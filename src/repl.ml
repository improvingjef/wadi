type plan = {
  target : Manifest.target;
  include_dirs : string list;
  package_resolution : Toolchain.package_resolution;
  env : (string * string) list;
  link_inputs : string list;
  toplevel_path : string;
}

let ( let* ) = Result.bind

let include_args include_dirs =
  List.concat_map (fun dir -> [ "-I"; dir ]) include_dirs

let resolve_profile workspace = function
  | Some profile when String.trim profile <> "" -> profile
  | Some _ | None -> Manifest.default_profile workspace

let libraries (workspace : Manifest.workspace) =
  List.filter_map
    (function
      | Manifest.Library library -> Some library
      | Manifest.Executable _ | Manifest.Test _ -> None)
    workspace.targets

let non_library_targets (workspace : Manifest.workspace) =
  List.filter
    (function
      | Manifest.Library _ -> false
      | Manifest.Executable _ | Manifest.Test _ -> true)
    workspace.targets

let named_target workspace name =
  List.find_opt
    (fun target -> Manifest.target_name target = name)
    workspace.Manifest.targets

let choose_default_target workspace =
  match libraries workspace with
  | [ library ] -> Ok (Manifest.Library library)
  | [] -> (
      match non_library_targets workspace with
      | [ target ] -> Ok target
      | [] -> Error "workspace does not define any targets for oasis repl"
      | targets ->
          Error
            (Printf.sprintf "workspace defines multiple targets; choose one: %s"
               (String.concat ", " (List.map Manifest.target_name targets))) )
  | libraries ->
      Error
        (Printf.sprintf "workspace defines multiple libraries; choose one: %s"
           (String.concat ", "
              (List.map (fun (library : Manifest.library) -> library.name) libraries)))

let resolve_target workspace requested_target =
  match requested_target with
  | Some name -> (
      match named_target workspace name with
      | Some target -> Ok target
      | None -> Error (Printf.sprintf "unknown target '%s'" name))
  | None -> choose_default_target workspace

let library_outputs_for_names order names
    (library_outputs : (string, Builder.built_library_output) Hashtbl.t) =
  List.filter_map
    (function
      | Manifest.Library library when Hashtbl.mem names library.name ->
          let output : Builder.built_library_output =
            Hashtbl.find library_outputs library.name
          in
          Some output.archive
      | Manifest.Library _ | Manifest.Executable _ | Manifest.Test _ -> None)
    order

let helper_object_files (description : Builder.runnable_description) main =
  let object_extension = Toolchain.object_extension Toolchain.Bytecode in
  description.source_order
  |> List.filter (fun stem -> stem <> main)
  |> List.map (fun stem ->
         Filename.concat description.out_dir (stem ^ object_extension))

let toplevel_path ~workspace_root ~profile target =
  Layout.repl_binary ~profile workspace_root (Manifest.target_name target)

let target_plan ~workspace_root ~verbose ?profile workspace requested_target =
  let workspace_root = Fs.realpath workspace_root in
  let manifest_path = Filename.concat workspace_root Manifest.default_filename in
  let session = Toolchain.create_session () in
  let profile = resolve_profile workspace profile in
  let* target = resolve_target workspace requested_target in
  let requested_name = Manifest.target_name target in
  let backend = Toolchain.Bytecode in
  let backend_request = Toolchain.Select backend in
  let* compiler_version = Toolchain.compiler_version ~session backend in
  let* order = Builder.resolve_build_order workspace [ requested_name ] in
  let index = Builder.index_targets workspace in
  let* _ =
    Builder.build ~workspace_root ~verbose ~requested_targets:[ requested_name ]
      ~backend_request ?profile:(Some profile) workspace
  in
  let library_outputs = Hashtbl.create 8 in
  let rec loop = function
    | [] ->
        Error
          (Printf.sprintf
             "internal error: failed to describe repl target '%s' after build"
             requested_name)
    | Manifest.Library library :: rest ->
        let* description =
          Builder.describe_library ~mode:Builder.Plan_only ~session
            ~workspace_root ~verbose:false ~manifest_path ~backend_request
            ~backend ~compiler_version ~profile workspace library
            library_outputs
        in
        Hashtbl.replace library_outputs library.name
          {
            Builder.archive = description.archive;
            out_dir = description.out_dir;
            fingerprint = description.fingerprint;
            packages = description.effective_packages;
          };
        if library.name = requested_name then
          let closure =
            Builder.collect_dependency_closure index (Hashtbl.create 8)
              [ library.name ]
          in
          Ok
            {
              target = Manifest.Library library;
              include_dirs = description.include_dirs;
              package_resolution = description.package_resolution;
              env = description.pipeline.options.env;
              link_inputs =
                library_outputs_for_names order closure library_outputs;
              toplevel_path =
                toplevel_path ~workspace_root ~profile
                  (Manifest.Library library);
            }
        else loop rest
    | Manifest.Executable executable :: rest ->
        let* description =
          Builder.describe_runnable ~mode:Builder.Plan_only ~session
            ~workspace_root ~verbose:false ~manifest_path ~backend_request
            ~backend ~compiler_version ~profile
            ~kind:Builder.Executable_kind workspace executable order index
            library_outputs
        in
        if executable.name = requested_name then
          let closure =
            Builder.collect_dependency_closure index (Hashtbl.create 8)
              executable.deps
          in
          Ok
            {
              target = Manifest.Executable executable;
              include_dirs = description.include_dirs;
              package_resolution = description.package_resolution;
              env = description.pipeline.options.env;
              link_inputs =
                library_outputs_for_names order closure library_outputs
                @ helper_object_files description executable.main;
              toplevel_path =
                toplevel_path ~workspace_root ~profile
                  (Manifest.Executable executable);
            }
        else loop rest
    | Manifest.Test test :: rest ->
        let* description =
          Builder.describe_runnable ~mode:Builder.Plan_only ~session
            ~workspace_root ~verbose:false ~manifest_path ~backend_request
            ~backend ~compiler_version ~profile ~kind:Builder.Test_kind
            workspace test order index library_outputs
        in
        if test.name = requested_name then
          let closure =
            Builder.collect_dependency_closure index (Hashtbl.create 8) test.deps
          in
          Ok
            {
              target = Manifest.Test test;
              include_dirs = description.include_dirs;
              package_resolution = description.package_resolution;
              env = description.pipeline.options.env;
              link_inputs =
                library_outputs_for_names order closure library_outputs
                @ helper_object_files description test.main;
              toplevel_path =
                toplevel_path ~workspace_root ~profile (Manifest.Test test);
            }
        else loop rest
  in
  loop order

let build_toplevel ~verbose (plan : plan) =
  let () = Fs.ensure_dir (Filename.dirname plan.toplevel_path) in
  Toolchain.ensure_success_ocamlmktop ~env:plan.env ~verbose
    plan.package_resolution
    (include_args plan.include_dirs
    @ Toolchain.link_args plan.package_resolution
    @ [ "-o"; plan.toplevel_path ]
    @ plan.link_inputs)

let run ~workspace_root ~verbose ?profile ?target ~args workspace =
  let* plan = target_plan ~workspace_root ~verbose ?profile workspace target in
  let* _ = build_toplevel ~verbose plan in
  let runtime_args = include_args plan.include_dirs @ args in
  print_endline
    (Printf.sprintf "Launching repl for %s %s -> %s"
       (Manifest.target_kind_name plan.target)
       (Manifest.target_display_name plan.target)
       plan.toplevel_path);
  Ok
    (Process.run_status ~verbose ~env:plan.env plan.toplevel_path runtime_args)
      .Process.unix_status
