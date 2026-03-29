type scaffold_kind =
  | Bare
  | Library_only of string
  | Executable_only of string
  | Library_and_executable of string * string

type report = {
  workspace_name : string;
  root_dir : string;
  created_paths : string list;
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

let manifest_contents workspace_name = function
  | Bare ->
      Printf.sprintf {|workspace = %S
version = 1
|} workspace_name
  | Library_only library_name ->
      let module_stem = safe_module_stem library_name in
      Printf.sprintf {|workspace = %S
version = 1

[library.%s]
dir = "lib"
modules = [%S]
|}
        workspace_name library_name module_stem
  | Executable_only executable_name ->
      Printf.sprintf {|workspace = %S
version = 1

[executable.%s]
dir = "app"
main = "main"
|}
        workspace_name executable_name
  | Library_and_executable (library_name, executable_name) ->
      let module_stem = safe_module_stem library_name in
      Printf.sprintf {|workspace = %S
version = 1

[library.%s]
dir = "lib"
modules = [%S]

[executable.%s]
dir = "app"
main = "main"
deps = [%S]
|}
        workspace_name library_name module_stem executable_name library_name

let scaffold_files workspace_name kind =
  let greeting = Printf.sprintf "Hello from %s" workspace_name in
  let manifest = (Manifest.default_filename, manifest_contents workspace_name kind) in
  match kind with
  | Bare -> [ manifest ]
  | Library_only library_name ->
      let module_stem = safe_module_stem library_name in
      [
        manifest;
        ( Filename.concat "lib" (module_stem ^ ".ml"),
          Printf.sprintf {|let message = %S
|} greeting );
      ]
  | Executable_only _ ->
      [
        manifest;
        ( "app/main.ml",
          Printf.sprintf {|let () = print_endline %S
|} greeting );
      ]
  | Library_and_executable (library_name, _) ->
      let module_stem = safe_module_stem library_name in
      let module_name = String.capitalize_ascii module_stem in
      [
        manifest;
        ( Filename.concat "lib" (module_stem ^ ".ml"),
          Printf.sprintf {|let message = %S
|} greeting );
        ( "app/main.ml",
          Printf.sprintf {|let () = print_endline %s.message
|} module_name );
      ]

let resolve_workspace_name root_dir name =
  match name with
  | Some name -> validate_nonempty "workspace name" name
  | None ->
      let derived = Filename.basename root_dir in
      validate_nonempty "workspace name" derived

let resolve_kind ~workspace_name ~library ~executable ~bare =
  if bare then
    match (library, executable) with
    | None, None -> Ok Bare
    | Some _, _ | _, Some _ ->
        Error "--bare cannot be combined with --library or --executable"
  else
    match (library, executable) with
    | None, None -> Ok (Executable_only workspace_name)
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

let init ~root_dir ?name ?library ?executable ~bare ~force () =
  let* () = ensure_root_dir root_dir in
  let* workspace_name = resolve_workspace_name root_dir name in
  let* kind = resolve_kind ~workspace_name ~library ~executable ~bare in
  let files = scaffold_files workspace_name kind in
  let created_paths = List.map fst files in
  let* () = ensure_writable ~force root_dir created_paths in
  List.iter
    (fun (relative_path, contents) ->
      Fs.write_file (Filename.concat root_dir relative_path) contents)
    files;
  Ok { workspace_name; root_dir; created_paths }

let render_report report =
  String.concat "\n"
    (Printf.sprintf "Initialized workspace %s at %s" report.workspace_name
       report.root_dir
    :: List.map (fun path -> "Wrote " ^ path) report.created_paths)
  ^ "\n"
