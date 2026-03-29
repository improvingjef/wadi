type module_plan = {
  stem : string;
  dir : string;
  has_mli : bool;
}

type target_plan = {
  name : string;
  packages : string list;
  ordered_modules : module_plan list;
}

type workspace_plan = {
  common : target_plan;
  executable : target_plan;
  test : target_plan;
}

type module_owner = {
  kind : string;
  target_name : string;
  source_path : string;
}

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

let ordered_module_plans ~workspace_root ~target_kind ~target_name ~dir ~modules
    ~packages =
  let session = Toolchain.create_session () in
  let* package_resolution = Toolchain.resolve_packages ~session packages in
  let* sources =
    Builder.source_descriptors ~workspace_root
      ~generated_root:(Filename.concat workspace_root "_oasis-bootstrap-generated")
      ~dir modules
  in
  let* prepared_sources =
    Builder.prepare_sources ~workspace_root
      ~out_dir:(Filename.concat workspace_root "_oasis-bootstrap-preprocessed")
      ~target_env:[] [] sources
  in
  let* ordered =
    Builder.infer_module_order ~session ~verbose:false ~env:[] ~target_kind
      ~target_name package_resolution prepared_sources
  in
  let source_table : (string, Builder.source_descriptor) Hashtbl.t =
    Hashtbl.create (List.length sources)
  in
  List.iter
    (fun (source : Builder.source_descriptor) ->
      Hashtbl.replace source_table source.stem source)
    sources;
  let rec loop acc = function
    | [] -> Ok (List.rev acc)
    | stem :: rest -> (
        match Hashtbl.find_opt source_table stem with
        | Some source ->
            loop ({ stem = source.stem; dir; has_mli = source.has_mli } :: acc) rest
        | None ->
            Error
              (Printf.sprintf
                 "bootstrap planning lost source descriptor for module '%s'" stem))
  in
  loop [] ordered

let append_main_module ~workspace_root (runnable : Manifest.runnable)
    ordered_modules =
  let* main_source =
    Builder.source_descriptor ~workspace_root
      ~generated_root:(Filename.concat workspace_root "_oasis-bootstrap-generated")
      ~dir:runnable.dir
      runnable.main
  in
  Ok
    (ordered_modules
    @
    [
      {
        stem = main_source.stem;
        dir = runnable.dir;
        has_mli = main_source.has_mli;
      };
    ])

let ensure_unique_module_stems groups =
  let stems : (string, module_owner list) Hashtbl.t = Hashtbl.create 16 in
  let add_module kind target_name module_plan =
    let owner =
      {
        kind;
        target_name;
        source_path = Filename.concat module_plan.dir (module_plan.stem ^ ".ml");
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

let plan ~workspace_root workspace =
  let* _ = Builder.resolve_build_order workspace [] in
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
    find_single_target "test"
      (function
        | Manifest.Test test -> Some test
        | Manifest.Library _ | Manifest.Executable _ -> None)
      workspace
  in
  let library_target = Manifest.Library library in
  let executable_target = Manifest.Executable executable in
  let test_target = Manifest.Test test in
  let* common_packages = effective_packages index library_target in
  let* common_modules =
    ordered_module_plans ~workspace_root ~target_kind:"library"
      ~target_name:library.name ~dir:library.dir ~modules:library.modules
      ~packages:common_packages
  in
  let* executable_packages = effective_packages index executable_target in
  let* executable_modules =
    let* ordered =
      ordered_module_plans ~workspace_root ~target_kind:"executable"
        ~target_name:executable.name ~dir:executable.dir
        ~modules:executable.modules ~packages:executable_packages
    in
    append_main_module ~workspace_root executable ordered
  in
  let* test_packages = effective_packages index test_target in
  let* test_modules =
    let* ordered =
      ordered_module_plans ~workspace_root ~target_kind:"test"
        ~target_name:test.name ~dir:test.dir ~modules:test.modules
        ~packages:test_packages
    in
    append_main_module ~workspace_root test ordered
  in
  let* () =
    ensure_unique_module_stems
      [
        ("library", library.name, common_modules);
        ("executable", executable.name, executable_modules);
        ("test", test.name, test_modules);
      ]
  in
  Ok
    {
      common = { name = library.name; packages = common_packages; ordered_modules = common_modules };
      executable =
        {
          name = executable.name;
          packages = executable_packages;
          ordered_modules = executable_modules;
        };
      test = { name = test.name; packages = test_packages; ordered_modules = test_modules };
    }

let object_path stem = Printf.sprintf "$(OBJ_DIR)/%s.$(OBJ_EXT)" stem

let interface_path stem = Printf.sprintf "$(OBJ_DIR)/%s.cmi" stem

let object_list modules =
  String.concat " "
    (List.map (fun module_plan -> object_path module_plan.stem) modules)

let package_flags packages =
  let resolution : Toolchain.package_resolution = { packages; package_paths = [] } in
  String.concat " " (Toolchain.package_args resolution)

let link_flags packages =
  let resolution : Toolchain.package_resolution = { packages; package_paths = [] } in
  String.concat " " (Toolchain.link_args resolution)

let last = function
  | [] -> None
  | items -> Some (List.hd (List.rev items))

let rule_header target prerequisites =
  match prerequisites with
  | [] -> Printf.sprintf "%s: | $(OBJ_DIR)" target
  | prerequisites ->
      Printf.sprintf "%s: %s | $(OBJ_DIR)" target
        (String.concat " " prerequisites)

let compile_command prefix =
  Printf.sprintf "$(call BOOTSTRAP_TOOL_CMD,$(%s_PACKAGE_FLAGS)) $(OCAMLFLAGS) -I $(OBJ_DIR)"
    prefix

let link_command prefix =
  Printf.sprintf
    "$(call BOOTSTRAP_TOOL_CMD,$(%s_PACKAGE_FLAGS)) $(OCAMLFLAGS) -I $(OBJ_DIR) \
     $(%s_LINK_FLAGS)"
    prefix prefix

let source_path module_plan extension =
  Filename.concat module_plan.dir (module_plan.stem ^ extension)

let module_rules prefix predecessor module_plan =
  let previous_object =
    match predecessor with
    | None -> []
    | Some previous -> [ object_path previous.stem ]
  in
  let interface_rules =
    if module_plan.has_mli then
      [
        rule_header (interface_path module_plan.stem)
          (source_path module_plan ".mli" :: previous_object);
        ("\t" ^ compile_command prefix ^ " -c -o $@ $<");
        "";
      ]
    else []
  in
  let object_prerequisites =
    [ source_path module_plan ".ml" ]
    @ (if module_plan.has_mli then [ interface_path module_plan.stem ] else [])
    @ previous_object
  in
  interface_rules
  @
  [
    rule_header (object_path module_plan.stem) object_prerequisites;
    ("\t" ^ compile_command prefix ^ " -c -o $@ $<");
    "";
  ]

let group_rules prefix modules predecessor =
  let rec loop previous acc = function
    | [] -> List.rev acc
    | module_plan :: rest ->
        let rules = module_rules prefix previous module_plan in
        loop (Some module_plan) (List.rev_append rules acc) rest
  in
  loop predecessor [] modules

let render_makefile_from_plan plan =
  let common_objects = object_list plan.common.ordered_modules in
  let executable_objects = object_list plan.executable.ordered_modules in
  let test_objects = object_list plan.test.ordered_modules in
  let common_tail = last plan.common.ordered_modules in
  let lines =
    [
      "# Generated by scripts/generate_bootstrap_makefile.ml from oasis.toml.";
      "# Edit oasis.toml instead of this file.";
      ("COMMON_PACKAGE_FLAGS := " ^ package_flags plan.common.packages);
      ("APP_PACKAGE_FLAGS := " ^ package_flags plan.executable.packages);
      ("APP_LINK_FLAGS := " ^ link_flags plan.executable.packages);
      ("TEST_PACKAGE_FLAGS := " ^ package_flags plan.test.packages);
      ("TEST_LINK_FLAGS := " ^ link_flags plan.test.packages);
      ("COMMON_OBJS := " ^ common_objects);
      ("APP_OBJS := $(COMMON_OBJS)"
      ^ if executable_objects = "" then "" else " " ^ executable_objects);
      ("TEST_OBJS := $(COMMON_OBJS)"
      ^ if test_objects = "" then "" else " " ^ test_objects);
      "";
    ]
    @ group_rules "COMMON" plan.common.ordered_modules None
    @ group_rules "APP" plan.executable.ordered_modules common_tail
    @ group_rules "TEST" plan.test.ordered_modules common_tail
    @ [
        Printf.sprintf "$(BIN_DIR)/%s: $(APP_OBJS) | $(BIN_DIR)"
          plan.executable.name;
        ("\t" ^ link_command "APP" ^ " -o $@ $(APP_OBJS)");
        "";
        Printf.sprintf "$(BIN_DIR)/%s: $(TEST_OBJS) | $(BIN_DIR)" plan.test.name;
        ("\t" ^ link_command "TEST" ^ " -o $@ $(TEST_OBJS)");
      ]
  in
  String.concat "\n" lines ^ "\n"

let render_makefile ~manifest_path =
  let* workspace = Manifest.load manifest_path in
  let workspace_root = Fs.realpath (Filename.dirname manifest_path) in
  let* workspace_plan = plan ~workspace_root workspace in
  Ok (render_makefile_from_plan workspace_plan)
