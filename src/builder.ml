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
  mli_path : string;
  mli_relative : string;
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

type action_result = {
  name : string;
  fingerprint : string;
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

let source_descriptor ~workspace_root ~generated_root ~dir stem =
  let ml_relative = Filename.concat dir (stem ^ ".ml") in
  let workspace_ml_path = Filename.concat workspace_root ml_relative in
  let generated_ml_path = Filename.concat generated_root (stem ^ ".ml") in
  let ml_path =
    if Fs.exists generated_ml_path then generated_ml_path else workspace_ml_path
  in
  let mli_relative = Filename.concat dir (stem ^ ".mli") in
  let workspace_mli_path = Filename.concat workspace_root mli_relative in
  let generated_mli_path = Filename.concat generated_root (stem ^ ".mli") in
  let mli_path =
    if Fs.exists generated_mli_path then generated_mli_path else workspace_mli_path
  in
  if not (Fs.exists ml_path) then
    Error
      (Printf.sprintf "missing source file for module '%s': %s" stem ml_path)
  else
    Ok
      {
        stem;
        ml_path;
        ml_relative;
        mli_path;
        mli_relative;
        has_mli = Fs.exists mli_path;
      }

let source_descriptors ~workspace_root ~generated_root ~dir stems =
  collect_results stems (source_descriptor ~workspace_root ~generated_root ~dir)

let prepared_source_files prepared_source =
  match prepared_source.mli_compile_path with
  | Some mli_path -> [ mli_path; prepared_source.ml_compile_path ]
  | None -> [ prepared_source.ml_compile_path ]

let ordered_source_table sources =
  let table = Hashtbl.create (List.length sources) in
  List.iter (fun source -> Hashtbl.replace table source.source.stem source) sources;
  table

let infer_module_order ~session ~verbose ~env ~target_kind ~target_name
    package_resolution sources =
  if sources = [] then Ok []
  else
    let requested = List.map (fun source -> source.source.stem) sources in
    let source_files = List.concat_map prepared_source_files sources in
    let* sorted_paths =
      match
        Toolchain.sort_sources ~session ~env ~verbose package_resolution
          source_files
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
           (Digest.to_hex (Digest.file source.ml_path)));
      append_line buffer
        (Printf.sprintf "mli %s %s" source.mli_relative
           (if source.has_mli then Digest.to_hex (Digest.file source.mli_path)
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
      Fs.copy_tree ~src:workspace_root ~dst:sandbox_root;
      let artifact_root = Filename.concat sandbox_root "_oasis" in
      if Fs.exists artifact_root then Fs.remove_tree artifact_root;
      Ok ()
  | Manifest.Target ->
      let sandbox_target_dir = Filename.concat sandbox_root target_dir in
      let workspace_target_dir = Filename.concat workspace_root target_dir in
      let* () =
        if Fs.exists workspace_target_dir then
          if Sys.is_directory workspace_target_dir then (
            Fs.copy_tree ~src:workspace_target_dir ~dst:sandbox_target_dir;
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
          copy_relative_path ~workspace_root ~sandbox_root ~label relative_path)
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
  let* () =
    List.fold_left
      (fun result dep ->
        let* () = result in
        let dep_path = Filename.concat workspace_root dep in
        if not (Fs.exists dep_path) then
          Error (Printf.sprintf "action dependency does not exist: %s" dep)
        else if Sys.is_directory dep_path then (
          append_line buffer ("dep-dir " ^ dep);
          Ok ())
        else (
          append_line buffer
            ("dep " ^ dep ^ " " ^ Digest.to_hex (Digest.file dep_path));
          Ok ()))
      (Ok ()) action.deps
  in
  Ok (Buffer.contents buffer)

let run_action ~workspace_root ~out_dir ~target_dir ~target_env options
    (action : Manifest.action) =
  let* fingerprint =
    action_fingerprint ~workspace_root ~target_env ~target_dir options action
  in
  let generated_root = generated_root out_dir in
  let output_paths =
    List.map (fun output -> Filename.concat generated_root output) action.outputs
  in
  let stamp_path = action_stamp_path out_dir action.name in
  Fs.ensure_dir (Filename.dirname stamp_path);
  if target_is_up_to_date ~stamp_path output_paths fingerprint then
    Ok { name = action.name; fingerprint }
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
        Fs.ensure_dir generated_root;
        let sandbox_target_dir = Filename.concat sandbox_root target_dir in
        let* () =
          List.fold_left
            (fun result output ->
              let* () = result in
              let src = Filename.concat sandbox_target_dir output in
              let dst = Filename.concat generated_root output in
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
        Ok { name = action.name; fingerprint })

let resolve_pipeline workspace ~profile target =
  let* options = Manifest.resolve_target_options workspace profile target in
  let* actions =
    collect_results options.actions (fun name ->
        match Manifest.find_action workspace name with
        | Some action -> Ok action
        | None ->
            Error
              (Printf.sprintf "target '%s' references unknown action '%s'"
                 (Manifest.target_name target) name))
  in
  let* preprocessors =
    collect_results options.preprocess (fun name ->
        match Manifest.find_preprocessor workspace name with
        | Some tool -> Ok tool
        | None ->
            Error
              (Printf.sprintf "target '%s' references unknown preprocessor '%s'"
                 (Manifest.target_name target) name))
  in
  let* ppx_tools =
    collect_results options.ppx (fun name ->
        match Manifest.find_ppx_tool workspace name with
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
  Ok { options; actions; preprocessors; ppx_tools }

let run_actions ~workspace_root ~out_dir ~target ~pipeline =
  Fs.ensure_dir out_dir;
  let target_env = pipeline.options.env in
  let options = pipeline.options in
  collect_results pipeline.actions (fun action ->
      run_action ~workspace_root ~out_dir ~target_dir:(Manifest.target_dir target)
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

let preprocess_source_path ~workspace_root ~out_dir ~target_env
    (preprocessors : Manifest.command_tool list) logical_path source_path =
  if preprocessors = [] then Ok source_path
  else
    let* output =
      List.fold_left
        (fun result tool ->
          let* input = result in
          run_preprocessor ~workspace_root ~target_env tool input)
        (Ok (Fs.read_file source_path)) preprocessors
    in
    let path = Filename.concat (preprocessed_root out_dir) logical_path in
    Fs.write_file path output;
    Ok path

let prepare_source ~workspace_root ~out_dir ~target_env
    (preprocessors : Manifest.command_tool list) source =
  let logical_ml_path = Filename.basename source.ml_relative in
  let* ml_compile_path =
    preprocess_source_path ~workspace_root ~out_dir ~target_env preprocessors
      logical_ml_path source.ml_path
  in
  let* mli_compile_path =
    match source.has_mli with
    | false -> Ok None
    | true ->
        let logical_mli_path = Filename.basename source.mli_relative in
        let* path =
          preprocess_source_path ~workspace_root ~out_dir ~target_env preprocessors
            logical_mli_path source.mli_path
        in
        Ok (Some path)
  in
  Ok { source; ml_compile_path; mli_compile_path }

let prepare_sources ~workspace_root ~out_dir ~target_env
    (preprocessors : Manifest.command_tool list) sources =
  collect_results sources
    (prepare_source ~workspace_root ~out_dir ~target_env preprocessors)

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
  let preprocessor_lines =
    List.concat_map
      (fun (tool : Manifest.command_tool) ->
        ("preprocess " ^ tool.name)
        :: (match tool.cwd with
           | Some cwd -> [ "preprocess-cwd " ^ cwd ]
           | None -> [])
        @ List.map
            (fun (name, value) ->
              "preprocess-env " ^ tool.name ^ " " ^ name ^ "=" ^ value)
            tool.env
        @ command_fingerprint_lines ~workspace_root tool.argv)
      pipeline.preprocessors
  in
  let ppx_lines =
    List.concat_map
      (fun (tool : Manifest.ppx_tool) ->
        ("ppx " ^ tool.name)
        :: command_fingerprint_lines ~workspace_root tool.argv)
      pipeline.ppx_tools
  in
  let action_lines =
    List.map
      (fun action_result ->
        "action " ^ action_result.name ^ " "
        ^ Digest.to_hex (Digest.string action_result.fingerprint))
      action_results
  in
  option_lines @ preprocessor_lines @ ppx_lines @ action_lines

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
           (fun (action : Manifest.action) -> action.name)
           pipeline.actions);
    "preprocessors: "
    ^ joined_names
        (List.map
           (fun (tool : Manifest.command_tool) -> tool.name)
           pipeline.preprocessors);
    "ppx: "
    ^ joined_names
        (List.map
           (fun (tool : Manifest.ppx_tool) -> tool.name)
           pipeline.ppx_tools);
  ]
  @
  if package_resolution.Toolchain.packages = [] then []
  else
    [
      Toolchain.render_command_report "ocamlfind"
        (Toolchain.resolved_ocamlfind_report ~session ());
    ]
    @ package_lines

let render_link_command ~session ~env ~backend ~package_resolution args =
  let* invocation =
    Toolchain.compiler_invocation ~session backend package_resolution args
  in
  Ok (Toolchain.render_invocation ~env invocation)

let write_target_report out_dir report =
  Fs.write_file (Layout.explain_path out_dir) report

let static_archive_path archive = Filename.remove_extension archive ^ ".a"

let build_library ~session ~workspace_root ~verbose ~manifest_path
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
      @ List.concat_map (fun output -> output.packages) dependency_outputs)
  in
  let* package_resolution =
    Toolchain.resolve_packages ~session effective_packages
  in
  let* pipeline = resolve_pipeline workspace ~profile target in
  let* action_results = run_actions ~workspace_root ~out_dir ~target ~pipeline in
  let* sources =
    source_descriptors ~workspace_root ~generated_root:(generated_root out_dir)
      ~dir:library.dir library.modules
  in
  let* prepared_sources =
    let target_env = pipeline.options.env in
    prepare_sources ~workspace_root ~out_dir ~target_env pipeline.preprocessors
      sources
  in
  let* ordered_modules =
    infer_module_order ~session ~verbose ~env:(pipeline.options.env)
      ~target_kind:"library" ~target_name:library.name package_resolution
      prepared_sources
  in
  let extra_lines =
    target_extra_lines ~workspace_root ~profile pipeline action_results
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
  let source_table = ordered_source_table prepared_sources in
  let dependency_include_dirs =
    List.map (fun output -> output.out_dir) dependency_outputs
  in
  let include_dirs = out_dir :: dependency_include_dirs in
  let module_order_sources = List.concat_map prepared_source_files prepared_sources in
  let* module_order_command =
    render_module_order_command ~session ~env:(pipeline.options.env)
      ~package_resolution module_order_sources
  in
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
  let report =
    Explain.render_report ~kind_name:"library" ~target_name:library.name
      ~profile ~status ~out_dir ~artifact:archive
      ~resolution_lines:
        (target_resolution_lines ~session ~backend_request ~backend
           ~compiler_version ~package_resolution pipeline)
      ~include_dirs ~module_order:ordered_modules
      ~command_lines:
        (List.map
           (fun (action_result : action_result) ->
             "action " ^ action_result.name ^ ": cached")
           action_results
        @ List.map
            (fun (tool : Manifest.command_tool) ->
              "preprocess " ^ tool.name ^ ": "
              ^ render_preprocessor_command ~workspace_root
                  ~target_env:(pipeline.options.env) tool)
            pipeline.preprocessors
        @ ("module-order: " ^ module_order_command)
          :: compile_commands
        @ [ "link: " ^ link_command ])
  in
  if status.Explain.build_status = Explain.Reused then (
    write_target_report out_dir report;
    Hashtbl.replace library_outputs library.name
      { archive; out_dir; fingerprint; packages = effective_packages };
    print_endline (Printf.sprintf "Up to date library %s -> %s" library.name archive);
    Ok (Built_library { name = library.name; out_dir; archive }))
  else (
    let () = Fs.ensure_dir out_dir in
    let* object_files =
      compile_ordered_sources ~session ~workspace_root ~verbose ~backend
        ~out_dir ~include_dirs ~package_resolution
        ~compile_flags:(pipeline.options.compile_flags)
        ~ppx_tools:pipeline.ppx_tools ~env:(pipeline.options.env) source_table
        ordered_modules
    in
    let* _ =
      Toolchain.ensure_success_compiler ~session ~env:(pipeline.options.env)
        ~verbose backend package_resolution
        (pipeline.options.link_flags @ [ "-a"; "-o"; archive ] @ object_files)
    in
    Fs.write_file (Layout.stamp_path out_dir) fingerprint;
    write_target_report out_dir report;
    Hashtbl.replace library_outputs library.name
      { archive; out_dir; fingerprint; packages = effective_packages };
    print_endline (Printf.sprintf "Built library %s -> %s" library.name archive);
    Ok (Built_library { name = library.name; out_dir; archive }))

type runnable_kind =
  | Executable_kind
  | Test_kind

let runnable_kind_name = function
  | Executable_kind -> "executable"
  | Test_kind -> "test"

let build_runnable ~session ~workspace_root ~verbose ~manifest_path
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
      @ List.concat_map (fun output -> output.packages) dependency_outputs)
  in
  let* package_resolution =
    Toolchain.resolve_packages ~session effective_packages
  in
  let* pipeline = resolve_pipeline workspace ~profile target in
  let* action_results = run_actions ~workspace_root ~out_dir ~target ~pipeline in
  let* module_sources =
    source_descriptors ~workspace_root ~generated_root:(generated_root out_dir)
      ~dir:runnable.dir runnable.modules
  in
  let* main_source =
    source_descriptor ~workspace_root ~generated_root:(generated_root out_dir)
      ~dir:runnable.dir runnable.main
  in
  let* prepared_sources =
    let target_env = pipeline.options.env in
    prepare_sources ~workspace_root ~out_dir ~target_env pipeline.preprocessors
      (module_sources @ [ main_source ])
  in
  let module_prepared_sources =
    List.filter
      (fun prepared -> prepared.source.stem <> runnable.main)
      prepared_sources
  in
  let* ordered_modules =
    infer_module_order ~session ~verbose ~env:(pipeline.options.env)
      ~target_kind:(runnable_kind_name kind) ~target_name:runnable.name
      package_resolution module_prepared_sources
  in
  let sources = module_sources @ [ main_source ] in
  let source_order = ordered_modules @ [ runnable.main ] in
  let extra_lines =
    target_extra_lines ~workspace_root ~profile pipeline action_results
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
  let source_table = ordered_source_table prepared_sources in
  let dependency_include_dirs =
    List.map (fun output -> output.out_dir) dependency_outputs
  in
  let include_dirs = out_dir :: dependency_include_dirs in
  let module_order_sources =
    List.concat_map prepared_source_files module_prepared_sources
  in
  let* module_order_command =
    render_module_order_command ~session ~env:(pipeline.options.env)
      ~package_resolution module_order_sources
  in
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
  let report =
    Explain.render_report ~kind_name:(runnable_kind_name kind)
      ~target_name:runnable.name ~profile ~status ~out_dir ~artifact:binary
      ~resolution_lines:
        (target_resolution_lines ~session ~backend_request ~backend
           ~compiler_version ~package_resolution pipeline)
      ~include_dirs ~module_order:source_order
      ~command_lines:
        (List.map
           (fun (action_result : action_result) ->
             "action " ^ action_result.name ^ ": cached")
           action_results
        @ List.map
            (fun (tool : Manifest.command_tool) ->
              "preprocess " ^ tool.name ^ ": "
              ^ render_preprocessor_command ~workspace_root
                  ~target_env:(pipeline.options.env) tool)
            pipeline.preprocessors
        @ ("module-order: " ^ module_order_command)
          :: compile_commands
        @ [ "link: " ^ link_command ])
  in
  if status.Explain.build_status = Explain.Reused then (
    write_target_report out_dir report;
    print_endline
      (Printf.sprintf "Up to date %s %s -> %s" (runnable_kind_name kind)
         runnable.name binary);
    Ok
      (match kind with
      | Executable_kind ->
          Built_executable { name = runnable.name; out_dir; binary }
      | Test_kind -> Built_test { name = runnable.name; out_dir; binary }))
  else (
    let () = Fs.ensure_dir out_dir in
    let* object_files =
      compile_ordered_sources ~session ~workspace_root ~verbose ~backend
        ~out_dir ~include_dirs ~package_resolution
        ~compile_flags:(pipeline.options.compile_flags)
        ~ppx_tools:pipeline.ppx_tools ~env:(pipeline.options.env) source_table
        source_order
    in
    let* _ =
      Toolchain.ensure_success_compiler ~session ~env:(pipeline.options.env)
        ~verbose backend package_resolution
        (pipeline.options.link_flags
        @ Toolchain.link_args package_resolution
        @ [ "-o"; binary ]
        @ archive_files @ object_files)
    in
    Fs.write_file (Layout.stamp_path out_dir) fingerprint;
    write_target_report out_dir report;
    print_endline
      (Printf.sprintf "Built %s %s -> %s" (runnable_kind_name kind)
         runnable.name binary);
    Ok
      (match kind with
      | Executable_kind ->
          Built_executable { name = runnable.name; out_dir; binary }
      | Test_kind -> Built_test { name = runnable.name; out_dir; binary }))

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
