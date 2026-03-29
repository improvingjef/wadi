type installed_library = {
  name : string;
  dir : string;
  files : string list;
}

type installed_executable = {
  name : string;
  path : string;
}

let ( let* ) = Result.bind

let report_detail ~verbose message =
  if verbose then prerr_endline message

let workspace_label (workspace : Manifest.workspace) =
  match workspace.name with
  | Some name when String.trim name <> "" -> name
  | Some _ | None -> "workspace"

let resolve_prefix ~workspace_root ~profile = function
  | Some prefix when Filename.is_relative prefix ->
      Filename.concat workspace_root prefix
  | Some prefix -> prefix
  | None -> Layout.install_root_for_profile workspace_root profile

let installable_targets (workspace : Manifest.workspace) =
  List.filter
    (function
      | Manifest.Library _ | Manifest.Executable _ -> true
      | Manifest.Test _ -> false)
    workspace.targets

let resolve_requested_targets workspace requested_targets =
  let requested_targets = String_util.dedup_preserve requested_targets in
  if requested_targets = [] then
    match installable_targets workspace with
    | [] ->
        Error "workspace does not define any installable libraries or executables"
    | targets -> Ok targets
  else
    let index = Hashtbl.create (List.length workspace.targets) in
    List.iter
      (fun target ->
        Hashtbl.replace index (Manifest.target_name target) target)
      workspace.targets;
    let rec loop acc = function
      | [] -> Ok (List.rev acc)
      | name :: rest -> (
          match Hashtbl.find_opt index name with
          | None -> Error (Printf.sprintf "unknown target '%s'" name)
          | Some (Manifest.Test _) ->
              Error
                (Printf.sprintf
                   "target '%s' is a test; oasis install only supports libraries \
                    and executables"
                   name)
          | Some target -> loop (target :: acc) rest)
    in
    loop [] requested_targets

let selected_names targets = List.map Manifest.target_name targets

let library_install_filenames out_dir =
  Sys.readdir out_dir
  |> Array.to_list
  |> List.filter (fun name ->
         let path = Filename.concat out_dir name in
         if Sys.is_directory path then false
         else
           List.exists
             (fun suffix -> String_util.ends_with ~suffix name)
             [ ".cmi"; ".cmo"; ".cmx"; ".cmxa"; ".cma"; ".a"; ".o" ])
  |> List.sort String.compare

let install_library ~verbose ~prefix (library : Builder.built_artifact) =
  match library with
  | Builder.Built_library library ->
      let install_dir = Layout.install_library_dir prefix library.name in
      let filenames = library_install_filenames library.out_dir in
      if Fs.exists install_dir then Fs.remove_tree install_dir;
      Fs.ensure_dir install_dir;
      List.iter
        (fun name ->
          let src = Filename.concat library.out_dir name in
          let dst = Filename.concat install_dir name in
          report_detail ~verbose (Printf.sprintf "Installing %s -> %s" src dst);
          Fs.copy_file ~src ~dst)
        filenames;
      print_endline
        (Printf.sprintf "Installed library %s -> %s" library.name install_dir);
      Ok
        {
          name = library.name;
          dir = Layout.relative_install_library_dir library.name;
          files =
            List.map
              (fun name ->
                Filename.concat (Layout.relative_install_library_dir library.name) name)
              filenames;
        }
  | Builder.Built_executable _ | Builder.Built_test _ ->
      Error "internal error: expected a built library artifact"

let install_executable ~verbose ~prefix (artifact : Builder.built_artifact) =
  match artifact with
  | Builder.Built_executable executable ->
      let install_path = Layout.install_executable_path prefix executable.name in
      report_detail ~verbose
        (Printf.sprintf "Installing %s -> %s" executable.binary install_path);
      Fs.copy_file ~src:executable.binary ~dst:install_path;
      print_endline
        (Printf.sprintf "Installed executable %s -> %s" executable.name install_path);
      Ok
        {
          name = executable.name;
          path = Layout.relative_install_executable_path executable.name;
        }
  | Builder.Built_library _ | Builder.Built_test _ ->
      Error "internal error: expected a built executable artifact"

let json_array items =
  "["
  ^ String.concat ", " items
  ^ "]"

let json_string text =
  "\"" ^ String_util.json_escape text ^ "\""

let render_install_metadata ~workspace_name ~profile ~prefix
    ~(libraries : installed_library list) ~(executables : installed_executable list)
    =
  let render_library (library : installed_library) =
    String.concat "\n"
      [
        "    {";
        "      \"name\": " ^ json_string library.name ^ ",";
        "      \"dir\": " ^ json_string library.dir ^ ",";
        "      \"files\": "
        ^ json_array (List.map json_string library.files);
        "    }";
      ]
  in
  let render_executable (executable : installed_executable) =
    String.concat "\n"
      [
        "    {";
        "      \"name\": " ^ json_string executable.name ^ ",";
        "      \"path\": " ^ json_string executable.path;
        "    }";
      ]
  in
  String.concat "\n"
    [
      "{";
      "  \"workspace\": " ^ json_string workspace_name ^ ",";
      "  \"profile\": " ^ json_string profile ^ ",";
      "  \"prefix\": " ^ json_string prefix ^ ",";
      "  \"libraries\": "
      ^ json_array (List.map render_library libraries)
      ^ ",";
      "  \"executables\": "
      ^ json_array (List.map render_executable executables);
      "}";
      "";
    ]

let copy_manifest ~workspace_root ~prefix workspace_name =
  let src = Filename.concat workspace_root Manifest.default_filename in
  let dst = Layout.install_manifest_copy_path prefix workspace_name in
  Fs.copy_file ~src ~dst;
  dst

let install ~workspace_root ~verbose ~backend_request ?profile ?prefix
    ~requested_targets workspace =
  let workspace_root = Fs.realpath workspace_root in
  let profile =
    match profile with
    | Some profile when String.trim profile <> "" -> profile
    | Some _ | None -> Manifest.default_profile workspace
  in
  let* targets = resolve_requested_targets workspace requested_targets in
  let requested_names = selected_names targets in
  let* build_result =
    Builder.build ~workspace_root ~verbose ~requested_targets:requested_names
      ~backend_request ~profile workspace
  in
  let prefix = resolve_prefix ~workspace_root ~profile prefix |> Fs.realpath in
  Fs.ensure_dir prefix;
  let selected_index = Hashtbl.create (List.length requested_names) in
  List.iter (fun name -> Hashtbl.replace selected_index name ()) requested_names;
  let selected_artifacts =
    List.filter
      (function
        | Builder.Built_library library -> Hashtbl.mem selected_index library.name
        | Builder.Built_executable executable ->
            Hashtbl.mem selected_index executable.name
        | Builder.Built_test _ -> false)
      build_result.artifacts
  in
  let rec collect libraries executables = function
    | [] -> Ok (List.rev libraries, List.rev executables)
    | Builder.Built_library _ as artifact :: rest ->
        let* library = install_library ~verbose ~prefix artifact in
        collect (library :: libraries) executables rest
    | Builder.Built_executable _ as artifact :: rest ->
        let* executable = install_executable ~verbose ~prefix artifact in
        collect libraries (executable :: executables) rest
    | Builder.Built_test _ :: rest -> collect libraries executables rest
  in
  let* libraries, executables = collect [] [] selected_artifacts in
  let workspace_name = workspace_label workspace in
  let _manifest_copy = copy_manifest ~workspace_root ~prefix workspace_name in
  let metadata =
    render_install_metadata ~workspace_name ~profile ~prefix ~libraries
      ~executables
  in
  let metadata_path = Layout.install_metadata_path prefix workspace_name in
  Fs.write_file metadata_path metadata;
  print_endline (Printf.sprintf "Wrote install metadata -> %s" metadata_path);
  Ok 0
