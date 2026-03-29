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

let ( let* ) = Result.bind

let target_name = Manifest.target_name

let dependency_names = Manifest.target_deps

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

let build_root = Layout.build_root

let target_out_dir = Layout.target_out_dir

let source_file workspace_root dir stem extension =
  Filename.concat workspace_root (Filename.concat dir (stem ^ extension))

let include_args dirs =
  List.concat_map (fun dir -> [ "-I"; dir ]) dirs

let stamp_path = Layout.stamp_path

let static_archive_path archive = Filename.remove_extension archive ^ ".a"

let append_line buffer line =
  Buffer.add_string buffer line;
  Buffer.add_char buffer '\n'

let source_descriptor ~workspace_root ~dir stem =
  let ml_relative = Filename.concat dir (stem ^ ".ml") in
  let ml_path = Filename.concat workspace_root ml_relative in
  let mli_relative = Filename.concat dir (stem ^ ".mli") in
  let mli_path = Filename.concat workspace_root mli_relative in
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

let source_descriptors ~workspace_root ~dir stems =
  let rec loop acc = function
    | [] -> Ok (List.rev acc)
    | stem :: rest ->
        let* source = source_descriptor ~workspace_root ~dir stem in
        loop (source :: acc) rest
  in
  loop [] stems

let source_files source =
  if source.has_mli then [ source.mli_path; source.ml_path ] else [ source.ml_path ]

let ordered_source_table sources =
  let table = Hashtbl.create (List.length sources) in
  List.iter (fun source -> Hashtbl.replace table source.stem source) sources;
  table

let infer_module_order ~verbose ~target_kind ~target_name package_resolution
    sources =
  if sources = [] then Ok []
  else
    let requested = List.map (fun source -> source.stem) sources in
    let source_files = List.concat_map source_files sources in
    let* sorted_paths =
      match Toolchain.sort_sources ~verbose package_resolution source_files with
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
  List.for_all Fs.exists expected_outputs && Fs.read_file stamp_path = fingerprint

let target_fingerprint ~manifest_path ~compiler_version ~kind_name ~target_name
    ~backend ~dir ~main ~ordered_modules ~sources ~package_resolution
    ~dependency_fingerprints =
  let buffer = Buffer.create 512 in
  append_line buffer ("compiler " ^ compiler_version);
  append_line buffer ("backend " ^ Toolchain.backend_name backend);
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
    (Toolchain.fingerprint_lines package_resolution);
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
        (Printf.sprintf "dep %s %s" dependency_name dependency_fingerprint))
    dependency_fingerprints;
  Buffer.contents buffer

let compile_module ~verbose ~backend ~out_dir ~include_dirs ~package_resolution
    source =
  let* () =
    if source.has_mli then
      let* _ =
        Toolchain.ensure_success_compiler ~verbose backend package_resolution
          ([ "-c" ] @ include_args include_dirs
         @ [ "-o"; Filename.concat out_dir (source.stem ^ ".cmi"); source.mli_path ])
      in
      Ok ()
    else Ok ()
  in
  let* _ =
    Toolchain.ensure_success_compiler ~verbose backend package_resolution
      ([ "-c" ] @ include_args include_dirs
     @
     [
       "-o";
       Filename.concat out_dir (source.stem ^ Toolchain.object_extension backend);
       source.ml_path;
     ])
  in
  Ok
    (Filename.concat out_dir
       (source.stem ^ Toolchain.object_extension backend))

let compile_ordered_sources ~verbose ~backend ~out_dir ~include_dirs
    ~package_resolution source_table ordered_stems =
  let rec loop acc = function
    | [] -> Ok (List.rev acc)
    | stem :: rest ->
        let source =
          match Hashtbl.find_opt source_table stem with
          | Some source -> source
          | None ->
              failwith
                (Printf.sprintf
                   "internal error: missing source descriptor for '%s'" stem)
        in
        let* object_file =
          compile_module ~verbose ~backend ~out_dir ~include_dirs
            ~package_resolution source
        in
        loop (object_file :: acc) rest
  in
  loop [] ordered_stems

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

let build_library ~workspace_root ~verbose ~manifest_path ~backend
    ~compiler_version library library_outputs =
  let out_dir = target_out_dir workspace_root (Manifest.Library library) in
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
  let* package_resolution = Toolchain.resolve_packages effective_packages in
  let* sources =
    source_descriptors ~workspace_root ~dir:library.dir library.modules
  in
  let* ordered_modules =
    infer_module_order ~verbose ~target_kind:"library"
      ~target_name:library.name package_resolution sources
  in
  let fingerprint =
    target_fingerprint ~manifest_path ~compiler_version ~kind_name:"library"
      ~target_name:library.name ~backend ~dir:library.dir ~main:None
      ~ordered_modules ~sources ~package_resolution
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
  in
  let archive =
    Layout.library_archive_for_backend workspace_root backend library.name
  in
  let expected_outputs =
    List.concat_map (expected_module_outputs backend out_dir) ordered_modules
    @ [ archive; stamp_path out_dir ]
    @
    (match backend with
      | Toolchain.Native -> [ static_archive_path archive ]
      | Toolchain.Bytecode -> [])
  in
  if target_is_up_to_date ~stamp_path:(stamp_path out_dir) expected_outputs
       fingerprint
  then (
    Hashtbl.replace library_outputs library.name
      { archive; out_dir; fingerprint; packages = effective_packages };
    print_endline (Printf.sprintf "Up to date library %s -> %s" library.name archive);
    Ok (Built_library { name = library.name; out_dir; archive }))
  else
    let source_table = ordered_source_table sources in
    let dependency_include_dirs =
      List.map (fun output -> output.out_dir) dependency_outputs
    in
    let include_dirs = out_dir :: dependency_include_dirs in
    Fs.remove_tree out_dir;
    Fs.ensure_dir out_dir;
    let* object_files =
      compile_ordered_sources ~verbose ~backend ~out_dir ~include_dirs
        ~package_resolution source_table ordered_modules
    in
    let* _ =
      Toolchain.ensure_success_compiler ~verbose backend package_resolution
        ([ "-a"; "-o"; archive ] @ object_files)
    in
    Fs.write_file (stamp_path out_dir) fingerprint;
    Hashtbl.replace library_outputs library.name
      { archive; out_dir; fingerprint; packages = effective_packages };
    print_endline (Printf.sprintf "Built library %s -> %s" library.name archive);
    Ok (Built_library { name = library.name; out_dir; archive })

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

type runnable_kind =
  | Executable_kind
  | Test_kind

let runnable_kind_name = function
  | Executable_kind -> "executable"
  | Test_kind -> "test"

let build_runnable ~workspace_root ~verbose ~manifest_path ~backend
    ~compiler_version ~kind runnable order index library_outputs =
  let target =
    match kind with
    | Executable_kind -> Manifest.Executable runnable
    | Test_kind -> Manifest.Test runnable
  in
  let out_dir = target_out_dir workspace_root target in
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
  let* package_resolution = Toolchain.resolve_packages effective_packages in
  let* module_sources =
    source_descriptors ~workspace_root ~dir:runnable.dir runnable.modules
  in
  let* ordered_modules =
    infer_module_order ~verbose
      ~target_kind:(runnable_kind_name kind) ~target_name:runnable.name
      package_resolution module_sources
  in
  let* main_source =
    source_descriptor ~workspace_root ~dir:runnable.dir runnable.main
  in
  let sources = module_sources @ [ main_source ] in
  let source_order = ordered_modules @ [ runnable.main ] in
  let fingerprint =
    target_fingerprint ~manifest_path ~compiler_version
      ~kind_name:(runnable_kind_name kind) ~target_name:runnable.name ~backend
      ~dir:runnable.dir ~main:(Some runnable.main) ~ordered_modules ~sources
      ~package_resolution
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
    | Executable_kind -> Layout.executable_binary workspace_root runnable.name
    | Test_kind -> Layout.test_binary workspace_root runnable.name
  in
  let expected_outputs =
    List.concat_map (expected_module_outputs backend out_dir) source_order
    @ [ binary; stamp_path out_dir ]
  in
  if target_is_up_to_date ~stamp_path:(stamp_path out_dir) expected_outputs
       fingerprint
  then (
    print_endline
      (Printf.sprintf "Up to date %s %s -> %s" (runnable_kind_name kind)
         runnable.name binary);
    Ok
      (match kind with
      | Executable_kind ->
          Built_executable { name = runnable.name; out_dir; binary }
      | Test_kind -> Built_test { name = runnable.name; out_dir; binary }))
  else
    let source_table = ordered_source_table sources in
    let dependency_include_dirs =
      List.map (fun output -> output.out_dir) dependency_outputs
    in
    let include_dirs = out_dir :: dependency_include_dirs in
    Fs.remove_tree out_dir;
    Fs.ensure_dir out_dir;
    let* object_files =
      compile_ordered_sources ~verbose ~backend ~out_dir ~include_dirs
        ~package_resolution source_table source_order
    in
    let* _ =
      Toolchain.ensure_success_compiler ~verbose backend package_resolution
        (Toolchain.link_args package_resolution
        @ [ "-o"; binary ]
        @ archive_files @ object_files)
    in
    Fs.write_file (stamp_path out_dir) fingerprint;
    print_endline
      (Printf.sprintf "Built %s %s -> %s" (runnable_kind_name kind)
         runnable.name binary);
    Ok
      (match kind with
      | Executable_kind ->
          Built_executable { name = runnable.name; out_dir; binary }
      | Test_kind -> Built_test { name = runnable.name; out_dir; binary })

let build ~workspace_root ~verbose ?(requested_targets = [])
    ?(backend_request = Toolchain.Auto) workspace =
  let workspace_root = Fs.realpath workspace_root in
  let manifest_path = Filename.concat workspace_root Manifest.default_filename in
  let* backend = Toolchain.resolve_backend backend_request in
  let* compiler_version = Toolchain.compiler_version backend in
  let* order = resolve_build_order workspace requested_targets in
  let index = index_targets workspace in
  Fs.ensure_dir (build_root workspace_root);
  let library_outputs = Hashtbl.create 8 in
  let rec loop artifacts = function
    | [] ->
        Ok
          {
            build_root = build_root workspace_root;
            artifacts = List.rev artifacts;
          }
    | Manifest.Library library :: rest ->
      let* artifact =
          build_library ~workspace_root ~verbose ~manifest_path ~backend
            ~compiler_version library library_outputs
        in
        loop (artifact :: artifacts) rest
    | Manifest.Executable executable :: rest ->
        let* artifact =
          build_runnable ~workspace_root ~verbose ~manifest_path ~backend
            ~compiler_version ~kind:Executable_kind executable order index
            library_outputs
        in
        loop (artifact :: artifacts) rest
    | Manifest.Test test :: rest ->
        let* artifact =
          build_runnable ~workspace_root ~verbose ~manifest_path ~backend
            ~compiler_version ~kind:Test_kind test order index library_outputs
        in
        loop (artifact :: artifacts) rest
  in
  loop [] order
