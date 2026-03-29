type sexp =
  | Atom of string
  | List of sexp list

type raw_target_kind =
  | Library
  | Executable
  | Test

type raw_target = {
  kind : raw_target_kind;
  name : string;
  public_name : string option;
  dir : string;
  main : string option;
  modules : string list option;
  libraries : string list;
}

type migration = {
  manifest : string;
  warnings : string list;
}

let ( let* ) = Result.bind

let parse_error path message = Error (Printf.sprintf "%s: %s" path message)

let rec skip_space text index =
  if index >= String.length text then index
  else
    match text.[index] with
    | ' ' | '\t' | '\r' | '\n' -> skip_space text (index + 1)
    | ';' -> skip_comment text (index + 1)
    | _ -> index

and skip_comment text index =
  if index >= String.length text then index
  else if text.[index] = '\n' then skip_space text (index + 1)
  else skip_comment text (index + 1)

let parse_string path text index =
  let buffer = Buffer.create 32 in
  let rec loop index =
    if index >= String.length text then
      parse_error path "unterminated string literal"
    else
      match text.[index] with
      | '"' -> Ok (Buffer.contents buffer, index + 1)
      | '\\' ->
          if index + 1 >= String.length text then
            parse_error path "unterminated escape sequence"
          else
            let escaped =
              match text.[index + 1] with
              | '"' -> '"'
              | '\\' -> '\\'
              | 'n' -> '\n'
              | 't' -> '\t'
              | ch -> ch
            in
            Buffer.add_char buffer escaped;
            loop (index + 2)
      | ch ->
          Buffer.add_char buffer ch;
          loop (index + 1)
  in
  loop index

let parse_atom text index =
  let rec loop stop =
    if stop >= String.length text then stop
    else
      match text.[stop] with
      | ' ' | '\t' | '\r' | '\n' | '(' | ')' | ';' -> stop
      | _ -> loop (stop + 1)
  in
  let stop = loop index in
  (String.sub text index (stop - index), stop)

let rec parse_one path text index =
  let index = skip_space text index in
  if index >= String.length text then
    parse_error path "unexpected end of file while parsing s-expression"
  else
    match text.[index] with
    | '(' -> parse_list path text (index + 1) []
    | ')' -> parse_error path "unexpected ')'"
    | '"' ->
        let* value, next_index = parse_string path text (index + 1) in
        Ok (Atom value, next_index)
    | _ ->
        let atom, next_index = parse_atom text index in
        Ok (Atom atom, next_index)

and parse_list path text index acc =
  let index = skip_space text index in
  if index >= String.length text then parse_error path "unterminated list"
  else if text.[index] = ')' then Ok (List (List.rev acc), index + 1)
  else
    let* value, next_index = parse_one path text index in
    parse_list path text next_index (value :: acc)

let parse_many path text =
  let rec loop index acc =
    let index = skip_space text index in
    if index >= String.length text then Ok (List.rev acc)
    else
      let* value, next_index = parse_one path text index in
      loop next_index (value :: acc)
  in
  loop 0 []

let field_name = function
  | List (Atom name :: _) -> Some name
  | _ -> None

let field_map fields =
  let table = Hashtbl.create (List.length fields) in
  List.iter
    (fun field ->
      match field_name field with
      | Some name -> Hashtbl.replace table name field
      | None -> ())
    fields;
  table

let field_atoms name fields =
  match Hashtbl.find_opt fields name with
  | None -> Ok None
  | Some (List (_ :: values)) ->
      let rec loop acc = function
        | [] -> Ok (Some (List.rev acc))
        | Atom value :: rest -> loop (value :: acc) rest
        | List _ :: _ ->
            Error
              (Printf.sprintf
                 "field '%s' uses a dune form this migrator does not understand"
                 name)
      in
      loop [] values
  | Some _ -> Error (Printf.sprintf "field '%s' is malformed" name)

let required_atom_field name fields =
  let* values = field_atoms name fields in
  match values with
  | Some [ value ] -> Ok value
  | Some _ ->
      Error
        (Printf.sprintf "field '%s' must contain exactly one atom/string" name)
  | None -> Error (Printf.sprintf "missing required field '%s'" name)

let optional_atom_field name fields =
  let* values = field_atoms name fields in
  match values with
  | Some [ value ] -> Ok (Some value)
  | Some _ ->
      Error
        (Printf.sprintf "field '%s' must contain exactly one atom/string" name)
  | None -> Ok None

let optional_atom_list_field name fields =
  let* values = field_atoms name fields in
  Ok (Option.value ~default:[] values)

let source_stems_in_dir dir =
  let path = if dir = "." then "." else dir in
  if not (Fs.exists path) || not (Fs.is_directory path) then []
  else
    Sys.readdir path
    |> Array.to_list
    |> List.filter_map (fun entry ->
           if String_util.ends_with ~suffix:".ml" entry
              || String_util.ends_with ~suffix:".mli" entry
           then Some (Filename.remove_extension entry)
           else None)
    |> List.sort_uniq String.compare

let relative_dir workspace_root dune_path =
  let dune_dir = Filename.dirname dune_path in
  if dune_dir = workspace_root then "."
  else
    let prefix = workspace_root ^ "/" in
    if String_util.starts_with ~prefix dune_dir then
      String.sub dune_dir (String.length prefix)
        (String.length dune_dir - String.length prefix)
    else dune_dir

let parse_library ~workspace_root ~dune_path fields =
  let name = required_atom_field "name" fields in
  let* name = name in
  let* public_name = optional_atom_field "public_name" fields in
  let dir = relative_dir workspace_root dune_path in
  let inferred_modules = source_stems_in_dir (Filename.dirname dune_path) in
  let* modules = field_atoms "modules" fields in
  let modules =
    match modules with
    | Some modules -> modules
    | None -> inferred_modules
  in
  let* libraries = optional_atom_list_field "libraries" fields in
  Ok
    [
      {
        kind = Library;
        name;
        public_name;
        dir;
        main = None;
        modules = Some modules;
        libraries;
      };
    ]

let pair_public_names names public_names =
  let rec loop acc names public_names =
    match (names, public_names) with
    | [], _ -> List.rev acc
    | name :: rest, public_name :: public_rest ->
        loop ((name, Some public_name) :: acc) rest public_rest
    | name :: rest, [] -> loop ((name, None) :: acc) rest []
  in
  loop [] names public_names

let parse_runnable_group kind_label raw_kind ~workspace_root ~dune_path fields
    ~names_field ~public_names_field =
  let dir = relative_dir workspace_root dune_path in
  let dune_dir = Filename.dirname dune_path in
  let inferred_modules = source_stems_in_dir dune_dir in
  let* names = optional_atom_list_field names_field fields in
  let* fallback_name = optional_atom_field "name" fields in
  let names =
    match (names, fallback_name) with
    | [], Some name -> [ name ]
    | names, _ -> names
  in
  if names = [] then
    Error (Printf.sprintf "%s stanza is missing a name" kind_label)
  else
    let* public_names = optional_atom_list_field public_names_field fields in
    let* public_name = optional_atom_field "public_name" fields in
    let public_names =
      match (public_names, public_name) with
      | [], Some value -> [ value ]
      | values, _ -> values
    in
    let* modules = field_atoms "modules" fields in
    let helper_modules =
      let modules =
        match modules with
        | Some modules -> modules
        | None -> inferred_modules
      in
      List.filter (fun module_name -> not (List.mem module_name names)) modules
    in
    let* libraries = optional_atom_list_field "libraries" fields in
    Ok
      (pair_public_names names public_names
      |> List.map (fun (name, public_name) ->
             {
               kind = raw_kind;
               name;
               public_name;
               dir;
               main = Some name;
               modules = Some helper_modules;
               libraries;
             }))

let parse_stanza ~workspace_root ~dune_path warnings = function
  | List (Atom "library" :: fields) ->
      let* targets = parse_library ~workspace_root ~dune_path (field_map fields) in
      Ok (targets, warnings)
  | List (Atom "executable" :: fields) ->
      parse_runnable_group "executable" Executable ~workspace_root ~dune_path
        (field_map fields) ~names_field:"names" ~public_names_field:"public_names"
      |> Result.map (fun targets -> (targets, warnings))
  | List (Atom "executables" :: fields) ->
      parse_runnable_group "executables" Executable ~workspace_root ~dune_path
        (field_map fields) ~names_field:"names" ~public_names_field:"public_names"
      |> Result.map (fun targets -> (targets, warnings))
  | List (Atom "test" :: fields) ->
      parse_runnable_group "test" Test ~workspace_root ~dune_path
        (field_map fields) ~names_field:"names" ~public_names_field:"public_names"
      |> Result.map (fun targets -> (targets, warnings))
  | List (Atom "tests" :: fields) ->
      parse_runnable_group "tests" Test ~workspace_root ~dune_path
        (field_map fields) ~names_field:"names" ~public_names_field:"public_names"
      |> Result.map (fun targets -> (targets, warnings))
  | List (Atom stanza_name :: _) ->
      Ok
        ( [],
          warnings
          @
          [
            Printf.sprintf
              "ignored unsupported dune stanza '%s' in %s; migrate it manually"
              stanza_name dune_path;
          ] )
  | _ ->
      Ok
        ( [],
          warnings
          @ [ Printf.sprintf "ignored malformed dune form in %s" dune_path ] )

let rec scan_workspace root_dir relative_dir acc =
  let dir =
    if relative_dir = "." then root_dir else Filename.concat root_dir relative_dir
  in
  let entries = Sys.readdir dir |> Array.to_list |> List.sort String.compare in
  List.fold_left
    (fun result entry ->
      let* files = result in
      let next_relative =
        if relative_dir = "." then entry else Filename.concat relative_dir entry
      in
      let path = Filename.concat root_dir next_relative in
      if Fs.is_directory path then
        if
          List.mem entry [ ".git"; "_build"; "_bootstrap"; "_oasis" ]
          || String_util.starts_with ~prefix:"." entry
        then Ok files
        else scan_workspace root_dir next_relative files
      else if entry = "dune" then Ok (path :: files)
      else Ok files)
    (Ok acc) entries

let dune_project_name workspace_root =
  let dune_project = Filename.concat workspace_root "dune-project" in
  if not (Fs.exists dune_project) then Ok None
  else
    let* sexps = parse_many dune_project (Fs.read_file dune_project) in
    let rec find_name = function
      | [] -> None
      | List (Atom "name" :: Atom name :: _) :: _ -> Some name
      | List (Atom "package" :: fields) :: rest -> (
          match fields with
          | List (Atom "name" :: Atom name :: _) :: _ -> Some name
          | _ -> find_name rest)
      | _ :: rest -> find_name rest
    in
    Ok (find_name sexps)

let index_workspace_libraries targets =
  let table = Hashtbl.create 16 in
  List.iter
    (fun target ->
      if target.kind = Library then (
        Hashtbl.replace table target.name target.name;
        match target.public_name with
        | Some public_name -> Hashtbl.replace table public_name target.name
        | None -> ()))
    targets;
  table

let toml_string value = "\"" ^ String_util.json_escape value ^ "\""

let toml_array values =
  "[" ^ String.concat ", " (List.map toml_string values) ^ "]"

let render_target alias_index (target : raw_target) =
  let deps, packages =
    List.fold_left
      (fun (deps, packages) library_name ->
        match Hashtbl.find_opt alias_index library_name with
        | Some dependency when dependency <> target.name ->
            (deps @ [ dependency ], packages)
        | _ -> (deps, packages @ [ library_name ]))
      ([], []) target.libraries
  in
  let deps = String_util.dedup_preserve deps in
  let packages = String_util.dedup_preserve packages in
  let section_name =
    match target.kind with
    | Library -> "library"
    | Executable -> "executable"
    | Test -> "test"
  in
  let header_comment =
    match target.public_name with
    | Some public_name when public_name <> target.name ->
        [ Printf.sprintf "# dune public_name = %S" public_name ]
    | _ -> []
  in
  let body =
    match target.kind with
    | Library ->
        [
          Printf.sprintf "[%s.%s]" section_name target.name;
          "dir = " ^ toml_string target.dir;
          "modules = "
          ^
          toml_array
            (match target.modules with
            | Some modules -> modules
            | None -> []);
        ]
    | Executable | Test ->
        [
          Printf.sprintf "[%s.%s]" section_name target.name;
          "dir = " ^ toml_string target.dir;
          "main = "
          ^
          toml_string
            (match target.main with
            | Some main -> main
            | None -> target.name);
        ]
        @
        (match target.modules with
        | Some [] | None -> []
        | Some modules -> [ "modules = " ^ toml_array modules ])
  in
  header_comment @ body
  @
  (match deps with
  | [] -> []
  | deps -> [ "deps = " ^ toml_array deps ])
  @
  (match packages with
  | [] -> []
  | packages -> [ "packages = " ^ toml_array packages ])

let generate_manifest ~workspace_root ~workspace_name targets warnings =
  if targets = [] then Error "no migratable dune stanzas were found"
  else
    let alias_index = index_workspace_libraries targets in
    let warning_block =
      match String_util.dedup_preserve warnings with
      | [] -> []
      | warnings ->
          [ "# Migration warnings:" ]
          @ List.map (fun warning -> "# - " ^ warning) warnings
          @ [ "" ]
    in
    let header =
      [
        "# Generated by `oasis migrate`.";
        "# Review comments and warnings before deleting your dune files.";
        "";
      ]
      @ warning_block
      @
      match workspace_name with
      | Some name -> [ "workspace = " ^ toml_string name; "version = 1"; "" ]
      | None -> [ "version = 1"; "" ]
    in
    let body =
      List.concat_map
        (fun target -> render_target alias_index target @ [ "" ])
        targets
    in
    Ok
      {
        manifest = String.concat "\n" (header @ body);
        warnings = String_util.dedup_preserve warnings;
      }

let run ~workspace_root =
  let workspace_root = Fs.realpath workspace_root in
  let* dune_files = scan_workspace workspace_root "." [] in
  if dune_files = [] then
    Error
      (Printf.sprintf "no dune files were found under workspace %s" workspace_root)
  else
    let* workspace_name = dune_project_name workspace_root in
    let rec collect targets warnings = function
      | [] -> generate_manifest ~workspace_root ~workspace_name targets warnings
      | dune_path :: rest ->
          let* sexps = parse_many dune_path (Fs.read_file dune_path) in
          let* parsed_targets, warnings =
            List.fold_left
              (fun result sexp ->
                let* acc_targets, acc_warnings = result in
                let* new_targets, new_warnings =
                  parse_stanza ~workspace_root ~dune_path acc_warnings sexp
                in
                Ok (acc_targets @ new_targets, new_warnings))
              (Ok ([], warnings)) sexps
          in
          collect (targets @ parsed_targets) warnings rest
    in
    collect [] [] (List.rev dune_files)
