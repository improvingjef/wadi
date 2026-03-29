type installed_library = {
  name : string;
  dir : string;
  files : string list;
  meta : string;
  requires : string list;
}

type installed_executable = {
  name : string;
  path : string;
}

type install_layout = {
  prefix : string;
  stage_root : string;
  bin_dir : string;
  lib_dir : string;
  share_dir : string;
  ocamlpath : string list;
  destdir : string option;
}

type prefix_request = {
  logical_prefix : string;
  resolved_prefix : string;
  destdir_suffix : string;
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
      {
        logical_prefix = prefix;
        resolved_prefix = Filename.concat workspace_root prefix |> Fs.realpath;
        destdir_suffix = prefix;
      }
  | Some prefix ->
      let resolved_prefix = Fs.realpath prefix in
      { logical_prefix = prefix; resolved_prefix; destdir_suffix = resolved_prefix }
  | None ->
      let resolved_prefix =
        Layout.install_root_for_profile workspace_root profile |> Fs.realpath
      in
      {
        logical_prefix = resolved_prefix;
        resolved_prefix;
        destdir_suffix = resolved_prefix;
      }

let resolve_destdir ~workspace_root = function
  | Some destdir when Filename.is_relative destdir ->
      Some (Filename.concat workspace_root destdir |> Fs.realpath)
  | Some destdir -> Some (Fs.realpath destdir)
  | None -> None

let path_under_destdir ~destdir path =
  let relative_path =
    if Filename.is_relative path then path
    else
      let rec skip index =
        if index < String.length path && path.[index] = '/' then skip (index + 1)
        else index
      in
      let index = skip 0 in
      if index >= String.length path then ""
      else String.sub path index (String.length path - index)
  in
  if relative_path = "" then destdir else Filename.concat destdir relative_path

let install_layout ~workspace_root ~profile ~prefix ~destdir workspace_name =
  let prefix_request = resolve_prefix ~workspace_root ~profile prefix in
  let destdir = resolve_destdir ~workspace_root destdir in
  let stage_root =
    match destdir with
    | None -> prefix_request.resolved_prefix
    | Some destdir ->
        path_under_destdir ~destdir prefix_request.destdir_suffix
  in
  {
    prefix = prefix_request.logical_prefix;
    stage_root;
    bin_dir = Layout.relative_install_bin_dir;
    lib_dir = Layout.relative_install_lib_dir;
    share_dir = Layout.relative_install_share_dir workspace_name;
    ocamlpath = [ Filename.concat stage_root Layout.relative_install_lib_dir ];
    destdir;
  }

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

let json_array items =
  "["
  ^ String.concat ", " items
  ^ "]"

let json_string text =
  "\"" ^ String_util.json_escape text ^ "\""

let json_optional_string = function
  | Some text -> json_string text
  | None -> "null"

let render_meta ~(workspace : Manifest.workspace) (library : Manifest.library)
    filenames =
  let requires =
    String_util.dedup_preserve (library.deps @ library.packages)
  in
  let find_archive suffix =
    List.find_opt (fun name -> String_util.ends_with ~suffix name) filenames
  in
  let lines =
    [
      "description = "
      ^ json_string
          (Printf.sprintf "%s library %s" (workspace_label workspace) library.name);
      "directory = " ^ json_string ".";
    ]
    @
    (match requires with
    | [] -> []
    | requires ->
        [ "requires = " ^ json_string (String.concat " " requires) ])
    @
    (match find_archive ".cma" with
    | Some archive ->
        [ "archive(byte) = " ^ json_string archive ]
    | None -> [])
    @
    (match find_archive ".cmxa" with
    | Some archive ->
        [ "archive(native) = " ^ json_string archive ]
    | None -> [])
  in
  (String.concat "\n" lines ^ "\n", requires)

let install_library ~verbose ~(layout : install_layout)
    ~(workspace : Manifest.workspace) (library : Manifest.library)
    (artifact : Builder.built_artifact) =
  match artifact with
  | Builder.Built_library built_library ->
      let install_dir =
        Layout.install_library_dir layout.stage_root built_library.name
      in
      let filenames = library_install_filenames built_library.out_dir in
      if Fs.exists install_dir then Fs.remove_tree install_dir;
      Fs.ensure_dir install_dir;
      List.iter
        (fun name ->
          let src = Filename.concat built_library.out_dir name in
          let dst = Filename.concat install_dir name in
          report_detail ~verbose (Printf.sprintf "Installing %s -> %s" src dst);
          Fs.copy_file ~src ~dst)
        filenames;
      let meta, requires = render_meta ~workspace library filenames in
      let meta_path =
        Layout.install_library_meta_path layout.stage_root built_library.name
      in
      Fs.write_file meta_path meta;
      print_endline
        (Printf.sprintf "Installed library %s -> %s" built_library.name install_dir);
      Ok
        {
          name = built_library.name;
          dir = Layout.relative_install_library_dir built_library.name;
          files =
            List.map
              (fun name ->
                Filename.concat
                  (Layout.relative_install_library_dir built_library.name)
                  name)
              filenames;
          meta = Layout.relative_install_library_meta_path built_library.name;
          requires;
        }
  | Builder.Built_executable _ | Builder.Built_test _ ->
      Error "internal error: expected a built library artifact"

let install_executable ~verbose ~(layout : install_layout)
    (artifact : Builder.built_artifact) =
  match artifact with
  | Builder.Built_executable executable ->
      let install_path =
        Layout.install_executable_path layout.stage_root executable.name
      in
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

let render_install_metadata ~workspace_name ~profile ~prefix
    ~(layout : install_layout)
    ~(libraries : installed_library list) ~(executables : installed_executable list)
    =
  let render_library (library : installed_library) =
    String.concat "\n"
      [
        "    {";
        "      \"name\": " ^ json_string library.name ^ ",";
        "      \"dir\": " ^ json_string library.dir ^ ",";
        "      \"meta\": " ^ json_string library.meta ^ ",";
        "      \"requires\": "
        ^ json_array (List.map json_string library.requires)
        ^ ",";
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
      "  \"stage_root\": " ^ json_string layout.stage_root ^ ",";
      "  \"destdir\": " ^ json_optional_string layout.destdir ^ ",";
      "  \"layout\": {";
      "    \"bin_dir\": " ^ json_string layout.bin_dir ^ ",";
      "    \"lib_dir\": " ^ json_string layout.lib_dir ^ ",";
      "    \"share_dir\": " ^ json_string layout.share_dir ^ ",";
      "    \"ocamlpath\": "
      ^ json_array (List.map json_string layout.ocamlpath);
      "  },";
      "  \"libraries\": "
      ^ json_array (List.map render_library libraries)
      ^ ",";
      "  \"executables\": "
      ^ json_array (List.map render_executable executables);
      "}";
      "";
    ]

let copy_manifest ~workspace_root ~(layout : install_layout) workspace_name =
  let src = Filename.concat workspace_root Manifest.default_filename in
  let dst = Layout.install_manifest_copy_path layout.stage_root workspace_name in
  Fs.copy_file ~src ~dst;
  dst

let install ~workspace_root ~verbose ~backend_request ?profile ?prefix ?destdir
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
  let workspace_name = workspace_label workspace in
  let layout =
    install_layout ~workspace_root ~profile ~prefix ~destdir workspace_name
  in
  Fs.ensure_dir layout.stage_root;
  let selected_index = Hashtbl.create (List.length requested_names) in
  List.iter (fun name -> Hashtbl.replace selected_index name ()) requested_names;
  let library_index = Hashtbl.create (List.length workspace.targets) in
  List.iter
    (function
      | Manifest.Library library -> Hashtbl.replace library_index library.name library
      | Manifest.Executable _ | Manifest.Test _ -> ())
    workspace.targets;
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
    | Builder.Built_library built_library as artifact :: rest ->
        let* manifest_library =
          match Hashtbl.find_opt library_index built_library.name with
          | Some library -> Ok library
          | None ->
              Error
                (Printf.sprintf
                   "internal error: missing manifest library '%s' during install"
                   built_library.name)
        in
        let* library =
          install_library ~verbose ~layout ~workspace manifest_library artifact
        in
        collect (library :: libraries) executables rest
    | Builder.Built_executable _ as artifact :: rest ->
        let* executable = install_executable ~verbose ~layout artifact in
        collect libraries (executable :: executables) rest
    | Builder.Built_test _ :: rest -> collect libraries executables rest
  in
  let* libraries, executables = collect [] [] selected_artifacts in
  let _manifest_copy = copy_manifest ~workspace_root ~layout workspace_name in
  let metadata =
    render_install_metadata ~workspace_name ~profile ~prefix:layout.prefix
      ~layout ~libraries
      ~executables
  in
  let metadata_path =
    Layout.install_metadata_path layout.stage_root workspace_name
  in
  Fs.write_file metadata_path metadata;
  print_endline (Printf.sprintf "Wrote install metadata -> %s" metadata_path);
  Ok 0
