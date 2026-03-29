type context = {
  target : Manifest.target;
  profile : string;
  out_dir : string;
  include_dirs : string list;
  action_results : Builder.action_result list;
  pipeline : Builder.resolved_pipeline;
  package_resolution : Toolchain.package_resolution;
  sources : Builder.source_descriptor list;
}

type plan = {
  context : context;
  selected_source : Builder.source_descriptor option;
  interface : bool;
  prepared_path : string option;
  command : string option;
}

type applied = {
  plan : plan;
  output : string;
}

let ( let* ) = Result.bind

let render_names names =
  match names with
  | [] -> "none"
  | names -> String.concat ", " names

let describe_action_result (action_result : Builder.action_result) =
  let action_name =
    action_result.name ^ Manifest.package_suffix action_result.package_path
  in
  match action_result.execution with
  | Builder.Action_cached -> Printf.sprintf "- %s: cached" action_name
  | Builder.Action_regenerated reasons ->
      Printf.sprintf "- %s: regenerated (%s)" action_name (render_names reasons)
  | Builder.Action_planned reasons ->
      Printf.sprintf "- %s: planned (%s)" action_name (render_names reasons)

let resolve_target workspace target_name =
  match
    List.find_opt
      (fun target -> Manifest.target_name target = target_name)
      workspace.Manifest.targets
  with
  | Some target -> Ok target
  | None -> Error (Printf.sprintf "unknown target '%s'" target_name)

let target_sources ~mode ~workspace_root ~out_dir target pipeline =
  let planned_generated_outputs =
    match target with
    | Manifest.Library library ->
        Builder.wrapped_library_generated_outputs ~workspace_root library
        @ Builder.planned_generated_output_names pipeline.Builder.actions
    | Manifest.Executable _ | Manifest.Test _ ->
        Builder.planned_generated_output_names pipeline.Builder.actions
  in
  let* () =
    match target with
    | Manifest.Library library ->
        Builder.materialize_wrapped_library_source ~mode ~workspace_root ~out_dir
          library
    | Manifest.Executable _ | Manifest.Test _ -> Ok ()
  in
  match target with
  | Manifest.Library library ->
      Builder.library_source_descriptors ~workspace_root ~out_dir
        ~planned_generated_outputs library
  | Manifest.Executable executable ->
      Builder.source_descriptors ~workspace_root
        ~generated_root:(Builder.generated_root out_dir)
        ~planned_generated_outputs ~dir:executable.dir
        (executable.modules @ [ executable.main ])
  | Manifest.Test test ->
      Builder.source_descriptors ~workspace_root
        ~generated_root:(Builder.generated_root out_dir)
        ~planned_generated_outputs ~dir:test.dir
        (test.modules @ [ test.main ])

let package_resolution_for_target ~session workspace target_name =
  let* deps_report =
    Deps.report_for_targets ~session workspace [ target_name ]
  in
  match deps_report.targets with
  | [ target_report ] -> Ok target_report.package_resolution
  | [] ->
      Error
        (Printf.sprintf
           "internal error: dependency analysis returned no target for '%s'"
           target_name)
  | _ ->
      Error
        (Printf.sprintf
           "internal error: dependency analysis returned multiple targets for '%s'"
           target_name)

let include_dirs ~workspace_root ~profile workspace target out_dir =
  let target_index = Hashtbl.create (List.length workspace.Manifest.targets) in
  List.iter
    (fun target ->
      Hashtbl.replace target_index (Manifest.target_name target) target)
    workspace.Manifest.targets;
  out_dir
  ::
  List.filter_map
    (fun dependency_name ->
      match Hashtbl.find_opt target_index dependency_name with
      | Some (Manifest.Library _ as dependency) ->
          Some (Builder.target_out_dir ~profile workspace_root dependency)
      | Some (Manifest.Executable _) | Some (Manifest.Test _) | None -> None)
    (Manifest.target_deps target)

let build_context ~mode ~workspace_root ~verbose ~profile workspace target_name =
  let session = Toolchain.create_session () in
  let* target = resolve_target workspace target_name in
  let out_dir = Builder.target_out_dir ~profile workspace_root target in
  let include_dirs = include_dirs ~workspace_root ~profile workspace target out_dir in
  let* package_resolution =
    package_resolution_for_target ~session workspace target_name
  in
  let* pipeline =
    Builder.resolve_pipeline ~workspace_root workspace ~profile target
  in
  let* action_results =
    Builder.run_actions ~verbose ~mode ~workspace_root ~out_dir ~target ~pipeline
  in
  let* sources =
    target_sources ~mode ~workspace_root ~out_dir target pipeline
  in
  Ok
    {
      target;
      profile;
      out_dir;
      include_dirs;
      action_results;
      pipeline;
      package_resolution;
      sources;
    }

let select_source (context : context) module_name =
  match module_name with
  | None -> Ok None
  | Some module_name -> (
      match
        List.find_opt
          (fun (source : Builder.source_descriptor) -> source.stem = module_name)
          context.sources
      with
      | Some source -> Ok (Some source)
      | None ->
          Error
            (Printf.sprintf "target %s does not define module '%s'"
               (Manifest.target_display_name context.target)
               module_name) )

let prepare_source ~mode ~workspace_root (context : context) source ~interface =
  let* prepared =
    Builder.prepare_source ~mode ~workspace_root ~out_dir:context.out_dir
      ~target_env:(context.pipeline.options.env)
      context.pipeline.preprocessors source
  in
  if interface then
    match prepared.mli_compile_path with
    | Some path -> Ok path
    | None ->
        Error
          (Printf.sprintf "module '%s' does not define an interface"
             source.stem)
  else
    match prepared.ml_compile_path with
    | Some path -> Ok path
    | None ->
        Error
          (Printf.sprintf "module '%s' does not define an implementation"
             source.stem)

let dump_output_path (context : context) ~interface source_path =
  let stem = Filename.basename source_path |> Filename.remove_extension in
  Filename.concat context.out_dir
    (stem ^ ".ppx_dump." ^ if interface then "cmi" else "cmo")

let dump_args ~workspace_root context ~interface ~source_path =
  context.pipeline.options.compile_flags
  @ Builder.ppx_args ~workspace_root context.pipeline.ppx_tools
  @ [ "-c" ]
  @ Builder.include_args context.include_dirs
  @ [
      "-stop-after";
      "typing";
      "-dsource";
      "-o";
      dump_output_path context ~interface source_path;
      (if interface then "-intf" else "-impl");
      source_path;
    ]

let plan ~workspace_root ~verbose ?(interface = false) ?module_name
    ~profile workspace target_name =
  let* context =
    build_context ~mode:Builder.Plan_only ~workspace_root ~verbose ~profile
      workspace target_name
  in
  let* selected_source = select_source context module_name in
  let* prepared_path =
    match selected_source with
    | None -> Ok None
    | Some source ->
        let* prepared_path =
          prepare_source ~mode:Builder.Plan_only ~workspace_root context source
            ~interface
        in
        Ok (Some prepared_path)
  in
  let* command =
    match prepared_path with
    | None -> Ok None
    | Some prepared_path ->
        let session = Toolchain.create_session () in
        let* invocation =
          Toolchain.compiler_invocation ~session Toolchain.Bytecode
            context.package_resolution
            (dump_args ~workspace_root context ~interface
               ~source_path:prepared_path)
        in
        Ok
          (Some
             (Toolchain.render_invocation
                ~env:(context.pipeline.options.env)
                invocation))
  in
  Ok { context; selected_source; interface; prepared_path; command }

let apply ~workspace_root ~verbose ?(interface = false) ?output_path
    ~profile workspace target_name module_name =
  let* context =
    build_context ~mode:Builder.Materialize ~workspace_root ~verbose ~profile
      workspace target_name
  in
  let* selected_source =
    match select_source context (Some module_name) with
    | Ok (Some source) -> Ok source
    | Ok None ->
        Error
          "internal error: source selection returned none for a required module"
    | Error _ as error -> error
  in
  let* prepared_path =
    prepare_source ~mode:Builder.Materialize ~workspace_root context
      selected_source ~interface
  in
  let session = Toolchain.create_session () in
  let* invocation =
    Toolchain.compiler_invocation ~session Toolchain.Bytecode
      context.package_resolution
      (dump_args ~workspace_root context ~interface ~source_path:prepared_path)
  in
  let outcome =
    Process.run_capture ~verbose ~env:(context.pipeline.options.env)
      invocation.prog invocation.args
  in
  if outcome.status <> 0 then
    Error
      (Printf.sprintf "failed to dump transformed source for %s\n%s"
         (Manifest.target_display_name context.target) outcome.output)
  else
    let () =
      match output_path with
      | Some output_path -> Fs.write_file output_path outcome.output
      | None -> ()
    in
    Ok
      {
        plan =
          {
            context;
            selected_source = Some selected_source;
            interface;
            prepared_path = Some prepared_path;
            command =
              Some
                (Toolchain.render_invocation
                   ~env:(context.pipeline.options.env)
                   invocation);
          };
        output = outcome.output;
      }

let render_packages package_resolution =
  match package_resolution.Toolchain.package_paths with
  | [] -> [ "Packages: none" ]
  | package_paths ->
      "Packages:"
      :: List.map
           (fun (package_name, package_path) ->
             Printf.sprintf "  %s -> %s" package_name package_path)
           package_paths

let render_preprocessors ~workspace_root target_env preprocessors =
  match preprocessors with
  | [] -> [ "Preprocessors: none" ]
  | preprocessors ->
      "Preprocessors:"
      :: List.map
           (fun (tool : Manifest.command_tool) ->
             "  "
             ^ Builder.render_preprocessor_command ~workspace_root ~target_env
                 tool)
           preprocessors

let render_ppx_tools ~workspace_root ppx_tools =
  match ppx_tools with
  | [] -> [ "PPX: none" ]
  | ppx_tools ->
      "PPX:"
      :: List.map
           (fun (tool : Manifest.ppx_tool) ->
             Printf.sprintf "  %s deps: %s"
               (Builder.ppx_command_string ~workspace_root tool)
               (render_names tool.deps))
           ppx_tools

let render_modules sources =
  "Modules:"
  ::
  match sources with
  | [] -> [ "  none" ]
  | sources ->
      List.map
        (fun (source : Builder.source_descriptor) ->
          let shapes =
            (if source.has_ml then [ "ml" ] else [])
            @ (if source.has_mli then [ "mli" ] else [])
          in
          Printf.sprintf "  %s (%s)" source.stem (render_names shapes))
        sources

let render_actions action_results =
  match action_results with
  | [] -> [ "Actions: none" ]
  | action_results -> "Actions:" :: List.map describe_action_result action_results

let render_plan ~workspace_root (plan : plan) =
  let target = plan.context.target in
  let selection_lines =
    match (plan.selected_source, plan.prepared_path, plan.command) with
    | None, _, _ -> []
    | Some source, prepared_path, command ->
        [
          (if plan.interface then "Selected-interface: " else "Selected-module: ")
          ^ source.stem;
          (if plan.interface then "Source-path: " ^ source.mli_path
           else "Source-path: " ^ source.ml_path);
        ]
        @ (match prepared_path with
          | Some prepared_path -> [ "Prepared-source: " ^ prepared_path ]
          | None -> [])
        @
        (match command with
        | Some command -> [ "Compiler-command: " ^ command ]
        | None -> [])
  in
  String.concat "\n"
    ([
       "Target: " ^ Manifest.target_display_name target;
       "Kind: " ^ Manifest.target_kind_name target;
       "Profile: " ^ plan.context.profile;
       "Out-dir: " ^ plan.context.out_dir;
     ]
    @ render_packages plan.context.package_resolution
    @ render_actions plan.context.action_results
    @ render_preprocessors ~workspace_root
        (plan.context.pipeline.options.env)
        plan.context.pipeline.preprocessors
    @ render_ppx_tools ~workspace_root plan.context.pipeline.ppx_tools
    @ render_modules plan.context.sources
    @ selection_lines
    @ [ "" ])

let render_applied_report output_path (applied : applied) =
  let source_label =
    match applied.plan.selected_source with
    | Some source -> source.stem
    | None -> "unknown"
  in
  match output_path with
  | Some output_path ->
      Printf.sprintf "Wrote transformed source for %s.%s -> %s\n"
        (Manifest.target_display_name applied.plan.context.target)
        source_label output_path
  | None -> applied.output
