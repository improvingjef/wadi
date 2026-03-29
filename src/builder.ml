type built_artifact =
  | Built_library of {
      name : string;
      out_dir : string;
      archive : string;
    }
  | Built_executable of {
      name : string;
      out_dir : string;
      binary : string;
    }
  | Built_test of {
      name : string;
      out_dir : string;
      binary : string;
    }

type build_result = {
  build_root : string;
  artifacts : built_artifact list;
}

type built_library_output = {
  archive : string;
  out_dir : string;
  fingerprint : string;
  packages : string list;
}

type source_descriptor = {
  stem : string;
  ml_path : string;
  ml_relative : string;
  ml_exists : bool;
  mli_path : string;
  mli_relative : string;
  mli_exists : bool;
  has_mli : bool;
}

type prepared_source = {
  source : source_descriptor;
  ml_compile_path : string;
  mli_compile_path : string option;
}

type resolved_pipeline = {
  options : Manifest.target_options;
  actions : Manifest.action list;
  preprocessors : Manifest.command_tool list;
  ppx_tools : Manifest.ppx_tool list;
}

type action_execution =
  | Action_cached
  | Action_regenerated of string list
  | Action_planned of string list

type action_result = {
  name : string;
  package_path : string option;
  fingerprint : string;
  output_paths : string list;
  execution : action_execution;
}

type pipeline_mode =
  | Materialize
  | Plan_only

type explain_report = {
  target_name : string;
  report : string;
  json_report : string;
}

type library_description = {
  out_dir : string;
  archive : string;
  fingerprint : string;
  effective_packages : string list;
  status : Explain.target_status;
  report : string;
  json_report : string;
  prepared_sources : prepared_source list;
  ordered_modules : string list;
  package_resolution : Toolchain.package_resolution;
  include_dirs : string list;
  pipeline : resolved_pipeline;
}

type runnable_description = {
  out_dir : string;
  binary : string;
  fingerprint : string;
  status : Explain.target_status;
  report : string;
  json_report : string;
  prepared_sources : prepared_source list;
  source_order : string list;
  package_resolution : Toolchain.package_resolution;
  include_dirs : string list;
  archive_files : string list;
  pipeline : resolved_pipeline;
}

let ( let* ) = Result.bind

let target_name = Manifest.target_name

let dependency_names = Manifest.target_deps

let build_root_for_profile = Layout.build_root_for_profile

let target_out_dir = Layout.target_out_dir

let generated_root out_dir = Filename.concat out_dir "generated"

let preprocessed_root out_dir = Filename.concat out_dir "preprocessed"

let action_stamp_path out_dir name =
  Filename.concat (Filename.concat out_dir "actions") (name ^ ".stamp")

let index_targets workspace =
  let table = Hashtbl.create (List.length workspace.Manifest.targets) in
  List.iter
    (fun target -> Hashtbl.add table (target_name target) target)
    workspace.Manifest.targets;
  table

let resolve_build_order workspace requested_targets =
  let index = index_targets workspace in
  let requested =
    if requested_targets = [] then
      List.map target_name workspace.Manifest.targets
    else String_util.dedup_preserve requested_targets
  in
  let visited = Hashtbl.create (List.length workspace.Manifest.targets) in
  let order = ref [] in
  let rec visit path name =
    if List.mem name path then
      Error
        (Printf.sprintf "dependency cycle detected: %s"
           (String.concat " -> " (path @ [ name ])))
    else if Hashtbl.mem visited name then Ok ()
    else
      match Hashtbl.find_opt index name with
      | None -> Error (Printf.sprintf "unknown target '%s'" name)
      | Some target ->
          let* () =
            List.fold_left
              (fun result dependency ->
                let* () = result in
                match Hashtbl.find_opt index dependency with
                | None ->
                    Error
                      (Printf.sprintf "target '%s' depends on unknown target '%s'"
                         name dependency)
                | Some dependency_target -> (
                    match dependency_target with
                    | Manifest.Library _ -> visit (path @ [ name ]) dependency
                    | _ ->
                        Error
                          (Printf.sprintf
                             "target '%s' depends on %s '%s'; only libraries may \
                              be dependencies"
                             name
                             (Manifest.target_kind_name dependency_target)
                             dependency)))
              (Ok ()) (dependency_names target)
          in
          Hashtbl.add visited name ();
          order := target :: !order;
          Ok ()
  in
  let* () =
    List.fold_left
      (fun result name ->
        let* () = result in
        visit [] name)
      (Ok ()) requested
  in
  Ok (List.rev !order)

let append_line buffer line =
  Buffer.add_string buffer line;
  Buffer.add_char buffer '\n'

let collect_results items f =
  let rec loop acc = function
    | [] -> Ok (List.rev acc)
    | item :: rest ->
        let* value = f item in
        loop (value :: acc) rest
  in
  loop [] items

let collect_line_groups items f =
  let* groups = collect_results items f in
  Ok (List.concat groups)

let resolve_command_prog ~workspace_root prog =
  if Filename.is_relative prog && String.contains prog '/' then
    Filename.concat workspace_root prog
  else prog

let command_prog_and_args argv =
  match argv with
  | [] -> failwith "internal error: empty command argv"
  | prog :: args -> (prog, args)

let command_cwd ~workspace_root ~default_dir = function
  | Some dir -> Filename.concat workspace_root dir
  | None -> default_dir

let command_fingerprint_lines ~workspace_root argv =
  match argv with
  | [] -> []
  | prog :: args ->
      let resolved_prog = resolve_command_prog ~workspace_root prog in
      let argv_lines =
        ("argv " ^ resolved_prog)
        :: List.map (fun arg -> "arg " ^ arg) args
      in
      let digest_lines =
        if Sys.file_exists resolved_prog && not (Sys.is_directory resolved_prog) then
          [ "prog-digest " ^ Digest.to_hex (Digest.file resolved_prog) ]
        else []
      in
      argv_lines @ digest_lines

let ppx_command_string ~workspace_root (tool : Manifest.ppx_tool) =
  let prog, args = command_prog_and_args tool.Manifest.argv in
  let resolved_prog = resolve_command_prog ~workspace_root prog in
  String.concat " "
    (List.map String_util.shell_quote (resolved_prog :: args))

let sandbox_name = function
  | Manifest.Workspace -> "workspace"
  | Manifest.Target -> "target"

let effective_sandbox (options : Manifest.target_options)
    (action : Manifest.action) =
  match action.Manifest.sandbox with
  | Some sandbox -> sandbox
  | None -> (
      match options.Manifest.sandbox with
      | Some sandbox -> sandbox
      | None -> Manifest.Target)

let is_source_path path =
  List.exists
    (fun suffix -> String_util.ends_with ~suffix path)
    [ ".ml"; ".mli" ]

let rec digest_path path =
  if Sys.is_directory path then
    let entries = Sys.readdir path |> Array.to_list |> List.sort String.compare in
    let buffer = Buffer.create 256 in
    List.iter
      (fun name ->
        append_line buffer ("entry " ^ name);
        append_line buffer (digest_path (Filename.concat path name)))
      entries;
    "dir:" ^ Digest.to_hex (Digest.string (Buffer.contents buffer))
  else "file:" ^ Digest.to_hex (Digest.file path)

let fingerprint_dependency_line prefix relative_path path =
  prefix ^ " " ^ relative_path ^ " " ^ digest_path path

let dependency_fingerprint_lines ~workspace_root ~line_prefix ~error_label deps =
  collect_results deps (fun relative_path ->
      let path = Filename.concat workspace_root relative_path in
      if not (Fs.exists path) then
        Error (Printf.sprintf "%s does not exist: %s" error_label relative_path)
      else Ok (fingerprint_dependency_line line_prefix relative_path path))

let tool_dependency_fingerprint_lines ~workspace_root ~line_prefix ~error_label
    tool_name deps =
  collect_results deps (fun relative_path ->
      let path = Filename.concat workspace_root relative_path in
      if not (Fs.exists path) then
        Error
          (Printf.sprintf "%s '%s' dependency does not exist: %s" error_label tool_name
             relative_path)
      else
        Ok
          (fingerprint_dependency_line
             (line_prefix ^ " " ^ tool_name) relative_path path))

let action_output_paths out_dir (action : Manifest.action) =
  let root = generated_root out_dir in
  List.map (fun output -> Filename.concat root output) action.outputs

let planned_generated_output_names actions =
  List.concat_map
    (fun (action : Manifest.action) -> action.outputs)
    actions
  |> String_util.dedup_preserve

let wrapped_library_stems (library : Manifest.library) =
  if library.wrapped then [ library.name ] else []

let wrapped_library_generated_outputs (library : Manifest.library) =
  List.map (fun stem -> stem ^ ".ml") (wrapped_library_stems library)

let wrapped_library_module_name stem = String.capitalize_ascii stem

let wrapped_library_source_contents (library : Manifest.library) =
  String.concat "\n"
    ([
       Printf.sprintf "(* Generated by oasis for wrapped library %s. *)"
         library.name;
     ]
    @ List.map
        (fun stem ->
          let module_name = wrapped_library_module_name stem in
          "module " ^ module_name ^ " = " ^ module_name)
        library.modules
    @ [ "" ])

let validate_wrapped_library_source_conflicts ~workspace_root
    (library : Manifest.library) (actions : Manifest.action list) =
  if not library.wrapped then Ok ()
  else if List.mem library.name library.modules then
    Error
      (Printf.sprintf
         "library '%s' sets wrapped = true, but modules already include the \
          reserved wrapper stem '%s'"
         library.name library.name)
  else
    let wrapper_ml = library.name ^ ".ml" in
    let wrapper_mli = library.name ^ ".mli" in
    let workspace_wrapper_ml =
      Filename.concat workspace_root (Filename.concat library.dir wrapper_ml)
    in
    let workspace_wrapper_mli =
      Filename.concat workspace_root (Filename.concat library.dir wrapper_mli)
    in
    if Fs.exists workspace_wrapper_ml then
      Error
        (Printf.sprintf
           "library '%s' sets wrapped = true, but %s already exists; wrapped \
            libraries reserve module stem '%s' for the generated wrapper"
           library.name workspace_wrapper_ml library.name)
    else if Fs.exists workspace_wrapper_mli then
      Error
        (Printf.sprintf
           "library '%s' sets wrapped = true, but %s already exists; wrapped \
            libraries reserve module stem '%s' for the generated wrapper"
           library.name workspace_wrapper_mli library.name)
    else
      let rec find_conflicting_action = function
        | [] -> None
        | (action : Manifest.action) :: rest ->
            if List.mem wrapper_ml action.outputs || List.mem wrapper_mli action.outputs
            then Some (action, if List.mem wrapper_ml action.outputs then wrapper_ml else wrapper_mli)
            else find_conflicting_action rest
      in
      match find_conflicting_action actions with
      | Some (action, output) ->
          Error
            (Printf.sprintf
               "library '%s' sets wrapped = true, but action '%s' also \
                declares output '%s'; wrapped libraries reserve module stem \
                '%s' for the generated wrapper"
               library.name action.name output library.name)
      | None -> Ok ()

let materialize_wrapped_library_source ~mode ~out_dir (library : Manifest.library)
    =
  if (not library.wrapped) || mode = Plan_only then Ok ()
  else
    let path =
      Filename.concat (generated_root out_dir) (library.name ^ ".ml")
    in
    let contents = wrapped_library_source_contents library in
    if Fs.exists path && Fs.read_file path = contents then Ok ()
    else (
      Fs.write_file path contents;
      Ok ())

let source_descriptor ~workspace_root ~generated_root ~planned_generated_outputs
    ~dir stem =
  let ml_relative = Filename.concat dir (stem ^ ".ml") in
  let workspace_ml_path = Filename.concat workspace_root ml_relative in
  let generated_ml_path = Filename.concat generated_root (stem ^ ".ml") in
  let generated_ml_declared =
    List.mem (stem ^ ".ml") planned_generated_outputs
  in
  let ml_path =
    if Fs.exists generated_ml_path || generated_ml_declared then generated_ml_path
    else workspace_ml_path
  in
  let ml_exists = Fs.exists ml_path in
  let mli_relative = Filename.concat dir (stem ^ ".mli") in
  let workspace_mli_path = Filename.concat workspace_root mli_relative in
  let generated_mli_path = Filename.concat generated_root (stem ^ ".mli") in
  let generated_mli_declared =
    List.mem (stem ^ ".mli") planned_generated_outputs
  in
  let mli_path =
    if Fs.exists generated_mli_path || generated_mli_declared then generated_mli_path
    else workspace_mli_path
  in
  let mli_exists = Fs.exists mli_path in
  if (not ml_exists) && not generated_ml_declared then
    Error
      (Printf.sprintf "missing source file for module '%s': %s" stem ml_path)
  else
    Ok
      {
        stem;
        ml_path;
        ml_relative;
        ml_exists;
        mli_path;
        mli_relative;
        mli_exists;
        has_mli = mli_exists || generated_mli_declared;
      }

let source_descriptors ~workspace_root ~generated_root ~planned_generated_outputs
    ~dir stems =
  collect_results stems
    (source_descriptor ~workspace_root ~generated_root ~planned_generated_outputs
       ~dir)

let library_source_descriptors ~workspace_root ~out_dir ~planned_generated_outputs
    (library : Manifest.library) =
  source_descriptors ~workspace_root ~generated_root:(generated_root out_dir)
    ~planned_generated_outputs ~dir:library.dir
    (library.modules @ wrapped_library_stems library)

let prepared_source_files prepared_source =
  match prepared_source.mli_compile_path with
  | Some mli_path -> [ mli_path; prepared_source.ml_compile_path ]
  | None -> [ prepared_source.ml_compile_path ]

let ordered_source_table sources =
  let table = Hashtbl.create (List.length sources) in
  List.iter (fun source -> Hashtbl.replace table source.source.stem source) sources;
  table

let infer_module_order_from_files ~session ~verbose ~env ~target_kind
    ~target_name package_resolution requested source_files =
  let* sorted_paths =
    match
      Toolchain.sort_sources ~session ~env ~verbose package_resolution source_files
    with
    | Ok sorted_paths -> Ok sorted_paths
    | Error message ->
        Error
          (Printf.sprintf
             "%s '%s' failed module dependency inference:\n%s" target_kind
             target_name message)
  in
  let sorted_stems =
    sorted_paths
    |> List.filter_map (fun path ->
           let stem = Filename.basename path |> Filename.remove_extension in
           if List.mem stem requested then Some stem else None)
    |> String_util.dedup_preserve
  in
  if List.length sorted_stems = List.length requested then Ok sorted_stems
  else
    Error
      (Printf.sprintf
         "%s '%s' failed to infer a complete module order for %s from ocamldep"
         target_kind target_name (String.concat ", " requested))

let infer_module_order ~session ~verbose ~env ~target_kind ~target_name
    package_resolution sources =
  if sources = [] then Ok []
  else
    let requested = List.map (fun source -> source.source.stem) sources in
    let source_files = List.concat_map prepared_source_files sources in
    infer_module_order_from_files ~session ~verbose ~env ~target_kind
      ~target_name package_resolution requested source_files

let dry_run_module_order ~session ~verbose ~env ~target_kind ~target_name
    ~preprocessors package_resolution sources =
  if sources = [] then Ok []
  else if preprocessors <> [] then
    Ok (List.map (fun source -> source.source.stem) sources)
  else
    let requested = List.map (fun source -> source.source.stem) sources in
    let source_files =
      List.concat_map
        (fun source ->
          (if source.source.mli_exists then [ source.source.mli_path ] else [])
          @
          (if source.source.ml_exists then [ source.source.ml_path ] else []))
        sources
    in
    if List.length source_files <> List.length (List.concat_map prepared_source_files sources)
    then Ok requested
    else
      match
        infer_module_order_from_files ~session ~verbose ~env ~target_kind
          ~target_name package_resolution requested source_files
      with
      | Ok ordered -> Ok ordered
      | Error _ -> Ok requested

let target_is_up_to_date ~stamp_path expected_outputs fingerprint =
  Fs.exists stamp_path && List.for_all Fs.exists expected_outputs
  && Fs.read_file stamp_path = fingerprint

let target_fingerprint ~session ~manifest_path ~compiler_version ~profile_name
    ~kind_name ~target_name ~backend ~dir ~main ~ordered_modules ~sources
    ~package_resolution ~dependency_fingerprints ~extra_lines =
  let buffer = Buffer.create 512 in
  append_line buffer ("compiler " ^ compiler_version);
  append_line buffer ("backend " ^ Toolchain.backend_name backend);
  append_line buffer ("profile " ^ profile_name);
  append_line buffer ("manifest " ^ Digest.to_hex (Digest.file manifest_path));
  append_line buffer ("kind " ^ kind_name);
  append_line buffer ("target " ^ target_name);
  append_line buffer ("dir " ^ dir);
  (match main with
  | None -> ()
  | Some stem -> append_line buffer ("main " ^ stem));
  List.iter
    (fun stem -> append_line buffer ("module " ^ stem))
    ordered_modules;
  List.iter (append_line buffer)
    (Toolchain.fingerprint_lines ~session package_resolution @ extra_lines);
  List.iter
    (fun source ->
      append_line buffer
        (Printf.sprintf "ml %s %s" source.ml_relative
           (if source.ml_exists then Digest.to_hex (Digest.file source.ml_path)
            else "planned-generated"));
      append_line buffer
        (Printf.sprintf "mli %s %s" source.mli_relative
           (if source.mli_exists then Digest.to_hex (Digest.file source.mli_path)
            else if source.has_mli then "planned-generated"
            else "missing")))
    sources;
  List.iter
    (fun (dependency_name, dependency_fingerprint) ->
      append_line buffer
        (Printf.sprintf "dep %s %s" dependency_name
           (Digest.to_hex (Digest.string dependency_fingerprint))))
    dependency_fingerprints;
  Buffer.contents buffer

let copy_path ~src ~dst =
  if Sys.is_directory src then Fs.copy_tree ~src ~dst else Fs.copy_file ~src ~dst

let materialize_path ~src ~dst =
  if Sys.is_directory src then Fs.materialize_tree ~src ~dst
  else Fs.materialize_file ~src ~dst

let copy_relative_path ~workspace_root ~sandbox_root ~label relative_path =
  let src = Filename.concat workspace_root relative_path in
  if not (Fs.exists src) then
    Error
      (Printf.sprintf "%s path does not exist: %s" label relative_path)
  else (
    copy_path ~src ~dst:(Filename.concat sandbox_root relative_path);
    Ok ())

let with_temp_dir prefix f =
  let path = Filename.temp_file prefix ".tmp" in
  Unix.unlink path;
  Unix.mkdir path 0o755;
  Fun.protect ~finally:(fun () -> Fs.remove_tree path) (fun () -> f path)

let prepare_action_sandbox ~workspace_root ~target_dir action sandbox_root sandbox =
  match sandbox with
  | Manifest.Workspace ->
      Fs.materialize_tree ~src:workspace_root ~dst:sandbox_root;
      let artifact_root = Filename.concat sandbox_root "_oasis" in
      if Fs.exists artifact_root then Fs.remove_tree artifact_root;
      Ok ()
  | Manifest.Target ->
      let sandbox_target_dir = Filename.concat sandbox_root target_dir in
      let workspace_target_dir = Filename.concat workspace_root target_dir in
      let* () =
        if Fs.exists workspace_target_dir then
          if Sys.is_directory workspace_target_dir then (
            Fs.materialize_tree ~src:workspace_target_dir ~dst:sandbox_target_dir;
            Ok ())
          else
            Error
              (Printf.sprintf "target dir exists and is not a directory: %s"
                 workspace_target_dir)
        else (
          Fs.ensure_dir sandbox_target_dir;
          Ok ())
      in
      let copied = Hashtbl.create 16 in
      let copy_once label relative_path =
        if Hashtbl.mem copied relative_path then Ok ()
        else (
          Hashtbl.add copied relative_path ();
          let src = Filename.concat workspace_root relative_path in
          if not (Fs.exists src) then
            Error
              (Printf.sprintf "%s path does not exist: %s" label relative_path)
          else (
            materialize_path ~src
              ~dst:(Filename.concat sandbox_root relative_path);
            Ok ()))
      in
      let* () =
        match action.Manifest.cwd with
        | Some cwd when cwd <> "." && cwd <> target_dir ->
            copy_once "action cwd" cwd
        | Some _ | None -> Ok ()
      in
      let* () =
        let prog, _ = command_prog_and_args action.Manifest.argv in
        if Filename.is_relative prog && String.contains prog '/' then
          copy_once "action program" prog
        else Ok ()
      in
      List.fold_left
        (fun result dep ->
          let* () = result in
          copy_once "action dependency" dep)
        (Ok ()) action.Manifest.deps

let validate_generated_source_collisions ~workspace_root ~target_dir ~target_name
    actions =
  List.fold_left
    (fun result (action : Manifest.action) ->
      let* () = result in
      let action_name = (action : Manifest.action).name in
      List.fold_left
        (fun result output ->
          let* () = result in
          if not (is_source_path output) then Ok ()
          else
            let workspace_output_path =
              Filename.concat workspace_root (Filename.concat target_dir output)
            in
            if Fs.exists workspace_output_path then
              Error
                (Printf.sprintf
                   "target '%s' action '%s' output '%s' collides with checked-in \
                    source %s"
                   target_name action_name output workspace_output_path)
            else Ok ())
        (Ok ()) action.Manifest.outputs)
    (Ok ()) actions

let action_fingerprint ~workspace_root ~target_env ~target_dir options
    (action : Manifest.action) =
  let sandbox = effective_sandbox options action in
  let env = Manifest.merge_env_bindings target_env action.env in
  let buffer = Buffer.create 256 in
  append_line buffer ("sandbox " ^ sandbox_name sandbox);
  append_line buffer ("target-dir " ^ target_dir);
  (match action.cwd with
  | Some cwd -> append_line buffer ("cwd " ^ cwd)
  | None -> ());
  (match action.stdin with
  | Some stdin -> append_line buffer ("stdin " ^ Digest.to_hex (Digest.string stdin))
  | None -> ());
  List.iter (append_line buffer)
    (command_fingerprint_lines ~workspace_root action.argv);
  List.iter
    (fun (name, value) -> append_line buffer ("env " ^ name ^ "=" ^ value))
    env;
  List.iter (fun output -> append_line buffer ("output " ^ output))
    action.outputs;
  let* dependency_lines =
    dependency_fingerprint_lines ~workspace_root ~line_prefix:"dep"
      ~error_label:"action dependency" action.deps
  in
  List.iter (append_line buffer) dependency_lines;
  Ok (Buffer.contents buffer)

let run_action ~workspace_root ~out_dir ~target_dir ~target_env options
    (action : Manifest.action) =
  let* fingerprint =
    action_fingerprint ~workspace_root ~target_env ~target_dir options action
  in
  let generated_dir = generated_root out_dir in
  let output_paths = action_output_paths out_dir action in
  let stamp_path = action_stamp_path out_dir action.name in
  let missing_outputs =
    List.filter (fun path -> not (Fs.exists path)) output_paths
  in
  let regeneration_reasons =
    (if Fs.exists stamp_path then [] else [ "action stamp missing: " ^ action.name ])
    @ List.map
        (fun path ->
          Printf.sprintf "missing generated output: %s (%s)" path action.name)
        missing_outputs
  in
  Fs.ensure_dir (Filename.dirname stamp_path);
  if target_is_up_to_date ~stamp_path output_paths fingerprint then
    Ok
      {
        name = action.name;
        package_path = action.package_path;
        fingerprint;
        output_paths;
        execution = Action_cached;
      }
  else
    let sandbox = effective_sandbox options action in
    let env = Manifest.merge_env_bindings target_env action.env in
    let prog, args = command_prog_and_args action.argv in
    let prog = resolve_command_prog ~workspace_root prog in
    with_temp_dir "oasis-action" (fun sandbox_root ->
        let* () =
          prepare_action_sandbox ~workspace_root ~target_dir action sandbox_root
            sandbox
        in
        let default_cwd = Filename.concat sandbox_root target_dir in
        let cwd =
          match action.cwd with
          | Some cwd -> Filename.concat sandbox_root cwd
          | None -> default_cwd
        in
        let* _ =
          Process.ensure_success ~cwd ~env ?stdin:action.stdin prog args
        in
        Fs.ensure_dir generated_dir;
        let sandbox_target_dir = Filename.concat sandbox_root target_dir in
        let* () =
          List.fold_left
            (fun result output ->
              let* () = result in
              let src = Filename.concat sandbox_target_dir output in
              let dst = Filename.concat generated_dir output in
              if not (Fs.exists src) then
                Error
                  (Printf.sprintf
                     "action '%s' did not produce declared output %s"
                     action.name output)
              else (
                if Fs.exists dst then Fs.remove_tree dst;
                copy_path ~src ~dst;
                Ok ()))
            (Ok ()) action.outputs
        in
        Fs.write_file stamp_path fingerprint;
        Ok
          {
            name = action.name;
            package_path = action.package_path;
            fingerprint;
            output_paths;
            execution =
              Action_regenerated
                (match String_util.dedup_preserve regeneration_reasons with
                | [] -> [ "action changed: " ^ action.name ]
                | reasons -> reasons);
          })

let plan_action ~workspace_root ~out_dir ~target_dir ~target_env options
    (action : Manifest.action) =
  let* fingerprint =
    action_fingerprint ~workspace_root ~target_env ~target_dir options action
  in
  let output_paths = action_output_paths out_dir action in
  let stamp_path = action_stamp_path out_dir action.name in
  let missing_outputs =
    List.filter (fun path -> not (Fs.exists path)) output_paths
  in
  let execution =
    if target_is_up_to_date ~stamp_path output_paths fingerprint then Action_cached
    else
      Action_planned
        ((if Fs.exists stamp_path then [] else [ "action stamp missing: " ^ action.name ])
        @ List.map
            (fun path ->
              Printf.sprintf "missing generated output: %s (%s)" path action.name)
            missing_outputs)
  in
  Ok
    {
      name = action.name;
      package_path = action.package_path;
      fingerprint;
      output_paths;
      execution;
    }

let resolve_pipeline ~workspace_root workspace ~profile target =
  let* options = Manifest.resolve_target_options workspace profile target in
  let package_path = Manifest.target_package_path target in
  let* actions =
    collect_results options.actions (fun name ->
        match Manifest.find_action workspace ?package_path name with
        | Some action -> Ok action
        | None ->
            Error
              (Printf.sprintf "target '%s' references unknown action '%s'"
                 (Manifest.target_name target) name))
  in
  let* preprocessors =
    collect_results options.preprocess (fun name ->
        match Manifest.find_preprocessor workspace ?package_path name with
        | Some tool -> Ok tool
        | None ->
            Error
              (Printf.sprintf "target '%s' references unknown preprocessor '%s'"
                 (Manifest.target_name target) name))
  in
  let* ppx_tools =
    collect_results options.ppx (fun name ->
        match Manifest.find_ppx_tool workspace ?package_path name with
        | Some tool -> Ok tool
        | None ->
            Error
              (Printf.sprintf "target '%s' references unknown ppx '%s'"
                 (Manifest.target_name target) name))
  in
  let output_seen = Hashtbl.create 16 in
  let* () =
    List.fold_left
      (fun result action ->
        let* () = result in
        List.fold_left
          (fun result output ->
            let* () = result in
            if Hashtbl.mem output_seen output then
              Error
                (Printf.sprintf
                   "target '%s' declares action output '%s' more than once"
                   (Manifest.target_name target) output)
            else (
              Hashtbl.add output_seen output ();
              Ok ()))
          (Ok ()) action.Manifest.outputs)
      (Ok ()) actions
  in
  let* () =
    validate_generated_source_collisions ~workspace_root
      ~target_dir:(Manifest.target_dir target)
      ~target_name:(Manifest.target_name target) actions
  in
  Ok { options; actions; preprocessors; ppx_tools }

let run_actions ~mode ~workspace_root ~out_dir ~target ~pipeline =
  Fs.ensure_dir out_dir;
  let target_env = pipeline.options.env in
  let options = pipeline.options in
  collect_results pipeline.actions (fun action ->
      match mode with
      | Materialize ->
          run_action ~workspace_root ~out_dir ~target_dir:(Manifest.target_dir target)
            ~target_env options action
      | Plan_only ->
          plan_action ~workspace_root ~out_dir
            ~target_dir:(Manifest.target_dir target)
            ~target_env options action)

let run_preprocessor ~workspace_root ~target_env (tool : Manifest.command_tool)
    input =
  let env = Manifest.merge_env_bindings target_env tool.Manifest.env in
  let prog, args = command_prog_and_args tool.Manifest.argv in
  let prog = resolve_command_prog ~workspace_root prog in
  let cwd =
    command_cwd ~workspace_root ~default_dir:workspace_root tool.Manifest.cwd
  in
  let* outcome = Process.ensure_success ~cwd ~env ~stdin:input prog args in
  Ok outcome.Process.output

let planned_preprocessed_path out_dir logical_path =
  Filename.concat (preprocessed_root out_dir) logical_path

let preprocess_source_path ~mode ~workspace_root ~out_dir ~target_env
    (preprocessors : Manifest.command_tool list) logical_path source_path =
  if preprocessors = [] then Ok source_path
  else if mode = Plan_only then
    Ok (planned_preprocessed_path out_dir logical_path)
  else
    let* output =
      List.fold_left
        (fun result tool ->
          let* input = result in
          run_preprocessor ~workspace_root ~target_env tool input)
        (Ok (Fs.read_file source_path)) preprocessors
    in
    let path = planned_preprocessed_path out_dir logical_path in
    Fs.write_file path output;
    Ok path

let prepare_source ~mode ~workspace_root ~out_dir ~target_env
    (preprocessors : Manifest.command_tool list) source =
  let logical_ml_path = Filename.basename source.ml_relative in
  let* ml_compile_path =
    preprocess_source_path ~mode ~workspace_root ~out_dir ~target_env
      preprocessors logical_ml_path source.ml_path
  in
  let* mli_compile_path =
    match source.has_mli with
    | false -> Ok None
    | true ->
        let logical_mli_path = Filename.basename source.mli_relative in
        let* path =
          preprocess_source_path ~mode ~workspace_root ~out_dir ~target_env
            preprocessors logical_mli_path source.mli_path
        in
        Ok (Some path)
  in
  Ok { source; ml_compile_path; mli_compile_path }

let prepare_sources ~mode ~workspace_root ~out_dir ~target_env
    (preprocessors : Manifest.command_tool list) sources =
  collect_results sources
    (prepare_source ~mode ~workspace_root ~out_dir ~target_env preprocessors)

let expected_module_outputs backend out_dir stem =
  match backend with
  | Toolchain.Native ->
      [
        Filename.concat out_dir (stem ^ ".cmi");
        Filename.concat out_dir (stem ^ ".cmx");
        Filename.concat out_dir (stem ^ ".o");
      ]
  | Toolchain.Bytecode ->
      [
        Filename.concat out_dir (stem ^ ".cmi");
        Filename.concat out_dir (stem ^ ".cmo");
      ]

let ppx_args ~workspace_root (ppx_tools : Manifest.ppx_tool list) =
  List.concat_map
    (fun tool -> [ "-ppx"; ppx_command_string ~workspace_root tool ])
    ppx_tools

let include_args include_dirs =
  List.concat_map (fun dir -> [ "-I"; dir ]) include_dirs

let interface_compile_args ~workspace_root ~out_dir ~include_dirs ~compile_flags
    ~(ppx_tools : Manifest.ppx_tool list) source mli_compile_path =
  compile_flags @ ppx_args ~workspace_root ppx_tools
  @ [ "-c" ]
  @ include_args include_dirs
  @ [ "-o"; Filename.concat out_dir (source.source.stem ^ ".cmi"); mli_compile_path ]

let implementation_compile_args ~workspace_root ~backend ~out_dir ~include_dirs
    ~compile_flags ~(ppx_tools : Manifest.ppx_tool list) source =
  compile_flags @ ppx_args ~workspace_root ppx_tools
  @ [ "-c" ]
  @ include_args include_dirs
  @
  [
    "-o";
    Filename.concat out_dir (source.source.stem ^ Toolchain.object_extension backend);
    source.ml_compile_path;
  ]

let render_preprocessor_command ~workspace_root ~target_env
    (tool : Manifest.command_tool) =
  let env = Manifest.merge_env_bindings target_env tool.Manifest.env in
  let prog, args = command_prog_and_args tool.Manifest.argv in
  let prog = resolve_command_prog ~workspace_root prog in
  let cwd =
    command_cwd ~workspace_root ~default_dir:workspace_root tool.Manifest.cwd
  in
  Process.render ~cwd ~env prog args

let render_module_order_command ~session ~env ~package_resolution source_files =
  match source_files with
  | [] -> Ok "module-order not needed"
  | _ ->
      let* invocation =
        Toolchain.ocamldep_invocation ~session package_resolution
          ("-sort" :: source_files)
      in
      Ok (Toolchain.render_invocation ~env invocation)

let dry_run_module_order_command ~session ~env ~package_resolution
    ~preprocessors source_files =
  if source_files = [] then Ok "module-order not needed"
  else if preprocessors <> [] || List.exists (fun path -> not (Fs.exists path)) source_files then
    Ok
      "module-order fallback: dry-run kept source transforms side-effect-free, \
       so declared module order is shown"
  else render_module_order_command ~session ~env ~package_resolution source_files

let render_compile_commands ~session ~workspace_root ~backend ~out_dir
    ~include_dirs ~package_resolution ~compile_flags
    ~(ppx_tools : Manifest.ppx_tool list) ~env source_table ordered_stems =
  let rec loop acc = function
    | [] -> Ok (List.rev acc)
    | stem :: rest ->
        let source =
          match Hashtbl.find_opt source_table stem with
          | Some source -> source
          | None ->
              failwith
                (Printf.sprintf
                   "internal error: missing prepared source for '%s'" stem)
        in
        let* commands =
          match source.mli_compile_path with
          | Some mli_compile_path ->
              let* invocation =
                Toolchain.compiler_invocation ~session backend package_resolution
                  (interface_compile_args ~workspace_root ~out_dir ~include_dirs
                     ~compile_flags ~ppx_tools source mli_compile_path)
              in
              Ok
                [
                  Printf.sprintf "compile %s.mli: %s" source.source.stem
                    (Toolchain.render_invocation ~env invocation);
                ]
          | None -> Ok []
        in
        let* invocation =
          Toolchain.compiler_invocation ~session backend package_resolution
            (implementation_compile_args ~workspace_root ~backend ~out_dir
               ~include_dirs ~compile_flags ~ppx_tools source)
        in
        loop
          (Printf.sprintf "compile %s.ml: %s" source.source.stem
             (Toolchain.render_invocation ~env invocation)
          :: List.rev_append commands acc)
          rest
  in
  loop [] ordered_stems

let compile_module ~session ~workspace_root ~verbose ~backend ~out_dir
    ~include_dirs
    ~package_resolution ~compile_flags
    ~(ppx_tools : Manifest.ppx_tool list) ~env source =
  let* () =
    match source.mli_compile_path with
    | Some mli_compile_path ->
        let* _ =
          Toolchain.ensure_success_compiler ~session ~env ~verbose backend
            package_resolution
            (interface_compile_args ~workspace_root ~out_dir ~include_dirs
               ~compile_flags ~ppx_tools source mli_compile_path)
        in
        Ok ()
    | None -> Ok ()
  in
  let* _ =
    Toolchain.ensure_success_compiler ~session ~env ~verbose backend
      package_resolution
      (implementation_compile_args ~workspace_root ~backend ~out_dir
         ~include_dirs ~compile_flags ~ppx_tools source)
  in
  Ok
    (Filename.concat out_dir
       (source.source.stem ^ Toolchain.object_extension backend))

let compile_ordered_sources ~session ~workspace_root ~verbose ~backend ~out_dir
    ~include_dirs ~package_resolution ~compile_flags
    ~(ppx_tools : Manifest.ppx_tool list) ~env source_table
    ordered_stems =
  let rec loop acc = function
    | [] -> Ok (List.rev acc)
    | stem :: rest ->
        let source =
          match Hashtbl.find_opt source_table stem with
          | Some source -> source
          | None ->
              failwith
                (Printf.sprintf
                   "internal error: missing prepared source for '%s'" stem)
        in
        let* object_file =
          compile_module ~session ~workspace_root ~verbose ~backend ~out_dir
            ~include_dirs ~package_resolution ~compile_flags ~ppx_tools ~env
            source
        in
        loop (object_file :: acc) rest
  in
  loop [] ordered_stems

let rec collect_dependency_closure index acc = function
  | [] -> acc
  | name :: rest ->
      if Hashtbl.mem acc name then collect_dependency_closure index acc rest
      else (
        Hashtbl.add acc name ();
        match Hashtbl.find_opt index name with
        | Some target ->
            collect_dependency_closure index acc (dependency_names target @ rest)
        | None -> acc)

let action_execution_reasons = function
  | Action_cached -> []
  | Action_regenerated reasons | Action_planned reasons -> reasons

let generated_source_reason_overrides ~target_dir (actions : Manifest.action list) =
  List.concat_map
    (fun (action : Manifest.action) ->
      List.concat_map
        (fun output ->
          let logical_path = Filename.concat target_dir output in
          let ml_reasons = [ "source changed: " ^ logical_path ] in
          if Filename.check_suffix output ".mli" then
            ml_reasons
            @
            [
              "interface changed: " ^ logical_path;
              "interface availability changed: " ^ logical_path;
            ]
          else ml_reasons)
        action.outputs)
    actions
  |> String_util.dedup_preserve

let include_action_execution_reasons ?(generated_source_reasons = []) status
    action_results =
  let action_reasons =
    action_results
    |> List.concat_map (fun (action_result : action_result) ->
           action_execution_reasons action_result.execution)
    |> String_util.dedup_preserve
  in
  match action_reasons with
  | [] -> status
  | reasons ->
      let remaining_reasons =
        List.filter
          (fun reason -> not (List.mem reason generated_source_reasons))
          status.Explain.reasons
        |> String_util.dedup_preserve
      in
      if
        status.Explain.build_status = Explain.Reused
        || (status.Explain.build_status = Explain.Rebuilt
           && remaining_reasons = [])
      then
        ({
           Explain.build_status = Explain.Regenerated;
           Explain.reasons = reasons;
         }
          : Explain.target_status)
      else
        ({
           Explain.build_status = status.Explain.build_status;
           Explain.reasons =
             String_util.dedup_preserve (remaining_reasons @ reasons);
         }
          : Explain.target_status)

let target_extra_lines ~workspace_root ~profile pipeline action_results =
  let option_lines =
    [
      "profile " ^ profile;
      "sandbox "
      ^
      (match pipeline.options.sandbox with
      | Some sandbox -> sandbox_name sandbox
      | None -> "target");
    ]
    @ List.map (fun flag -> "compile-flag " ^ flag) pipeline.options.compile_flags
    @ List.map (fun flag -> "link-flag " ^ flag) pipeline.options.link_flags
    @ List.map
        (fun (name, value) -> "env " ^ name ^ "=" ^ value)
        pipeline.options.env
  in
  let* preprocessor_lines =
    collect_line_groups pipeline.preprocessors
      (fun (tool : Manifest.command_tool) ->
        let* dependency_lines =
          tool_dependency_fingerprint_lines ~workspace_root
            ~line_prefix:"preprocess-dep" ~error_label:"preprocessor" tool.name
            tool.deps
        in
        Ok
          (("preprocess " ^ tool.name)
          :: (match tool.cwd with
             | Some cwd -> [ "preprocess-cwd " ^ cwd ]
             | None -> [])
          @ List.map
              (fun (name, value) ->
                "preprocess-env " ^ tool.name ^ " " ^ name ^ "=" ^ value)
              tool.env
          @ command_fingerprint_lines ~workspace_root tool.argv
          @ dependency_lines))
  in
  let* ppx_lines =
    collect_line_groups pipeline.ppx_tools
      (fun (tool : Manifest.ppx_tool) ->
        let* dependency_lines =
          tool_dependency_fingerprint_lines ~workspace_root
            ~line_prefix:"ppx-dep" ~error_label:"ppx" tool.name tool.deps
        in
        Ok
          (("ppx " ^ tool.name)
          :: command_fingerprint_lines ~workspace_root tool.argv
          @ dependency_lines))
  in
  let action_lines =
    List.map
      (fun action_result ->
        "action "
        ^ action_result.name
        ^ Manifest.package_suffix action_result.package_path
        ^ " "
        ^ Digest.to_hex (Digest.string action_result.fingerprint))
      action_results
  in
  Ok (option_lines @ preprocessor_lines @ ppx_lines @ action_lines)

let backend_selection_note ~session request backend =
  match request with
  | Toolchain.Select _ ->
      Printf.sprintf "selected %s because it was requested explicitly"
        (Toolchain.backend_name backend)
  | Toolchain.Auto -> (
      match backend with
      | Toolchain.Native ->
          "auto selected native because ocamlopt is available"
      | Toolchain.Bytecode ->
          if
            Toolchain.command_is_available ~session
              (Toolchain.compiler_cmd Toolchain.Native)
          then "auto selected bytecode despite a working native compiler"
          else "auto selected bytecode because ocamlopt is unavailable")

let joined_names names =
  match names with
  | [] -> "none"
  | names -> String.concat ", " names

let render_action_resolution_lines (action : Manifest.action) =
  let name = Manifest.action_display_name action in
  [
    "action " ^ name ^ " outputs: " ^ joined_names action.outputs;
    "action " ^ name ^ " deps: " ^ joined_names action.deps;
  ]
  @
  (match action.cwd with
  | Some cwd -> [ "action " ^ name ^ " cwd: " ^ cwd ]
  | None -> [])

let render_preprocessor_resolution_lines (tool : Manifest.command_tool) =
  let name = Manifest.command_tool_display_name tool in
  [
    "preprocess " ^ name ^ " deps: " ^ joined_names tool.deps;
  ]
  @
  (match tool.cwd with
  | Some cwd -> [ "preprocess " ^ name ^ " cwd: " ^ cwd ]
  | None -> [])

let render_ppx_resolution_lines (tool : Manifest.ppx_tool) =
  [ "ppx " ^ Manifest.ppx_tool_display_name tool ^ " deps: " ^ joined_names tool.deps ]

let target_resolution_lines ~session ~backend_request ~backend ~compiler_version
    ~package_resolution (pipeline : resolved_pipeline) =
  let stdlib_line =
    match Toolchain.stdlib_dir ~session () with
    | Ok path -> "stdlib: " ^ path
    | Error message -> "stdlib-error: " ^ String.trim message
  in
  let unix_line =
    match Toolchain.stdlib_dir ~session () with
    | Ok stdlib_dir -> (
        match
          Toolchain.resolve_library_dir ~exists:Sys.file_exists ~stdlib_dir
            "unix"
        with
        | Some path -> "unix-library-dir: " ^ path
        | None -> "unix-library-dir: unavailable")
    | Error message -> "unix-library-dir-error: " ^ String.trim message
  in
  let package_lines =
    match package_resolution.Toolchain.package_paths with
    | [] -> [ "packages: none" ]
    | package_paths ->
        List.map
          (fun (package_name, package_path) ->
            Printf.sprintf "package: %s -> %s" package_name package_path)
          package_paths
  in
  [
    "backend-request: " ^ Toolchain.backend_request_name backend_request;
    "selected-backend: " ^ Toolchain.backend_name backend;
    "backend-selection: " ^ backend_selection_note ~session backend_request backend;
    "compiler-version: " ^ compiler_version;
    Toolchain.render_command_report "compiler"
      (Toolchain.configured_command_report ~session
         (Toolchain.compiler_cmd backend));
    Toolchain.render_command_report "ocamldep"
      (Toolchain.configured_command_report ~session (Toolchain.ocamldep_cmd ()));
    stdlib_line;
    unix_line;
    "actions: "
    ^ joined_names
        (List.map
           Manifest.action_display_name
           pipeline.actions);
    "preprocessors: "
    ^ joined_names
        (List.map
           Manifest.command_tool_display_name
           pipeline.preprocessors);
  ]
  @ List.concat_map render_action_resolution_lines pipeline.actions
  @ List.concat_map render_preprocessor_resolution_lines pipeline.preprocessors
  @ [
    "ppx: "
    ^ joined_names
        (List.map
           Manifest.ppx_tool_display_name
           pipeline.ppx_tools);
  ]
  @ List.concat_map render_ppx_resolution_lines pipeline.ppx_tools
  @
  if package_resolution.Toolchain.packages = [] then []
  else
    [
      Toolchain.render_command_report "ocamlfind"
        (Toolchain.resolved_ocamlfind_report ~session ());
    ]
    @ package_lines

let target_command_lines ~workspace_root pipeline action_results
    ~module_order_command ~compile_commands ~link_command =
  List.map
    (fun (action_result : action_result) ->
      "action "
      ^ action_result.name
      ^ Manifest.package_suffix action_result.package_path
      ^ ": "
      ^
      match action_result.execution with
      | Action_cached -> "cached"
      | Action_regenerated _ -> "ran"
      | Action_planned _ -> "planned")
    action_results
  @ List.map
      (fun (tool : Manifest.command_tool) ->
        "preprocess " ^ tool.name ^ ": "
        ^ render_preprocessor_command ~workspace_root
            ~target_env:(pipeline.options.env) tool)
      pipeline.preprocessors
  @ ("module-order: " ^ module_order_command)
    :: compile_commands
  @ [ "link: " ^ link_command ]

let render_link_command ~session ~env ~backend ~package_resolution args =
  let* invocation =
    Toolchain.compiler_invocation ~session backend package_resolution args
  in
  Ok (Toolchain.render_invocation ~env invocation)

let write_target_report out_dir report json_report =
  Fs.write_file (Layout.explain_path out_dir) report;
  Fs.write_file (Layout.explain_json_path out_dir) json_report

let static_archive_path archive = Filename.remove_extension archive ^ ".a"

let describe_library ~mode ~session ~workspace_root ~verbose ~manifest_path
    ~backend_request ~backend ~compiler_version ~profile workspace library
    library_outputs =
  let target = Manifest.Library library in
  let out_dir = target_out_dir ~profile workspace_root target in
  let dependency_outputs =
    List.map
      (fun dependency ->
        match Hashtbl.find_opt library_outputs dependency with
        | Some output -> output
        | None ->
            failwith
              (Printf.sprintf "internal error: missing built dependency '%s'"
                 dependency))
      library.Manifest.deps
  in
  let effective_packages =
    String_util.dedup_preserve
      (library.packages
      @ List.concat_map
          (fun (output : built_library_output) -> output.packages)
          dependency_outputs)
  in
  let* package_resolution =
    Toolchain.resolve_packages ~session effective_packages
  in
  let* pipeline = resolve_pipeline ~workspace_root workspace ~profile target in
  let* () =
    validate_wrapped_library_source_conflicts ~workspace_root library
      pipeline.actions
  in
  let* action_results =
    run_actions ~mode ~workspace_root ~out_dir ~target ~pipeline
  in
  let* () = materialize_wrapped_library_source ~mode ~out_dir library in
  let wrapper_generated_outputs = wrapped_library_generated_outputs library in
  let planned_generated_outputs =
    wrapper_generated_outputs
    @
    match mode with
    | Materialize -> []
    | Plan_only -> planned_generated_output_names pipeline.actions
  in
  let* sources =
    library_source_descriptors ~workspace_root ~out_dir ~planned_generated_outputs
      library
  in
  let* prepared_sources =
    let target_env = pipeline.options.env in
    prepare_sources ~mode ~workspace_root ~out_dir ~target_env
      pipeline.preprocessors sources
  in
  let* ordered_modules =
    match mode with
    | Materialize ->
        infer_module_order ~session ~verbose ~env:(pipeline.options.env)
          ~target_kind:"library" ~target_name:library.name package_resolution
          prepared_sources
    | Plan_only ->
        dry_run_module_order ~session ~verbose ~env:(pipeline.options.env)
          ~target_kind:"library" ~target_name:library.name
          ~preprocessors:pipeline.preprocessors package_resolution
          prepared_sources
  in
  let* extra_lines =
    target_extra_lines ~workspace_root ~profile pipeline action_results
  in
  let generated_source_reasons =
    generated_source_reason_overrides ~target_dir:library.dir pipeline.actions
  in
  let fingerprint =
    target_fingerprint ~session ~manifest_path ~compiler_version
      ~profile_name:profile
      ~kind_name:"library" ~target_name:library.name ~backend ~dir:library.dir
      ~main:None ~ordered_modules ~sources ~package_resolution
      ~dependency_fingerprints:
        (List.map
           (fun dependency ->
             let output =
               match Hashtbl.find_opt library_outputs dependency with
               | Some output -> output
               | None ->
                   failwith
                     (Printf.sprintf
                        "internal error: missing built dependency '%s'" dependency)
             in
             (dependency, output.fingerprint))
           library.deps)
      ~extra_lines
  in
  let archive =
    Layout.library_archive_for_backend ~profile workspace_root backend
      library.name
  in
  let dependency_include_dirs =
    List.map
      (fun (output : built_library_output) -> output.out_dir)
      dependency_outputs
  in
  let include_dirs = out_dir :: dependency_include_dirs in
  let module_order_sources = List.concat_map prepared_source_files prepared_sources in
  let* module_order_command =
    match mode with
    | Materialize ->
        render_module_order_command ~session ~env:(pipeline.options.env)
          ~package_resolution module_order_sources
    | Plan_only ->
        dry_run_module_order_command ~session ~env:(pipeline.options.env)
          ~package_resolution ~preprocessors:pipeline.preprocessors
          module_order_sources
  in
  let source_table = ordered_source_table prepared_sources in
  let* compile_commands =
    render_compile_commands ~session ~workspace_root ~backend ~out_dir
      ~include_dirs ~package_resolution
      ~compile_flags:(pipeline.options.compile_flags)
      ~ppx_tools:pipeline.ppx_tools ~env:(pipeline.options.env) source_table
      ordered_modules
  in
  let expected_outputs =
    List.concat_map (expected_module_outputs backend out_dir) ordered_modules
    @ [ archive ]
    @
    (match backend with
    | Toolchain.Native -> [ static_archive_path archive ]
    | Toolchain.Bytecode -> [])
  in
  let* link_command =
    render_link_command ~session ~env:(pipeline.options.env) ~backend
      ~package_resolution
      (pipeline.options.link_flags @ [ "-a"; "-o"; archive ]
      @ List.map
          (fun stem -> Filename.concat out_dir (stem ^ Toolchain.object_extension backend))
          ordered_modules)
  in
  let status =
    Explain.evaluate_target ~stamp_path:(Layout.stamp_path out_dir)
      ~expected_outputs ~fingerprint
  in
  let status =
    include_action_execution_reasons ~generated_source_reasons status
      action_results
  in
  let resolution_lines =
    target_resolution_lines ~session ~backend_request ~backend
      ~compiler_version ~package_resolution pipeline
  in
  let command_lines =
    target_command_lines ~workspace_root pipeline action_results
      ~module_order_command ~compile_commands ~link_command
  in
  let report =
    Explain.render_report ~kind_name:"library" ~target_name:library.name
      ~package_path:library.package_path
      ~profile ~status ~out_dir ~artifact:archive
      ~resolution_lines ~include_dirs ~module_order:ordered_modules
      ~command_lines
  in
  let json_report =
    Explain.render_json_report ~kind_name:"library" ~target_name:library.name
      ~package_path:library.package_path
      ~profile ~status ~out_dir ~artifact:archive
      ~resolution_lines ~include_dirs ~module_order:ordered_modules
      ~command_lines
  in
  Ok
    {
      out_dir;
      archive;
      fingerprint;
      effective_packages;
      status;
      report;
      json_report;
      prepared_sources;
      ordered_modules;
      package_resolution;
      include_dirs;
      pipeline;
    }

let build_library ~session ~workspace_root ~verbose ~manifest_path
    ~backend_request ~backend ~compiler_version ~profile workspace library
    library_outputs =
  let* description =
    describe_library ~mode:Materialize ~session ~workspace_root ~verbose
      ~manifest_path ~backend_request ~backend ~compiler_version ~profile
      workspace library library_outputs
  in
  let source_table = ordered_source_table description.prepared_sources in
  let display_name = library.name ^ Manifest.package_suffix library.package_path in
  if not (Explain.needs_rebuild description.status.Explain.build_status) then (
    write_target_report description.out_dir description.report
      description.json_report;
    Hashtbl.replace library_outputs library.name
      {
        archive = description.archive;
        out_dir = description.out_dir;
        fingerprint = description.fingerprint;
        packages = description.effective_packages;
      };
    print_endline
      (Printf.sprintf
         (match description.status.Explain.build_status with
         | Explain.Reused -> "Up to date library %s -> %s"
         | Explain.Regenerated -> "Regenerated action outputs for library %s -> %s"
         | Explain.Rebuilt -> "Built library %s -> %s")
         display_name description.archive);
    Ok
      (Built_library
         { name = library.name; out_dir = description.out_dir; archive = description.archive }))
  else (
    let () = Fs.ensure_dir description.out_dir in
    let* object_files =
      compile_ordered_sources ~session ~workspace_root ~verbose ~backend
        ~out_dir:description.out_dir ~include_dirs:description.include_dirs
        ~package_resolution:description.package_resolution
        ~compile_flags:(description.pipeline.options.compile_flags)
        ~ppx_tools:description.pipeline.ppx_tools
        ~env:(description.pipeline.options.env) source_table
        description.ordered_modules
    in
    let* _ =
      Toolchain.ensure_success_compiler ~session
        ~env:(description.pipeline.options.env)
        ~verbose backend description.package_resolution
        (description.pipeline.options.link_flags
        @ [ "-a"; "-o"; description.archive ]
        @ object_files)
    in
    Fs.write_file (Layout.stamp_path description.out_dir) description.fingerprint;
    write_target_report description.out_dir description.report
      description.json_report;
    Hashtbl.replace library_outputs library.name
      {
        archive = description.archive;
        out_dir = description.out_dir;
        fingerprint = description.fingerprint;
        packages = description.effective_packages;
      };
    print_endline
      (Printf.sprintf "Built library %s -> %s" display_name description.archive);
    Ok
      (Built_library
         { name = library.name; out_dir = description.out_dir; archive = description.archive }))

type runnable_kind =
  | Executable_kind
  | Test_kind

let runnable_kind_name = function
  | Executable_kind -> "executable"
  | Test_kind -> "test"

let describe_runnable ~mode ~session ~workspace_root ~verbose ~manifest_path
    ~backend_request ~backend ~compiler_version ~profile ~kind workspace
    runnable order index library_outputs =
  let target =
    match kind with
    | Executable_kind -> Manifest.Executable runnable
    | Test_kind -> Manifest.Test runnable
  in
  let out_dir = target_out_dir ~profile workspace_root target in
  let dependency_outputs =
    List.map
      (fun dependency ->
        match Hashtbl.find_opt library_outputs dependency with
        | Some output -> output
        | None ->
            failwith
              (Printf.sprintf "internal error: missing built dependency '%s'"
                 dependency))
      runnable.Manifest.deps
  in
  let effective_packages =
    String_util.dedup_preserve
      (runnable.packages
      @ List.concat_map
          (fun (output : built_library_output) -> output.packages)
          dependency_outputs)
  in
  let* package_resolution =
    Toolchain.resolve_packages ~session effective_packages
  in
  let* pipeline = resolve_pipeline ~workspace_root workspace ~profile target in
  let* action_results =
    run_actions ~mode ~workspace_root ~out_dir ~target ~pipeline
  in
  let planned_generated_outputs =
    match mode with
    | Materialize -> []
    | Plan_only -> planned_generated_output_names pipeline.actions
  in
  let* module_sources =
    source_descriptors ~workspace_root ~generated_root:(generated_root out_dir)
      ~planned_generated_outputs ~dir:runnable.dir runnable.modules
  in
  let* main_source =
    source_descriptor ~workspace_root ~generated_root:(generated_root out_dir)
      ~planned_generated_outputs ~dir:runnable.dir runnable.main
  in
  let* prepared_sources =
    let target_env = pipeline.options.env in
    prepare_sources ~mode ~workspace_root ~out_dir ~target_env
      pipeline.preprocessors (module_sources @ [ main_source ])
  in
  let module_prepared_sources =
    List.filter
      (fun prepared -> prepared.source.stem <> runnable.main)
      prepared_sources
  in
  let* ordered_modules =
    match mode with
    | Materialize ->
        infer_module_order ~session ~verbose ~env:(pipeline.options.env)
          ~target_kind:(runnable_kind_name kind) ~target_name:runnable.name
          package_resolution module_prepared_sources
    | Plan_only ->
        dry_run_module_order ~session ~verbose ~env:(pipeline.options.env)
          ~target_kind:(runnable_kind_name kind) ~target_name:runnable.name
          ~preprocessors:pipeline.preprocessors package_resolution
          module_prepared_sources
  in
  let sources = module_sources @ [ main_source ] in
  let source_order = ordered_modules @ [ runnable.main ] in
  let* extra_lines =
    target_extra_lines ~workspace_root ~profile pipeline action_results
  in
  let generated_source_reasons =
    generated_source_reason_overrides ~target_dir:runnable.dir pipeline.actions
  in
  let fingerprint =
    target_fingerprint ~session ~manifest_path ~compiler_version
      ~profile_name:profile ~kind_name:(runnable_kind_name kind)
      ~target_name:runnable.name ~backend ~dir:runnable.dir
      ~main:(Some runnable.main) ~ordered_modules ~sources ~package_resolution
      ~dependency_fingerprints:
        (List.map
           (fun dependency ->
             let output =
               match Hashtbl.find_opt library_outputs dependency with
               | Some output -> output
               | None ->
                   failwith
                     (Printf.sprintf
                        "internal error: missing built dependency '%s'" dependency)
             in
             (dependency, output.fingerprint))
           runnable.deps)
      ~extra_lines
  in
  let closure =
    collect_dependency_closure index (Hashtbl.create 8) runnable.deps
  in
  let archive_files =
    List.filter_map
      (function
        | Manifest.Library library when Hashtbl.mem closure library.name ->
            let output = Hashtbl.find library_outputs library.name in
            Some output.archive
        | _ -> None)
      order
  in
  let binary =
    match kind with
    | Executable_kind -> Layout.executable_binary ~profile workspace_root runnable.name
    | Test_kind -> Layout.test_binary ~profile workspace_root runnable.name
  in
  let dependency_include_dirs =
    List.map
      (fun (output : built_library_output) -> output.out_dir)
      dependency_outputs
  in
  let include_dirs = out_dir :: dependency_include_dirs in
  let module_order_sources =
    List.concat_map prepared_source_files module_prepared_sources
  in
  let* module_order_command =
    match mode with
    | Materialize ->
        render_module_order_command ~session ~env:(pipeline.options.env)
          ~package_resolution module_order_sources
    | Plan_only ->
        dry_run_module_order_command ~session ~env:(pipeline.options.env)
          ~package_resolution ~preprocessors:pipeline.preprocessors
          module_order_sources
  in
  let source_table = ordered_source_table prepared_sources in
  let* compile_commands =
    render_compile_commands ~session ~workspace_root ~backend ~out_dir
      ~include_dirs ~package_resolution
      ~compile_flags:(pipeline.options.compile_flags)
      ~ppx_tools:pipeline.ppx_tools ~env:(pipeline.options.env) source_table
      source_order
  in
  let expected_outputs =
    List.concat_map (expected_module_outputs backend out_dir) source_order
    @ [ binary ]
  in
  let* link_command =
    render_link_command ~session ~env:(pipeline.options.env) ~backend
      ~package_resolution
      (pipeline.options.link_flags
      @ Toolchain.link_args package_resolution
      @ [ "-o"; binary ]
      @ archive_files
      @ List.map
          (fun stem -> Filename.concat out_dir (stem ^ Toolchain.object_extension backend))
          source_order)
  in
  let status =
    Explain.evaluate_target ~stamp_path:(Layout.stamp_path out_dir)
      ~expected_outputs ~fingerprint
  in
  let status =
    include_action_execution_reasons ~generated_source_reasons status
      action_results
  in
  let resolution_lines =
    target_resolution_lines ~session ~backend_request ~backend
      ~compiler_version ~package_resolution pipeline
  in
  let command_lines =
    target_command_lines ~workspace_root pipeline action_results
      ~module_order_command ~compile_commands ~link_command
  in
  let report =
    Explain.render_report ~kind_name:(runnable_kind_name kind)
      ~target_name:runnable.name ~package_path:runnable.package_path ~profile
      ~status ~out_dir ~artifact:binary ~resolution_lines ~include_dirs
      ~module_order:source_order
      ~command_lines
  in
  let json_report =
    Explain.render_json_report ~kind_name:(runnable_kind_name kind)
      ~target_name:runnable.name ~package_path:runnable.package_path ~profile
      ~status ~out_dir ~artifact:binary ~resolution_lines ~include_dirs
      ~module_order:source_order
      ~command_lines
  in
  Ok
    {
      out_dir;
      binary;
      fingerprint;
      status;
      report;
      json_report;
      prepared_sources;
      source_order;
      package_resolution;
      include_dirs;
      archive_files;
      pipeline;
    }

let build_runnable ~session ~workspace_root ~verbose ~manifest_path
    ~backend_request ~backend ~compiler_version ~profile ~kind workspace
    runnable order index library_outputs =
  let* description =
    describe_runnable ~mode:Materialize ~session ~workspace_root ~verbose
      ~manifest_path ~backend_request ~backend ~compiler_version ~profile
      ~kind workspace runnable order index library_outputs
  in
  let source_table = ordered_source_table description.prepared_sources in
  let display_name =
    runnable.name ^ Manifest.package_suffix runnable.package_path
  in
  if not (Explain.needs_rebuild description.status.Explain.build_status) then (
    write_target_report description.out_dir description.report
      description.json_report;
    print_endline
      (Printf.sprintf
         (match description.status.Explain.build_status with
         | Explain.Reused -> "Up to date %s %s -> %s"
         | Explain.Regenerated ->
             "Regenerated action outputs for %s %s -> %s"
         | Explain.Rebuilt -> "Built %s %s -> %s")
         (runnable_kind_name kind) display_name description.binary);
    Ok
      (match kind with
      | Executable_kind ->
          Built_executable
            {
              name = runnable.name;
              out_dir = description.out_dir;
              binary = description.binary;
            }
      | Test_kind ->
          Built_test
            {
              name = runnable.name;
              out_dir = description.out_dir;
              binary = description.binary;
            }))
  else (
    let () = Fs.ensure_dir description.out_dir in
    let* object_files =
      compile_ordered_sources ~session ~workspace_root ~verbose ~backend
        ~out_dir:description.out_dir ~include_dirs:description.include_dirs
        ~package_resolution:description.package_resolution
        ~compile_flags:(description.pipeline.options.compile_flags)
        ~ppx_tools:description.pipeline.ppx_tools
        ~env:(description.pipeline.options.env) source_table
        description.source_order
    in
    let* _ =
      Toolchain.ensure_success_compiler ~session
        ~env:(description.pipeline.options.env)
        ~verbose backend description.package_resolution
        (description.pipeline.options.link_flags
        @ Toolchain.link_args description.package_resolution
        @ [ "-o"; description.binary ]
        @ description.archive_files @ object_files)
    in
    Fs.write_file (Layout.stamp_path description.out_dir) description.fingerprint;
    write_target_report description.out_dir description.report
      description.json_report;
    print_endline
      (Printf.sprintf "Built %s %s -> %s" (runnable_kind_name kind)
         display_name description.binary);
    Ok
      (match kind with
      | Executable_kind ->
          Built_executable
            {
              name = runnable.name;
              out_dir = description.out_dir;
              binary = description.binary;
            }
      | Test_kind ->
          Built_test
            {
              name = runnable.name;
              out_dir = description.out_dir;
              binary = description.binary;
            }))

let build ~workspace_root ~verbose ?(requested_targets = [])
    ?(backend_request = Toolchain.Auto) ?profile workspace =
  let workspace_root = Fs.realpath workspace_root in
  let manifest_path = Filename.concat workspace_root Manifest.default_filename in
  let session = Toolchain.create_session () in
  let profile =
    match profile with
    | Some profile when String.trim profile <> "" -> profile
    | Some _ | None -> Manifest.default_profile workspace
  in
  let* backend = Toolchain.resolve_backend ~session backend_request in
  let* compiler_version = Toolchain.compiler_version ~session backend in
  let* order = resolve_build_order workspace requested_targets in
  let index = index_targets workspace in
  Fs.ensure_dir (build_root_for_profile workspace_root profile);
  let library_outputs = Hashtbl.create 8 in
  let rec loop artifacts = function
    | [] ->
        Ok
          {
            build_root = build_root_for_profile workspace_root profile;
            artifacts = List.rev artifacts;
          }
    | Manifest.Library library :: rest ->
        let* artifact =
          build_library ~session ~workspace_root ~verbose ~manifest_path
            ~backend_request ~backend ~compiler_version ~profile workspace
            library library_outputs
        in
        loop (artifact :: artifacts) rest
    | Manifest.Executable executable :: rest ->
        let* artifact =
          build_runnable ~session ~workspace_root ~verbose ~manifest_path
            ~backend_request ~backend ~compiler_version ~profile
            ~kind:Executable_kind workspace executable order index
            library_outputs
        in
        loop (artifact :: artifacts) rest
    | Manifest.Test test :: rest ->
        let* artifact =
          build_runnable ~session ~workspace_root ~verbose ~manifest_path
            ~backend_request ~backend ~compiler_version ~profile
            ~kind:Test_kind workspace test order index library_outputs
        in
        loop (artifact :: artifacts) rest
  in
  loop [] order

let explain_current ~workspace_root ?(requested_targets = [])
    ?(backend_request = Toolchain.Auto) ?profile workspace =
  let workspace_root = Fs.realpath workspace_root in
  let manifest_path = Filename.concat workspace_root Manifest.default_filename in
  let session = Toolchain.create_session () in
  let profile =
    match profile with
    | Some profile when String.trim profile <> "" -> profile
    | Some _ | None -> Manifest.default_profile workspace
  in
  let display_targets =
    if requested_targets = [] then workspace.Manifest.targets
    else
      let index = index_targets workspace in
      String_util.dedup_preserve requested_targets
      |> List.map (fun name ->
             match Hashtbl.find_opt index name with
             | Some target -> target
             | None ->
                 failwith
                   (Printf.sprintf
                      "internal error: explain target '%s' disappeared during \
                       resolution"
                      name))
  in
  let requested_names = List.map Manifest.target_name display_targets in
  let* backend = Toolchain.resolve_backend ~session backend_request in
  let* compiler_version = Toolchain.compiler_version ~session backend in
  let* order = resolve_build_order workspace requested_names in
  let index = index_targets workspace in
  let library_outputs = Hashtbl.create 8 in
  let reports : (string, explain_report) Hashtbl.t = Hashtbl.create 16 in
  let rec loop = function
    | [] -> Ok ()
    | Manifest.Library library :: rest ->
        let* description =
          describe_library ~mode:Plan_only ~session ~workspace_root
            ~verbose:false ~manifest_path ~backend_request ~backend
            ~compiler_version ~profile workspace library library_outputs
        in
        Hashtbl.replace library_outputs library.name
          {
            archive = description.archive;
            out_dir = description.out_dir;
            fingerprint = description.fingerprint;
            packages = description.effective_packages;
          };
        Hashtbl.replace reports library.name
          {
            target_name = library.name;
            report = description.report;
            json_report = description.json_report;
          };
        loop rest
    | Manifest.Executable executable :: rest ->
        let* description =
          describe_runnable ~mode:Plan_only ~session ~workspace_root
            ~verbose:false ~manifest_path ~backend_request ~backend
            ~compiler_version ~profile ~kind:Executable_kind workspace
            executable order index library_outputs
        in
        Hashtbl.replace reports executable.name
          {
            target_name = executable.name;
            report = description.report;
            json_report = description.json_report;
          };
        loop rest
    | Manifest.Test test :: rest ->
        let* description =
          describe_runnable ~mode:Plan_only ~session ~workspace_root
            ~verbose:false ~manifest_path ~backend_request ~backend
            ~compiler_version ~profile ~kind:Test_kind workspace test order
            index library_outputs
        in
        Hashtbl.replace reports test.name
          {
            target_name = test.name;
            report = description.report;
            json_report = description.json_report;
          };
        loop rest
  in
  let* () = loop order in
  let rec collect acc = function
    | [] -> Ok (List.rev acc)
    | target :: rest -> (
        match Hashtbl.find_opt reports (Manifest.target_name target) with
        | Some report -> collect (report :: acc) rest
        | None ->
            Error
              (Printf.sprintf
                 "internal error: missing current explain report for %s '%s'"
                 (Manifest.target_kind_name target)
                 (Manifest.target_name target)))
  in
  collect [] display_targets
