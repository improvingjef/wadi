type scaffold_kind =
  | Bare
  | Library_only of string
  | Executable_only of string
  | Library_and_executable of string * string

type report = {
  workspace_name : string;
  root_dir : string;
  created_paths : string list;
  member_path : string option;
  member_registered : bool;
}

let ( let* ) = Result.bind

let validate_nonempty label value =
  let value = String.trim value in
  if value = "" then Error (Printf.sprintf "%s cannot be empty" label) else Ok value

let validate_target_name label value =
  let* value = validate_nonempty label value in
  if String.contains value '/' then
    Error (Printf.sprintf "%s must not contain '/': %s" label value)
  else if String.contains value '.' then
    Error (Printf.sprintf "%s must not contain '.': %s" label value)
  else Ok value

let validate_member_path value =
  let* value = validate_nonempty "member path" value in
  if not (Filename.is_relative value) then
    Error (Printf.sprintf "member path must be relative: %s" value)
  else
    let parts =
      String.split_on_char '/' value |> List.filter (fun part -> part <> "")
    in
    if parts = [] then Error "member path cannot be empty"
    else if List.exists (fun part -> part = "." || part = "..") parts then
      Error
        (Printf.sprintf
           "member path must not contain '.' or '..' segments: %s" value)
    else Ok (String.concat "/" parts)

let safe_module_stem name =
  let buffer = Buffer.create (String.length name + 8) in
  String.iter
    (fun ch ->
      match ch with
      | 'a' .. 'z' | '0' .. '9' | '_' ->
          Buffer.add_char buffer ch
      | 'A' .. 'Z' ->
          Buffer.add_char buffer (Char.lowercase_ascii ch)
      | _ -> Buffer.add_char buffer '_')
    name;
  let stem = Buffer.contents buffer in
  let stem =
    if stem = "" then "module"
    else
      match stem.[0] with
      | '0' .. '9' -> "module_" ^ stem
      | _ -> stem
  in
  if stem = "" then "module" else stem

let manifest_body_lines = function
  | Bare -> []
  | Library_only library_name ->
      let module_stem = safe_module_stem library_name in
      [ Printf.sprintf "[library.%s]" library_name; {|dir = "lib"|}; Printf.sprintf "modules = [%S]" module_stem ]
  | Executable_only executable_name ->
      [ Printf.sprintf "[executable.%s]" executable_name; {|dir = "app"|}; {|main = "main"|} ]
  | Library_and_executable (library_name, executable_name) ->
      let module_stem = safe_module_stem library_name in
      [
        Printf.sprintf "[library.%s]" library_name;
        {|dir = "lib" |} |> String.trim;
        Printf.sprintf "modules = [%S]" module_stem;
        "";
        Printf.sprintf "[executable.%s]" executable_name;
        {|dir = "app"|};
        {|main = "main"|};
        Printf.sprintf "deps = [%S]" library_name;
      ]

let render_manifest ?workspace_name ?(members = []) kind =
  let header =
    match workspace_name with
    | Some workspace_name ->
        [
          Printf.sprintf "workspace = %S" workspace_name;
          "version = 1";
        ]
        @ (match members with
          | [] -> []
          | members -> [ Vendor.members_line members ])
    | None -> []
  in
  let body = manifest_body_lines kind in
  let lines =
    header
    @
    match (header, body) with
    | [], body -> body
    | _header, [] -> []
    | _header, body -> "" :: body
  in
  String.concat "\n" (lines @ [ "" ])

let rebase_path prefix path =
  if prefix = "" then path else Filename.concat prefix path

let scaffold_files ~scaffold_name ~manifest_path ~source_prefix
    ~manifest_contents kind =
  let greeting = Printf.sprintf "Hello from %s" scaffold_name in
  let manifest = (manifest_path, manifest_contents) in
  match kind with
  | Bare -> [ manifest ]
  | Library_only library_name ->
      let module_stem = safe_module_stem library_name in
      [
        manifest;
        ( rebase_path source_prefix (Filename.concat "lib" (module_stem ^ ".ml")),
          Printf.sprintf {|let message = %S
|} greeting );
      ]
  | Executable_only _ ->
      [
        manifest;
        ( rebase_path source_prefix "app/main.ml",
          Printf.sprintf {|let () = print_endline %S
|} greeting );
      ]
  | Library_and_executable (library_name, _) ->
      let module_stem = safe_module_stem library_name in
      let module_name = String.capitalize_ascii module_stem in
      [
        manifest;
        ( rebase_path source_prefix (Filename.concat "lib" (module_stem ^ ".ml")),
          Printf.sprintf {|let message = %S
|} greeting );
        ( rebase_path source_prefix "app/main.ml",
          Printf.sprintf {|let () = print_endline %s.message
|} module_name );
      ]

let resolve_workspace_name root_dir name =
  match name with
  | Some name -> validate_nonempty "workspace name" name
  | None ->
      let derived = Filename.basename root_dir in
      validate_nonempty "workspace name" derived

let resolve_existing_workspace_name root_dir requested_name existing_name =
  match existing_name with
  | Some existing_name when String.trim existing_name <> "" -> (
      match requested_name with
      | None -> Ok existing_name
      | Some requested_name ->
          let* requested_name = validate_nonempty "workspace name" requested_name in
          if requested_name = existing_name then Ok existing_name
          else
            Error
              (Printf.sprintf
                 "workspace is already named %s; omit --name or reuse that name"
                 existing_name) )
  | Some _ | None -> (
      match requested_name with
      | Some _ ->
          Error
            "the root manifest already exists; --name only applies when creating \
             a new workspace root"
      | None ->
          let derived = Filename.basename root_dir in
          validate_nonempty "workspace name" derived )

let resolve_kind ~scaffold_name ~library ~executable ~bare =
  if bare then
    match (library, executable) with
    | None, None -> Ok Bare
    | Some _, _ | _, Some _ ->
        Error "--bare cannot be combined with --library or --executable"
  else
    match (library, executable) with
    | None, None ->
        let* executable_name =
          validate_target_name "default target name" scaffold_name
        in
        Ok (Executable_only executable_name)
    | Some library_name, None ->
        let* library_name = validate_target_name "library name" library_name in
        Ok (Library_only library_name)
    | None, Some executable_name ->
        let* executable_name =
          validate_target_name "executable name" executable_name
        in
        Ok (Executable_only executable_name)
    | Some library_name, Some executable_name ->
        let* library_name = validate_target_name "library name" library_name in
        let* executable_name =
          validate_target_name "executable name" executable_name
        in
        if library_name = executable_name then
          Error
            "library and executable names must differ when both are scaffolded"
        else Ok (Library_and_executable (library_name, executable_name))

let ensure_root_dir root_dir =
  if Fs.exists root_dir && not (Fs.is_directory root_dir) then
    Error (Printf.sprintf "init target exists and is not a directory: %s" root_dir)
  else (
    Fs.ensure_dir root_dir;
    Ok ())

let ensure_writable ~force root_dir paths =
  let rec loop = function
    | [] -> Ok ()
    | relative_path :: rest ->
        let absolute_path = Filename.concat root_dir relative_path in
        if Fs.exists absolute_path && not force then
          Error
            (Printf.sprintf
               "refusing to overwrite existing scaffold path %s; rerun with --force"
               absolute_path)
        else loop rest
  in
  loop paths

let init_root ~root_dir ?name ?library ?executable ~bare ~force () =
  let* () = ensure_root_dir root_dir in
  let* workspace_name = resolve_workspace_name root_dir name in
  let* kind =
    resolve_kind ~scaffold_name:workspace_name ~library ~executable ~bare
  in
  let files =
    scaffold_files ~scaffold_name:workspace_name
      ~manifest_path:Manifest.default_filename ~source_prefix:""
      ~manifest_contents:(render_manifest ~workspace_name kind) kind
  in
  let created_paths = List.map fst files in
  let* () = ensure_writable ~force root_dir created_paths in
  List.iter
    (fun (relative_path, contents) ->
      Fs.write_file (Filename.concat root_dir relative_path) contents)
    files;
  Ok
    {
      workspace_name;
      root_dir;
      created_paths;
      member_path = None;
      member_registered = false;
    }

let init_member ~root_dir ?name ?library ?executable ~bare ~force member_path =
  let* () = ensure_root_dir root_dir in
  let* member_path = validate_member_path member_path in
  let root_manifest_path = Filename.concat root_dir Manifest.default_filename in
  let* root_loaded =
    if Fs.exists root_manifest_path then
      Manifest.load_local root_manifest_path |> Result.map Option.some
    else Ok None
  in
  let* workspace_name =
    match root_loaded with
    | Some loaded ->
        resolve_existing_workspace_name root_dir name loaded.workspace.Manifest.name
    | None -> resolve_workspace_name root_dir name
  in
  let scaffold_name = Filename.basename member_path in
  let* kind =
    resolve_kind ~scaffold_name ~library ~executable ~bare
  in
  let member_files =
    scaffold_files ~scaffold_name
      ~manifest_path:(Filename.concat member_path Manifest.default_filename)
      ~source_prefix:member_path
      ~manifest_contents:(render_manifest kind) kind
  in
  let member_registered =
    match root_loaded with
    | Some loaded -> not (List.mem member_path loaded.members)
    | None -> true
  in
  let files =
    match root_loaded with
    | Some _ -> member_files
    | None ->
        let root_manifest =
          ( Manifest.default_filename,
            render_manifest ~workspace_name ~members:[ member_path ] Bare )
        in
        root_manifest :: member_files
  in
  let created_paths = List.map fst files in
  let* () = ensure_writable ~force root_dir created_paths in
  List.iter
    (fun (relative_path, contents) ->
      Fs.write_file (Filename.concat root_dir relative_path) contents)
    files;
  let* () =
    match root_loaded with
    | Some loaded when member_registered ->
        Vendor.rewrite_members root_manifest_path (loaded.members @ [ member_path ])
    | Some _ | None -> Ok ()
  in
  Ok
    {
      workspace_name;
      root_dir;
      created_paths;
      member_path = Some member_path;
      member_registered;
    }

let init ~root_dir ?name ?library ?executable ?member ~bare ~force () =
  match member with
  | None -> init_root ~root_dir ?name ?library ?executable ~bare ~force ()
  | Some member_path ->
      init_member ~root_dir ?name ?library ?executable ~bare ~force member_path

let render_report report =
  let header =
    match report.member_path with
    | None ->
        Printf.sprintf "Initialized workspace %s at %s" report.workspace_name
          report.root_dir
    | Some member_path ->
        Printf.sprintf "Initialized member %s in workspace %s at %s" member_path
          report.workspace_name report.root_dir
  in
  let detail_lines =
    (match report.member_path with
    | Some member_path when report.member_registered ->
        [ "Registered workspace member " ^ member_path ]
    | Some member_path ->
        [ "Kept existing workspace member " ^ member_path ]
    | None -> [])
    @ List.map (fun path -> "Wrote " ^ path) report.created_paths
  in
  String.concat "\n" (header :: detail_lines) ^ "\n"
