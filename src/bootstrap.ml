type scope =
  | Executable_only
  | Full

type module_plan = {
  stem : string;
  logical_ml_path : string;
  logical_mli_path : string option;
  ml_path : string;
  mli_path : string option;
}

type target_plan = {
  name : string;
  packages : string list;
  compile_flags : string list;
  link_flags : string list;
  env : Manifest.env_binding list;
  ppx_tools : Manifest.ppx_tool list;
  ordered_modules : module_plan list;
}

type workspace_plan = {
  scope : scope;
  profile : string;
  inputs : string list;
  common : target_plan;
  executable : target_plan;
  test : target_plan option;
}

type module_owner = {
  kind : string;
  target_name : string;
  source_path : string;
}

type runnable_kind =
  | Executable_kind
  | Test_kind

let ( let* ) = Result.bind

let collect_results items f =
  let rec loop acc = function
    | [] -> Ok (List.rev acc)
    | item :: rest ->
        let* value = f item in
        loop (value :: acc) rest
  in
  loop [] items

let find_single_target label select workspace =
  match List.filter_map select workspace.Manifest.targets with
  | [ target ] -> Ok target
  | [] ->
      Error
        (Printf.sprintf
           "bootstrap manifest requires exactly one %s target, found none" label)
  | targets ->
      Error
        (Printf.sprintf
           "bootstrap manifest requires exactly one %s target, found %d" label
           (List.length targets))

let index_targets workspace =
  let table = Hashtbl.create (List.length workspace.Manifest.targets) in
  List.iter
    (fun target -> Hashtbl.replace table (Manifest.target_name target) target)
    workspace.Manifest.targets;
  table

let scope_name = function
  | Executable_only -> "app"
  | Full -> "full"

let runnable_kind_name = function
  | Executable_kind -> "executable"
  | Test_kind -> "test"

let resolve_profile workspace = function
  | Some profile when String.trim profile <> "" -> profile
  | Some _ | None -> Manifest.default_profile workspace

let normalize_workspace_root workspace_root =
  if String_util.ends_with ~suffix:"/" workspace_root then workspace_root
  else workspace_root ^ "/"

let workspace_relative_path ~workspace_root path =
  let normalized_root = normalize_workspace_root workspace_root in
  if String_util.starts_with ~prefix:normalized_root path then
    String.sub path (String.length normalized_root)
      (String.length path - String.length normalized_root)
  else path

let render_shell_words words =
  String.concat " " (List.map String_util.shell_quote words)

let render_env_prefix env =
  match env with
  | [] -> ""
  | env ->
      String.concat " "
        (List.map
           (fun (name, value) -> name ^ "=" ^ String_util.shell_quote value)
           env)
      ^ " "

let package_flags packages =
  let resolution : Toolchain.package_resolution = { packages; package_paths = [] } in
  String.concat " " (Toolchain.package_args resolution)

let link_flags packages extra_flags =
  let resolution : Toolchain.package_resolution = { packages; package_paths = [] } in
  String.concat " " (Toolchain.link_args resolution @ extra_flags)

let rec dependency_packages index seen name =
  if Hashtbl.mem seen name then Ok []
  else (
    Hashtbl.add seen name ();
    match Hashtbl.find_opt index name with
    | None ->
        Error
          (Printf.sprintf
             "bootstrap manifest refers to unknown dependency '%s'" name)
    | Some (Manifest.Library library) ->
        let* packages =
          collect_results library.deps (dependency_packages index seen)
        in
        Ok
          (String_util.dedup_preserve
             (library.packages @ List.concat packages))
    | Some target ->
        Error
          (Printf.sprintf
             "bootstrap manifest dependency '%s' resolved to %s; only libraries \
              can contribute bootstrap packages"
             name (Manifest.target_kind_name target)))

let effective_packages index target =
  let* packages =
    collect_results (Manifest.target_deps target)
      (dependency_packages index (Hashtbl.create 8))
  in
  Ok
    (String_util.dedup_preserve
       (Manifest.target_packages target @ List.concat packages))

let rec tracked_input_paths path =
  if not (Fs.exists path) then [ path ]
  else if Fs.is_directory path then
    let entries = Sys.readdir path |> Array.to_list |> List.sort String.compare in
    path :: List.concat_map (fun entry -> tracked_input_paths (Filename.concat path entry)) entries
  else [ path ]

let resolve_input_path ~workspace_root path =
  if Filename.is_relative path then Filename.concat workspace_root path else path

let existing_workspace_inputs ~workspace_root relative_path =
  let path = resolve_input_path ~workspace_root relative_path in
  if Fs.exists path then tracked_input_paths path else []

let command_input_paths ~workspace_root argv =
  match argv with
  | [] -> []
  | prog :: _ ->
      let path = Builder.resolve_command_prog ~workspace_root prog in
      if Fs.exists path && not (Fs.is_directory path) then tracked_input_paths path
      else []

let action_input_paths ~workspace_root (action : Manifest.action) =
  List.concat_map
    (command_input_paths ~workspace_root)
    (Manifest.action_commands action)
  @ List.concat_map
      (existing_workspace_inputs ~workspace_root)
      action.deps

let preprocessor_input_paths ~workspace_root (tool : Manifest.command_tool) =
  command_input_paths ~workspace_root tool.argv
  @ List.concat_map
      (existing_workspace_inputs ~workspace_root)
      tool.deps

let ppx_input_paths ~workspace_root (tool : Manifest.ppx_tool) =
  command_input_paths ~workspace_root tool.argv
  @ List.concat_map
      (existing_workspace_inputs ~workspace_root)
      tool.deps

let pipeline_input_paths ~workspace_root (pipeline : Builder.resolved_pipeline) =
  List.concat_map (action_input_paths ~workspace_root) pipeline.actions
  @ List.concat_map
      (preprocessor_input_paths ~workspace_root)
      pipeline.preprocessors
  @ List.concat_map (ppx_input_paths ~workspace_root) pipeline.ppx_tools

let source_input_paths ~workspace_root sources =
  sources
  |> List.concat_map (fun (source : Builder.source_descriptor) ->
         existing_workspace_inputs ~workspace_root source.ml_relative
         @
         if source.has_mli then
           existing_workspace_inputs ~workspace_root source.mli_relative
         else [])

let bootstrap_target_out_dir ~workspace_root ~profile target =
  Filename.concat workspace_root
    (Filename.concat "_bootstrap"
       (Filename.concat "materialized"
          (Filename.concat profile
             (Manifest.target_kind_name target ^ "-" ^ Manifest.target_name target))))

let ordered_module_plans ~workspace_root ordered_stems prepared_sources =
  let source_table : (string, Builder.prepared_source) Hashtbl.t =
    Hashtbl.create (List.length prepared_sources)
  in
  List.iter
    (fun (source : Builder.prepared_source) ->
      Hashtbl.replace source_table source.source.stem source)
    prepared_sources;
  let rec loop acc = function
    | [] -> Ok (List.rev acc)
    | stem :: rest -> (
        match Hashtbl.find_opt source_table stem with
        | Some source ->
            let module_plan =
              {
                stem = source.source.stem;
                logical_ml_path = source.source.ml_relative;
                logical_mli_path =
                  if source.source.has_mli then Some source.source.mli_relative
                  else None;
                ml_path =
                  workspace_relative_path ~workspace_root source.ml_compile_path;
                mli_path =
                  Option.map
                    (workspace_relative_path ~workspace_root)
                    source.mli_compile_path;
              }
            in
            loop (module_plan :: acc) rest
        | None ->
            Error
              (Printf.sprintf
                 "bootstrap planning lost source descriptor for module '%s'" stem))
  in
  loop [] ordered_stems

let ensure_unique_module_stems groups =
  let stems : (string, module_owner list) Hashtbl.t = Hashtbl.create 16 in
  let add_module kind target_name module_plan =
    let owner =
      {
        kind;
        target_name;
        source_path = module_plan.logical_ml_path;
      }
    in
    let previous =
      match Hashtbl.find_opt stems module_plan.stem with
      | Some owners -> owners
      | None -> []
    in
    Hashtbl.replace stems module_plan.stem (owner :: previous)
  in
  List.iter
    (fun (kind, target_name, modules) ->
      List.iter (add_module kind target_name) modules)
    groups;
  let duplicates =
    Hashtbl.fold
      (fun stem owners acc ->
        if List.length owners > 1 then (stem, List.rev owners) :: acc else acc)
      stems []
    |> List.sort (fun (left, _) (right, _) -> String.compare left right)
  in
  match duplicates with
  | [] -> Ok ()
  | duplicates ->
      let render_owner owner =
        Printf.sprintf "%s '%s' (%s)" owner.kind owner.target_name
          owner.source_path
      in
      let details =
        List.map
          (fun (stem, owners) ->
            Printf.sprintf "%s -> %s" stem
              (String.concat ", " (List.map render_owner owners)))
          duplicates
      in
      Error
        (Printf.sprintf
           "bootstrap manifest reuses module stems in the shared _bootstrap/obj \
            directory: %s"
           (String.concat "; " details))

let library_plan ~session ~workspace_root ~profile workspace index library =
  let target = Manifest.Library library in
  let out_dir = bootstrap_target_out_dir ~workspace_root ~profile target in
  let* packages = effective_packages index target in
  let* package_resolution = Toolchain.resolve_packages ~session packages in
  let* pipeline = Builder.resolve_pipeline ~workspace_root workspace ~profile target in
  let* () =
    Builder.validate_wrapped_library_source_conflicts ~workspace_root library
      pipeline.actions
  in
  let* _action_results =
    Builder.run_actions ~mode:Builder.Materialize ~workspace_root ~out_dir ~target
      ~pipeline
  in
  let* () =
    Builder.materialize_wrapped_library_source ~mode:Builder.Materialize
      ~workspace_root ~out_dir library
  in
  let* sources =
    Builder.library_source_descriptors ~workspace_root ~out_dir
      ~planned_generated_outputs:
        (Builder.wrapped_library_generated_outputs ~workspace_root library
        @ Builder.planned_generated_output_names pipeline.actions)
      library
  in
  let* prepared_sources =
    Builder.prepare_sources ~mode:Builder.Materialize ~workspace_root ~out_dir
      ~target_env:(pipeline.options.env)
      pipeline.preprocessors sources
  in
  let* ordered =
    Builder.infer_module_order ~session ~verbose:false ~env:(pipeline.options.env)
      ~target_kind:"library" ~target_name:library.name package_resolution
      prepared_sources
  in
  let* ordered_modules =
    ordered_module_plans ~workspace_root ordered prepared_sources
  in
  let inputs =
    source_input_paths ~workspace_root sources
    @ pipeline_input_paths ~workspace_root pipeline
  in
  Ok
    ( {
        name = library.name;
        packages;
        compile_flags = pipeline.options.compile_flags;
        link_flags = pipeline.options.link_flags;
        env = pipeline.options.env;
        ppx_tools = pipeline.ppx_tools;
        ordered_modules;
      },
      inputs )

let runnable_plan ~session ~workspace_root ~profile workspace index ~kind runnable =
  let target =
    match kind with
    | Executable_kind -> Manifest.Executable runnable
    | Test_kind -> Manifest.Test runnable
  in
  let out_dir = bootstrap_target_out_dir ~workspace_root ~profile target in
  let* packages = effective_packages index target in
  let* package_resolution = Toolchain.resolve_packages ~session packages in
  let* pipeline = Builder.resolve_pipeline ~workspace_root workspace ~profile target in
  let* _action_results =
    Builder.run_actions ~mode:Builder.Materialize ~workspace_root ~out_dir ~target
      ~pipeline
  in
  let* module_sources =
    Builder.source_descriptors ~workspace_root
      ~generated_root:(Builder.generated_root out_dir)
      ~planned_generated_outputs:
        (Builder.planned_generated_output_names pipeline.actions)
      ~dir:runnable.dir runnable.modules
  in
  let* main_source =
    Builder.source_descriptor ~workspace_root
      ~generated_root:(Builder.generated_root out_dir)
      ~planned_generated_outputs:
        (Builder.planned_generated_output_names pipeline.actions)
      ~dir:runnable.dir runnable.main
  in
  let all_sources = module_sources @ [ main_source ] in
  let* prepared_sources =
    Builder.prepare_sources ~mode:Builder.Materialize ~workspace_root ~out_dir
      ~target_env:(pipeline.options.env)
      pipeline.preprocessors all_sources
  in
  let module_prepared_sources =
    List.filter
      (fun (source : Builder.prepared_source) ->
        source.source.stem <> runnable.main)
      prepared_sources
  in
  let* ordered_modules =
    Builder.infer_module_order ~session ~verbose:false ~env:(pipeline.options.env)
      ~target_kind:(runnable_kind_name kind) ~target_name:runnable.name
      package_resolution module_prepared_sources
  in
  let source_order = ordered_modules @ [ runnable.main ] in
  let* ordered_sources =
    ordered_module_plans ~workspace_root source_order prepared_sources
  in
  let inputs =
    source_input_paths ~workspace_root all_sources
    @ pipeline_input_paths ~workspace_root pipeline
  in
  Ok
    ( {
        name = runnable.name;
        packages;
        compile_flags = pipeline.options.compile_flags;
        link_flags = pipeline.options.link_flags;
        env = pipeline.options.env;
        ppx_tools = pipeline.ppx_tools;
        ordered_modules = ordered_sources;
      },
      inputs )

let plan ~workspace_root ?profile ~scope workspace =
  let profile = resolve_profile workspace profile in
  let index = index_targets workspace in
  let* library =
    find_single_target "library"
      (function
        | Manifest.Library library -> Some library
        | Manifest.Executable _ | Manifest.Test _ -> None)
      workspace
  in
  let* executable =
    find_single_target "executable"
      (function
        | Manifest.Executable executable -> Some executable
        | Manifest.Library _ | Manifest.Test _ -> None)
      workspace
  in
  let* test =
    match scope with
    | Executable_only -> Ok None
    | Full ->
        let* test =
          find_single_target "test"
            (function
              | Manifest.Test test -> Some test
              | Manifest.Library _ | Manifest.Executable _ -> None)
            workspace
        in
        Ok (Some test)
  in
  let requested_targets =
    library.name :: executable.name
    ::
    (match test with
    | Some test -> [ test.name ]
    | None -> [])
  in
  let* _ = Builder.resolve_build_order workspace requested_targets in
  let session = Toolchain.create_session () in
  let* common, common_inputs =
    library_plan ~session ~workspace_root ~profile workspace index library
  in
  let* executable_plan, executable_inputs =
    runnable_plan ~session ~workspace_root ~profile workspace index
      ~kind:Executable_kind executable
  in
  let* test_plan, test_inputs =
    match test with
    | None -> Ok (None, [])
    | Some test ->
        let* plan, inputs =
          runnable_plan ~session ~workspace_root ~profile workspace index
            ~kind:Test_kind test
        in
        Ok (Some plan, inputs)
  in
  let* () =
    ensure_unique_module_stems
      ([
         ("library", library.name, common.ordered_modules);
         ("executable", executable.name, executable_plan.ordered_modules);
       ]
      @
      match test_plan with
      | Some test -> [ ("test", test.name, test.ordered_modules) ]
      | None -> [])
  in
  Ok
    {
      scope;
      profile;
      inputs =
        String_util.dedup_preserve
          (List.map
             (workspace_relative_path ~workspace_root)
             (common_inputs @ executable_inputs @ test_inputs));
      common;
      executable = executable_plan;
      test = test_plan;
    }

let object_path stem = Printf.sprintf "$(OBJ_DIR)/%s.$(OBJ_EXT)" stem

let interface_path stem = Printf.sprintf "$(OBJ_DIR)/%s.cmi" stem

let object_list modules =
  String.concat " "
    (List.map (fun module_plan -> object_path module_plan.stem) modules)

let last = function
  | [] -> None
  | items -> Some (List.hd (List.rev items))

let rule_header ?order_only target prerequisites =
  let order_only_suffix =
    match order_only with
    | Some directory -> " | " ^ directory
    | None -> ""
  in
  match prerequisites with
  | [] -> target ^ ":" ^ order_only_suffix
  | prerequisites ->
      Printf.sprintf "%s: %s%s" target (String.concat " " prerequisites)
        order_only_suffix

let compile_flags_value ~workspace_root target =
  let ppx_args = render_shell_words (Builder.ppx_args ~workspace_root target.ppx_tools) in
  String.concat " "
    (target.compile_flags
    @
    match ppx_args with
    | "" -> []
    | args -> [ args ])

let compile_command prefix target =
  render_env_prefix target.env
  ^ Printf.sprintf
      "$(call BOOTSTRAP_TOOL_CMD,$(%s_PACKAGE_FLAGS)) $(OCAMLFLAGS) -I $(OBJ_DIR) \
       $(%s_COMPILE_FLAGS)"
      prefix prefix

let link_command prefix target =
  render_env_prefix target.env
  ^ Printf.sprintf
      "$(call BOOTSTRAP_TOOL_CMD,$(%s_PACKAGE_FLAGS)) $(OCAMLFLAGS) -I $(OBJ_DIR) \
       $(%s_LINK_FLAGS)"
      prefix prefix

let module_rules prefix target predecessor module_plan =
  let previous_object =
    match predecessor with
    | None -> []
    | Some previous -> [ object_path previous.stem ]
  in
  let interface_rules =
    match module_plan.mli_path with
    | Some mli_path ->
        [
          rule_header ~order_only:"$(OBJ_DIR)"
            (interface_path module_plan.stem)
            (mli_path :: "$(BOOTSTRAP_MK)" :: previous_object);
          ("\t" ^ compile_command prefix target ^ " -c -o $@ $<");
          "";
        ]
    | None -> []
  in
  let object_prerequisites =
    [ module_plan.ml_path; "$(BOOTSTRAP_MK)" ]
    @
    (match module_plan.mli_path with
    | Some _ -> [ interface_path module_plan.stem ]
    | None -> [])
    @ previous_object
  in
  interface_rules
  @
  [
    rule_header ~order_only:"$(OBJ_DIR)" (object_path module_plan.stem)
      object_prerequisites;
    ("\t" ^ compile_command prefix target ^ " -c -o $@ $<");
    "";
  ]

let group_rules prefix target modules predecessor =
  let rec loop previous acc = function
    | [] -> List.rev acc
    | module_plan :: rest ->
        let rules = module_rules prefix target previous module_plan in
        loop (Some module_plan) (List.rev_append rules acc) rest
  in
  loop predecessor [] modules

let target_variable_lines ~workspace_root prefix target =
  [
    prefix ^ "_PACKAGE_FLAGS := " ^ package_flags target.packages;
    prefix ^ "_COMPILE_FLAGS := "
    ^ compile_flags_value ~workspace_root target;
    prefix ^ "_LINK_FLAGS := " ^ link_flags target.packages target.link_flags;
  ]

let render_makefile_from_plan ~workspace_root plan =
  let common_objects = object_list plan.common.ordered_modules in
  let executable_objects = object_list plan.executable.ordered_modules in
  let common_tail = last plan.common.ordered_modules in
  let test_lines =
    match plan.test with
    | None -> []
    | Some test ->
        let test_objects = object_list test.ordered_modules in
        target_variable_lines ~workspace_root "TEST" test
        @ [
            "TEST_OBJS := $(COMMON_OBJS)"
            ^ if test_objects = "" then "" else " " ^ test_objects;
            "";
          ]
        @ group_rules "TEST" test test.ordered_modules common_tail
        @ [
            rule_header ~order_only:"$(BIN_DIR)"
              (Printf.sprintf "$(BIN_DIR)/%s" test.name)
              [ "$(BOOTSTRAP_MK)"; "$(TEST_OBJS)" ];
            ("\t" ^ link_command "TEST" test ^ " -o $@ $(TEST_OBJS)");
          ]
  in
  let lines =
    [
      "# Generated by the oasis bootstrap planner from oasis.toml.";
      "# Edit oasis.toml instead of this file.";
      ("# Bootstrap scope: " ^ scope_name plan.scope);
      ("# Bootstrap profile: " ^ plan.profile);
      "";
      rule_header "$(BOOTSTRAP_MK)"
        ([ "$(BOOTSTRAP_MANIFEST)"; "$(BOOTSTRAP_GENERATOR)" ] @ plan.inputs);
      "";
    ]
    @ target_variable_lines ~workspace_root "COMMON" plan.common
    @ target_variable_lines ~workspace_root "APP" plan.executable
    @ [
        "COMMON_OBJS := " ^ common_objects;
        "APP_OBJS := $(COMMON_OBJS)"
        ^ if executable_objects = "" then "" else " " ^ executable_objects;
        "";
      ]
    @ group_rules "COMMON" plan.common plan.common.ordered_modules None
    @ group_rules "APP" plan.executable plan.executable.ordered_modules
        common_tail
    @ [
        rule_header ~order_only:"$(BIN_DIR)"
          (Printf.sprintf "$(BIN_DIR)/%s" plan.executable.name)
          [ "$(BOOTSTRAP_MK)"; "$(APP_OBJS)" ];
        ("\t" ^ link_command "APP" plan.executable ^ " -o $@ $(APP_OBJS)");
      ]
    @
    match test_lines with
    | [] -> []
    | lines -> "" :: lines
  in
  String.concat "\n" lines ^ "\n"

let render_makefile ?profile ?(scope = Full) ~manifest_path () =
  let* workspace = Manifest.load manifest_path in
  let workspace_root = Fs.realpath (Filename.dirname manifest_path) in
  let* workspace_plan = plan ~workspace_root ?profile ~scope workspace in
  Ok (render_makefile_from_plan ~workspace_root workspace_plan)

let hidden_command_name = "__bootstrap_makefile"

type command_options = {
  manifest_path : string;
  profile : string option;
  scope : scope;
}

let parse_scope value =
  match String.lowercase_ascii (String.trim value) with
  | "app" | "executable" -> Ok Executable_only
  | "full" -> Ok Full
  | value ->
      Error
        (Printf.sprintf
           "unknown scope '%s'; expected app, executable, or full" value)

let parse_command_args args =
  let rec loop options = function
    | [] -> Ok options
    | "--manifest" :: path :: rest ->
        loop { options with manifest_path = path } rest
    | "--manifest" :: [] -> Error "--manifest requires a path"
    | "--profile" :: profile :: rest ->
        loop { options with profile = Some profile } rest
    | "--profile" :: [] -> Error "--profile requires a name"
    | "--scope" :: value :: rest ->
        let* scope = parse_scope value in
        loop { options with scope } rest
    | "--scope" :: [] -> Error "--scope requires app, executable, or full"
    | "--help" :: _ ->
        Error
          "usage: oasis __bootstrap_makefile --manifest PATH [--profile NAME] [--scope app|executable|full]"
    | option :: _ when String_util.starts_with ~prefix:"-" option ->
        Error (Printf.sprintf "unknown option '%s'" option)
    | _ :: _ ->
        Error
          "oasis __bootstrap_makefile does not accept positional arguments"
  in
  loop
    { manifest_path = Manifest.default_filename; profile = None; scope = Full }
    args

let run_hidden_command args =
  match parse_command_args args with
  | Error message ->
      prerr_endline ("oasis bootstrap: " ^ message);
      2
  | Ok options -> (
      match
        render_makefile ?profile:options.profile ~scope:options.scope
          ~manifest_path:options.manifest_path ()
      with
      | Ok text ->
          print_string text;
          0
      | Error message ->
          prerr_endline ("oasis bootstrap: " ^ message);
          1)
