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

type build_result = {
  build_root : string;
  artifacts : built_artifact list;
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
                | Some (Manifest.Executable _) ->
                    Error
                      (Printf.sprintf
                         "target '%s' depends on executable '%s'; only libraries \
                          may be dependencies"
                         name dependency)
                | Some _ -> visit (path @ [ name ]) dependency)
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

let build_root workspace_root =
  Filename.concat workspace_root "_oasis/build/default"

let target_out_dir workspace_root = function
  | Manifest.Library library ->
      Filename.concat (Filename.concat (build_root workspace_root) "lib")
        library.name
  | Manifest.Executable executable ->
      Filename.concat (Filename.concat (build_root workspace_root) "exe")
        executable.name

let source_file workspace_root dir stem extension =
  Filename.concat workspace_root (Filename.concat dir (stem ^ extension))

let include_args dirs =
  List.concat_map (fun dir -> [ "-I"; dir ]) dirs

let compile_module ~workspace_root ~verbose ~out_dir ~include_dirs ~dir stem =
  let ml_path = source_file workspace_root dir stem ".ml" in
  let mli_path = source_file workspace_root dir stem ".mli" in
  if not (Fs.exists ml_path) then
    Error
      (Printf.sprintf "missing source file for module '%s': %s" stem ml_path)
  else
    let* () =
      if Fs.exists mli_path then
        let* _ =
          Process.ensure_success ~verbose "ocamlopt"
            ([ "-c" ] @ include_args include_dirs @ [ "-o"; Filename.concat out_dir (stem ^ ".cmi"); mli_path ])
        in
        Ok ()
      else Ok ()
    in
    let* _ =
      Process.ensure_success ~verbose "ocamlopt"
        ([ "-c" ] @ include_args include_dirs @ [ "-o"; Filename.concat out_dir (stem ^ ".cmx"); ml_path ])
    in
    Ok (Filename.concat out_dir (stem ^ ".cmx"))

let build_library ~workspace_root ~verbose library library_outputs =
  let out_dir = target_out_dir workspace_root (Manifest.Library library) in
  Fs.remove_tree out_dir;
  Fs.ensure_dir out_dir;
  let dependency_include_dirs =
    List.map
      (fun dependency ->
        match Hashtbl.find_opt library_outputs dependency with
        | Some (_, out_dir) -> out_dir
        | None ->
            failwith
              (Printf.sprintf "internal error: missing built dependency '%s'"
                 dependency))
      library.Manifest.deps
  in
  let include_dirs = out_dir :: dependency_include_dirs in
  let rec compile acc = function
    | [] -> Ok (List.rev acc)
    | stem :: rest ->
        let* object_file =
          compile_module ~workspace_root ~verbose ~out_dir ~include_dirs
            ~dir:library.dir stem
        in
        compile (object_file :: acc) rest
  in
  let* object_files = compile [] library.modules in
  let archive = Filename.concat out_dir ("lib" ^ library.name ^ ".cmxa") in
  let* _ =
    Process.ensure_success ~verbose "ocamlopt"
      ([ "-a"; "-o"; archive ] @ object_files)
  in
  Hashtbl.replace library_outputs library.name (archive, out_dir);
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

let build_executable ~workspace_root ~verbose executable order index
    library_outputs =
  let out_dir = target_out_dir workspace_root (Manifest.Executable executable) in
  Fs.remove_tree out_dir;
  Fs.ensure_dir out_dir;
  let dependency_include_dirs =
    List.map
      (fun dependency ->
        match Hashtbl.find_opt library_outputs dependency with
        | Some (_, out_dir) -> out_dir
        | None ->
            failwith
              (Printf.sprintf "internal error: missing built dependency '%s'"
                 dependency))
      executable.Manifest.deps
  in
  let include_dirs = out_dir :: dependency_include_dirs in
  let source_modules = executable.modules @ [ executable.main ] in
  let rec compile acc = function
    | [] -> Ok (List.rev acc)
    | stem :: rest ->
        let* object_file =
          compile_module ~workspace_root ~verbose ~out_dir ~include_dirs
            ~dir:executable.dir stem
        in
        compile (object_file :: acc) rest
  in
  let* object_files = compile [] source_modules in
  let closure = collect_dependency_closure index (Hashtbl.create 8) executable.deps in
  let archive_files =
    List.filter_map
      (function
        | Manifest.Library library when Hashtbl.mem closure library.name ->
            let archive, _ =
              Hashtbl.find library_outputs library.name
            in
            Some archive
        | _ -> None)
      order
  in
  let binary = Filename.concat out_dir executable.name in
  let* _ =
    Process.ensure_success ~verbose "ocamlopt"
      ([ "-o"; binary ] @ archive_files @ object_files)
  in
  print_endline
    (Printf.sprintf "Built executable %s -> %s" executable.name binary);
  Ok (Built_executable { name = executable.name; out_dir; binary })

let build ~workspace_root ~verbose ?(requested_targets = []) workspace =
  let workspace_root = Fs.realpath workspace_root in
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
          build_library ~workspace_root ~verbose library library_outputs
        in
        loop (artifact :: artifacts) rest
    | Manifest.Executable executable :: rest ->
        let* artifact =
          build_executable ~workspace_root ~verbose executable order index
            library_outputs
        in
        loop (artifact :: artifacts) rest
  in
  loop [] order
