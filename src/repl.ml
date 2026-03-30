type toplevel_plan = {
  target : Manifest.target;
  include_dirs : string list;
  package_resolution : Toolchain.package_resolution;
  env : (string * string) list;
  link_inputs : string list;
  toplevel_path : string;
  stamp_path : string;
  fingerprint : string;
}

let ( let* ) = Result.bind

type toplevel_build_status =
  | Built
  | Reused

type plan_status =
  | Build_needed
  | Reusable

type launch_plan = {
  toplevel : toplevel_plan;
  profile : string;
  toplevel_status : plan_status;
  runtime_args : string list;
  script_path : string option;
  stdin : string option;
}

let include_args include_dirs =
  List.concat_map (fun dir -> [ "-I"; dir ]) include_dirs

let append_line buffer line =
  Buffer.add_string buffer line;
  Buffer.add_char buffer '\n'

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
      | [] -> Error "workspace does not define any targets for wadi repl"
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

let toplevel_stamp_path ~workspace_root ~profile target =
  Layout.repl_stamp_path ~profile workspace_root (Manifest.target_name target)

let toplevel_fingerprint ?(allow_missing_inputs = false) ~session
    ~compiler_version target include_dirs package_resolution env link_inputs =
  let buffer = Buffer.create 256 in
  append_line buffer ("compiler-version " ^ compiler_version);
  append_line buffer ("tool ocamlmktop " ^ Toolchain.ocamlmktop_cmd ());
  append_line buffer ("target-kind " ^ Manifest.target_kind_name target);
  append_line buffer ("target-name " ^ Manifest.target_name target);
  List.iter (append_line buffer)
    (Toolchain.fingerprint_lines ~session package_resolution);
  List.iter
    (fun dir -> append_line buffer ("include-dir " ^ dir))
    include_dirs;
  List.iter
    (fun (name, value) -> append_line buffer ("env " ^ name ^ "=" ^ value))
    env;
  let* () =
    List.fold_left
      (fun result path ->
        let* () = result in
        if Fs.exists path then (
          append_line buffer
            ("input " ^ path ^ " " ^ Digest.to_hex (Digest.file path));
          Ok ())
        else if allow_missing_inputs then (
          append_line buffer ("input-missing " ^ path);
          Ok ())
        else Error (Printf.sprintf "repl input does not exist: %s" path))
      (Ok ()) link_inputs
  in
  Ok (Buffer.contents buffer)

let target_plan ~workspace_root ~verbose ~materialize_targets ?profile workspace
    requested_target =
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
    if materialize_targets then
      Builder.build ~workspace_root ~verbose ~requested_targets:[ requested_name ]
        ~backend_request ?profile:(Some profile) workspace
    else Ok { Builder.build_root = ""; artifacts = [] }
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
        let repl_dep_dirs =
          String_util.dedup_preserve
            (List.concat_map
               (fun dep_name ->
                 match Hashtbl.find_opt library_outputs dep_name with
                 | Some output -> output.out_dir :: output.transitive_include_dirs
                 | None -> [])
               library.Manifest.deps)
        in
        Hashtbl.replace library_outputs library.name
          {
            Builder.archive = description.archive;
            out_dir = description.out_dir;
            fingerprint = description.fingerprint;
            packages = description.effective_packages;
            transitive_include_dirs = repl_dep_dirs;
          };
        if library.name = requested_name then
          let closure =
            Builder.collect_dependency_closure index (Hashtbl.create 8)
              [ library.name ]
          in
          let link_inputs =
            library_outputs_for_names order closure library_outputs
          in
          let* fingerprint =
            toplevel_fingerprint ~allow_missing_inputs:(not materialize_targets)
              ~session ~compiler_version
              (Manifest.Library library) description.include_dirs
              description.package_resolution description.pipeline.options.env
              link_inputs
          in
          Ok
            {
              target = Manifest.Library library;
              include_dirs = description.include_dirs;
              package_resolution = description.package_resolution;
              env = description.pipeline.options.env;
              link_inputs;
              toplevel_path =
                toplevel_path ~workspace_root ~profile
                  (Manifest.Library library);
              stamp_path =
                toplevel_stamp_path ~workspace_root ~profile
                  (Manifest.Library library);
              fingerprint;
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
        let closure =
          Builder.collect_dependency_closure index (Hashtbl.create 8)
            executable.deps
        in
        let link_inputs =
          library_outputs_for_names order closure library_outputs
          @ helper_object_files description executable.main
        in
        let* fingerprint =
          toplevel_fingerprint ~allow_missing_inputs:(not materialize_targets)
            ~session ~compiler_version
            (Manifest.Executable executable) description.include_dirs
            description.package_resolution description.pipeline.options.env
            link_inputs
        in
        if executable.name = requested_name then
          Ok
            {
              target = Manifest.Executable executable;
              include_dirs = description.include_dirs;
              package_resolution = description.package_resolution;
              env = description.pipeline.options.env;
              link_inputs;
              toplevel_path =
                toplevel_path ~workspace_root ~profile
                  (Manifest.Executable executable);
              stamp_path =
                toplevel_stamp_path ~workspace_root ~profile
                  (Manifest.Executable executable);
              fingerprint;
            }
        else loop rest
    | Manifest.Test test :: rest ->
        let* description =
          Builder.describe_runnable ~mode:Builder.Plan_only ~session
            ~workspace_root ~verbose:false ~manifest_path ~backend_request
            ~backend ~compiler_version ~profile ~kind:Builder.Test_kind
            workspace test order index library_outputs
        in
        let closure =
          Builder.collect_dependency_closure index (Hashtbl.create 8) test.deps
        in
        let link_inputs =
          library_outputs_for_names order closure library_outputs
          @ helper_object_files description test.main
        in
        let* fingerprint =
          toplevel_fingerprint ~allow_missing_inputs:(not materialize_targets)
            ~session ~compiler_version (Manifest.Test test)
            description.include_dirs description.package_resolution
            description.pipeline.options.env link_inputs
        in
        if test.name = requested_name then
          Ok
            {
              target = Manifest.Test test;
              include_dirs = description.include_dirs;
              package_resolution = description.package_resolution;
              env = description.pipeline.options.env;
              link_inputs;
              toplevel_path =
                toplevel_path ~workspace_root ~profile (Manifest.Test test);
              stamp_path =
                toplevel_stamp_path ~workspace_root ~profile (Manifest.Test test);
              fingerprint;
            }
        else loop rest
  in
  loop order

let build_toplevel ~verbose (plan : toplevel_plan) =
  if
    Fs.exists plan.toplevel_path && Fs.exists plan.stamp_path
    && Fs.read_file plan.stamp_path = plan.fingerprint
  then Ok Reused
  else
    let () = Fs.ensure_dir (Filename.dirname plan.toplevel_path) in
    let* _ =
      Toolchain.ensure_success_ocamlmktop ~env:plan.env ~verbose
        plan.package_resolution
        (include_args plan.include_dirs
        @ Toolchain.link_args plan.package_resolution
        @ [ "-o"; plan.toplevel_path ]
        @ plan.link_inputs)
    in
    Fs.write_file plan.stamp_path plan.fingerprint;
    Ok Built

let plan_status (plan : toplevel_plan) =
  if
    Fs.exists plan.toplevel_path && Fs.exists plan.stamp_path
    && Fs.read_file plan.stamp_path = plan.fingerprint
  then Reusable
  else Build_needed

let resolve_script_path path =
  if Filename.is_relative path then Filename.concat (Sys.getcwd ()) path
  else path

let read_script path =
  let resolved_path = resolve_script_path path |> Fs.realpath in
  if not (Fs.exists resolved_path) then
    Error (Printf.sprintf "repl script does not exist: %s" path)
  else if Fs.is_directory resolved_path then
    Error (Printf.sprintf "repl script is a directory, not a file: %s" path)
  else Ok (resolved_path, Fs.read_file resolved_path)

let launch_plan ~workspace_root ~verbose ?profile ?target ?script_path ~args
    ~materialize_targets workspace =
  let* toplevel =
    target_plan ~workspace_root ~verbose ~materialize_targets ?profile workspace
      target
  in
  let* script_path, stdin =
    match script_path with
    | None -> Ok (None, None)
    | Some path ->
        let* resolved_path, contents = read_script path in
        Ok (Some resolved_path, Some contents)
  in
  Ok
    {
      toplevel;
      profile =
        (match profile with
        | Some profile when String.trim profile <> "" -> profile
        | Some _ | None -> Manifest.default_profile workspace);
      toplevel_status = plan_status toplevel;
      runtime_args = include_args toplevel.include_dirs @ args;
      script_path;
      stdin;
    }

let json_string text = "\"" ^ String_util.json_escape text ^ "\""

let json_array items = "[" ^ String.concat ", " items ^ "]"

let render_binding_json (name, value) =
  "{ \"name\": " ^ json_string name ^ ", \"value\": " ^ json_string value ^ " }"

let render_package_path_json (name, path) =
  "{ \"name\": " ^ json_string name ^ ", \"path\": " ^ json_string path ^ " }"

let merged_env env =
  Process.merged_environment_bindings env
  |> List.sort (fun (left, _) (right, _) -> String.compare left right)

let plan_status_name = function
  | Build_needed -> "build-needed"
  | Reusable -> "reusable"

let render_plan (plan : launch_plan) =
  let toplevel = plan.toplevel in
  let package_names = toplevel.package_resolution.Toolchain.packages in
  let package_paths = toplevel.package_resolution.Toolchain.package_paths in
  let env_overrides =
    match toplevel.env with
    | [] -> [ "Env-overrides: none" ]
    | bindings ->
        "Env-overrides:" :: List.map (fun (name, value) -> "  " ^ name ^ "=" ^ value) bindings
  in
  let package_lines =
    match package_paths with
    | [] ->
        [
          "Packages: "
          ^
          (match package_names with
          | [] -> "none"
          | names -> String.concat ", " names);
        ]
    | package_paths ->
        [
          "Packages: "
          ^
          (match package_names with
          | [] -> "none"
          | names -> String.concat ", " names);
          "Package-paths:";
        ]
        @ List.map
            (fun (name, path) -> "  " ^ name ^ " -> " ^ path)
            package_paths
  in
  String.concat "\n"
    ([
       "Profile: " ^ plan.profile;
       "Target: "
       ^ Manifest.target_kind_name toplevel.target
       ^ " "
       ^ Manifest.target_display_name toplevel.target;
       "Toplevel: " ^ toplevel.toplevel_path;
       "Toplevel-status: " ^ plan_status_name plan.toplevel_status;
       "Runtime-command: "
       ^ Process.render ~env:toplevel.env toplevel.toplevel_path plan.runtime_args;
       "Script-stdin: "
       ^
       (match plan.script_path with
       | Some path -> path
       | None -> "none");
       "Include-dirs:";
     ]
    @ List.map (fun dir -> "  " ^ dir) toplevel.include_dirs
    @ [ "Link-inputs:" ]
    @ List.map (fun path -> "  " ^ path) toplevel.link_inputs
    @ package_lines
    @ env_overrides
    @ [ "" ])

let render_json_plan (plan : launch_plan) =
  let toplevel = plan.toplevel in
  String.concat "\n"
    [
      "{";
      "  \"profile\": " ^ json_string plan.profile ^ ",";
      "  \"target\": {";
      "    \"kind\": "
      ^ json_string (Manifest.target_kind_name toplevel.target)
      ^ ",";
      "    \"name\": "
      ^ json_string (Manifest.target_name toplevel.target)
      ^ ",";
      "    \"display_name\": "
      ^ json_string (Manifest.target_display_name toplevel.target);
      "  },";
      "  \"toplevel_path\": " ^ json_string toplevel.toplevel_path ^ ",";
      "  \"toplevel_status\": "
      ^ json_string (plan_status_name plan.toplevel_status)
      ^ ",";
      "  \"runtime_args\": "
      ^ json_array (List.map json_string plan.runtime_args)
      ^ ",";
      "  \"runtime_command\": "
      ^ json_string
          (Process.render ~env:toplevel.env toplevel.toplevel_path plan.runtime_args)
      ^ ",";
      "  \"script_path\": "
      ^
      (match plan.script_path with
      | Some path -> json_string path
      | None -> "null")
      ^ ",";
      "  \"include_dirs\": "
      ^ json_array (List.map json_string toplevel.include_dirs)
      ^ ",";
      "  \"link_inputs\": "
      ^ json_array (List.map json_string toplevel.link_inputs)
      ^ ",";
      "  \"packages\": "
      ^ json_array
          (List.map json_string toplevel.package_resolution.Toolchain.packages)
      ^ ",";
      "  \"package_paths\": "
      ^ json_array
          (List.map render_package_path_json
             toplevel.package_resolution.Toolchain.package_paths)
      ^ ",";
      "  \"env_overrides\": "
      ^ json_array (List.map render_binding_json toplevel.env)
      ^ ",";
      "  \"env\": "
      ^ json_array (List.map render_binding_json (merged_env toplevel.env));
      "}";
      "";
    ]

let report ~workspace_root ~verbose ?profile ?target ?script_path ~args workspace =
  launch_plan ~workspace_root ~verbose ?profile ?target ?script_path ~args
    ~materialize_targets:false workspace

let run ~workspace_root ~verbose ?profile ?target ?script_path ~args workspace =
  let* plan =
    launch_plan ~workspace_root ~verbose ?profile ?target ?script_path ~args
      ~materialize_targets:true workspace
  in
  let* build_status = build_toplevel ~verbose plan.toplevel in
  print_endline
    (Printf.sprintf
       (match build_status with
       | Built -> "Built repl toplevel for %s %s -> %s"
       | Reused -> "Up to date repl toplevel for %s %s -> %s")
       (Manifest.target_kind_name plan.toplevel.target)
       (Manifest.target_display_name plan.toplevel.target)
       plan.toplevel.toplevel_path);
  print_endline
    (Printf.sprintf "Launching repl for %s %s -> %s"
       (Manifest.target_kind_name plan.toplevel.target)
       (Manifest.target_display_name plan.toplevel.target)
       plan.toplevel.toplevel_path);
  Ok
    (Process.run_status ~verbose ~env:plan.toplevel.env ?stdin:plan.stdin
       plan.toplevel.toplevel_path plan.runtime_args)
      .Process.unix_status
