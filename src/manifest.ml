type value =
  | String of string
  | Int of int
  | Strings of string list

type library = {
  name : string;
  dir : string;
  modules : string list;
  deps : string list;
  packages : string list;
}

type runnable = {
  name : string;
  dir : string;
  main : string;
  modules : string list;
  deps : string list;
  packages : string list;
}

type executable = runnable

type test_target = runnable

type target =
  | Library of library
  | Executable of executable
  | Test of test_target

type workspace = {
  name : string option;
  version : int;
  targets : target list;
}

type binding = {
  key : string;
  value : value;
  line : int;
}

type section = {
  path : string list;
  line : int;
  bindings : binding list;
}

let default_filename = "oasis.toml"

let ( let* ) = Result.bind

let error path line message =
  Error (Printf.sprintf "%s:%d: %s" path line message)

let target_name = function
  | Library library -> library.name
  | Executable executable -> executable.name
  | Test test -> test.name

let target_deps = function
  | Library library -> library.deps
  | Executable executable -> executable.deps
  | Test test -> test.deps

let target_packages = function
  | Library library -> library.packages
  | Executable executable -> executable.packages
  | Test test -> test.packages

let target_kind_name = function
  | Library _ -> "library"
  | Executable _ -> "executable"
  | Test _ -> "test"

let parse_quoted_string path line text start_index =
  let length = String.length text in
  if start_index >= length || text.[start_index] <> '"' then
    error path line "expected a quoted string"
  else
    let buffer = Buffer.create 32 in
    let rec loop index =
      if index >= length then error path line "unterminated string literal"
      else
        match text.[index] with
        | '"' -> Ok (Buffer.contents buffer, index + 1)
        | '\\' ->
            if index + 1 >= length then
              error path line "unterminated escape sequence"
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
    loop (start_index + 1)

let parse_string_value path line text =
  let* value, next_index = parse_quoted_string path line text 0 in
  let trailing =
    String.sub text next_index (String.length text - next_index) |> String.trim
  in
  if trailing <> "" then error path line "unexpected content after string literal"
  else Ok value

let parse_string_array path line text =
  let length = String.length text in
  if length < 2 || text.[0] <> '[' || text.[length - 1] <> ']' then
    error path line "malformed array literal"
  else
    let inner = String.sub text 1 (length - 2) in
    let inner_length = String.length inner in
    let rec skip_whitespace index =
      if index < inner_length then
        match inner.[index] with
        | ' ' | '\t' -> skip_whitespace (index + 1)
        | _ -> index
      else index
    in
    let rec parse_items index acc =
      let index = skip_whitespace index in
      if index >= inner_length then Ok (List.rev acc)
      else
        let* item, next_index = parse_quoted_string path line inner index in
        let next_index = skip_whitespace next_index in
        if next_index >= inner_length then Ok (List.rev (item :: acc))
        else if inner.[next_index] = ',' then
          parse_items (next_index + 1) (item :: acc)
        else error path line "expected a comma between array elements"
    in
    parse_items 0 []

let parse_value path line text =
  if String_util.starts_with ~prefix:"\"" text then
    let* value = parse_string_value path line text in
    Ok (String value)
  else if String_util.starts_with ~prefix:"[" text then
    let* values = parse_string_array path line text in
    Ok (Strings values)
  else
    match int_of_string_opt text with
    | Some number -> Ok (Int number)
    | None -> error path line "unsupported value syntax"

let add_binding path line key value bindings =
  if key = "" then error path line "expected a key before '='"
  else if List.exists (fun binding -> binding.key = key) bindings then
    error path line (Printf.sprintf "duplicate key '%s'" key)
  else Ok ({ key; value; line } :: bindings)

let parse_section_header path line text =
  if not (String_util.starts_with ~prefix:"[" text) then
    error path line "expected a section header"
  else if not (String_util.ends_with ~suffix:"]" text) then
    error path line "section header must end with ']'"
  else
    let inner = String.sub text 1 (String.length text - 2) |> String.trim in
    let components = String_util.split_dot inner in
    if components = [] then error path line "section path cannot be empty"
    else Ok { path = components; line; bindings = [] }

let find_binding key bindings =
  List.find_opt (fun binding -> binding.key = key) bindings

let required_string path section field =
  match find_binding field section.bindings with
  | None ->
      error path section.line
        (Printf.sprintf "section [%s] is missing required field '%s'"
           (String_util.join_dot section.path) field)
  | Some { value = String value; _ } -> Ok value
  | Some binding ->
      error path binding.line
        (Printf.sprintf "field '%s' must be a string" field)

let optional_strings path section field =
  match find_binding field section.bindings with
  | None -> Ok []
  | Some { value = Strings values; _ } -> Ok values
  | Some binding ->
      error path binding.line
        (Printf.sprintf "field '%s' must be an array of strings" field)

let required_strings path section field =
  match find_binding field section.bindings with
  | None ->
      error path section.line
        (Printf.sprintf "section [%s] is missing required field '%s'"
           (String_util.join_dot section.path) field)
  | Some { value = Strings values; _ } -> Ok values
  | Some binding ->
      error path binding.line
        (Printf.sprintf "field '%s' must be an array of strings" field)

let allowed_fields path section fields =
  match List.find_opt (fun binding -> not (List.mem binding.key fields)) section.bindings with
  | None -> Ok ()
  | Some binding ->
      error path binding.line
        (Printf.sprintf "unknown field '%s' in section [%s]" binding.key
           (String_util.join_dot section.path))

let validate_identifier_list ~allow_empty path line label items =
  if (not allow_empty) && items = [] then
    error path line (Printf.sprintf "%s cannot be empty" label)
  else
    let seen = Hashtbl.create (List.length items) in
    let rec loop = function
      | [] -> Ok ()
      | item :: rest ->
          if item = "" then
            error path line (Printf.sprintf "%s cannot contain an empty entry" label)
          else if String.contains item '/' then
            error path line
              (Printf.sprintf
                 "%s entries must be file stems relative to dir, not paths: '%s'"
                 label item)
          else if String.contains item '.' then
            error path line
              (Printf.sprintf "%s entries must omit file extensions: '%s'" label
                 item)
          else if Hashtbl.mem seen item then
            error path line
              (Printf.sprintf "duplicate %s entry '%s'" label item)
          else (
            Hashtbl.add seen item ();
            loop rest)
    in
    loop items

let validate_package_list path line packages =
  let seen = Hashtbl.create (List.length packages) in
  let rec loop = function
    | [] -> Ok ()
    | package_name :: rest ->
        if package_name = "" then
          error path line "packages cannot contain an empty entry"
        else if Hashtbl.mem seen package_name then
          error path line
            (Printf.sprintf "duplicate packages entry '%s'" package_name)
        else (
          Hashtbl.add seen package_name ();
          loop rest)
  in
  loop packages

let parse_library path section name =
  let* () = allowed_fields path section [ "dir"; "modules"; "deps"; "packages" ] in
  let* dir = required_string path section "dir" in
  let* modules = required_strings path section "modules" in
  let* deps = optional_strings path section "deps" in
  let* packages = optional_strings path section "packages" in
  let* () =
    validate_identifier_list ~allow_empty:false path section.line "modules"
      modules
  in
  let* () =
    validate_identifier_list ~allow_empty:true path section.line "deps" deps
  in
  let* () = validate_package_list path section.line packages in
  Ok (Library { name; dir; modules; deps; packages })

let parse_runnable path section name =
  let* () =
    allowed_fields path section [ "dir"; "main"; "modules"; "deps"; "packages" ]
  in
  let* dir = required_string path section "dir" in
  let* main = required_string path section "main" in
  let* modules = optional_strings path section "modules" in
  let* deps = optional_strings path section "deps" in
  let* packages = optional_strings path section "packages" in
  let* () =
    validate_identifier_list ~allow_empty:true path section.line "modules"
      modules
  in
  let* () =
    validate_identifier_list ~allow_empty:true path section.line "deps" deps
  in
  let* () = validate_package_list path section.line packages in
  if main = "" then error path section.line "main cannot be empty"
  else if String.contains main '/' || String.contains main '.' then
    error path section.line "main must be a file stem without path or extension"
  else if List.mem main modules then
    error path section.line "main should not be repeated in modules"
  else Ok { name; dir; main; modules; deps; packages }

let parse_executable path section name =
  let* executable = parse_runnable path section name in
  Ok (Executable executable)

let parse_test path section name =
  let* test = parse_runnable path section name in
  Ok (Test test)

let parse_target path section =
  match section.path with
  | [ "library"; name ] -> parse_library path section name
  | [ "executable"; name ] -> parse_executable path section name
  | [ "test"; name ] -> parse_test path section name
  | [ kind; _ ] ->
      error path section.line
        (Printf.sprintf
           "unknown target kind '%s'; expected library, executable, or test"
           kind)
  | _ ->
      error path section.line
        "target sections must look like [library.name], [executable.name], or \
         [test.name]"

let parse_top_level path bindings =
  let allowed = [ "workspace"; "version" ] in
  let* () =
    match List.find_opt (fun binding -> not (List.mem binding.key allowed)) bindings with
    | None -> Ok ()
    | Some binding ->
        error path binding.line
          (Printf.sprintf "unknown top-level key '%s'" binding.key)
  in
  let name =
    match find_binding "workspace" bindings with
    | None -> Ok None
    | Some { value = String value; _ } -> Ok (Some value)
    | Some binding -> error path binding.line "workspace must be a string"
  in
  let version =
    match find_binding "version" bindings with
    | None -> Ok 1
    | Some { value = Int value; _ } ->
        if value = 1 then Ok value
        else error path 1 (Printf.sprintf "unsupported manifest version %d" value)
    | Some binding -> error path binding.line "version must be an integer"
  in
  let* name = name in
  let* version = version in
  Ok (name, version)

let validate_unique_target_names path targets =
  let seen = Hashtbl.create (List.length targets) in
  let rec loop = function
    | [] -> Ok ()
    | target :: rest ->
        let name = target_name target in
        if Hashtbl.mem seen name then
          error path 1
            (Printf.sprintf "duplicate target name '%s' across workspace" name)
        else (
          Hashtbl.add seen name ();
          loop rest)
  in
  loop targets

let load path =
  let lines = Fs.read_lines path in
  let rec parse_lines line_number current_section top_level sections = function
    | [] ->
        let sections =
          match current_section with
          | None -> sections
          | Some section -> section :: sections
        in
        let sections = List.rev sections in
        let top_level = List.rev top_level in
        let* name, version = parse_top_level path top_level in
        let rec collect_targets acc = function
          | [] -> Ok (List.rev acc)
          | section :: rest ->
              let* target = parse_target path section in
              collect_targets (target :: acc) rest
        in
        let* targets = collect_targets [] sections in
        let* () = validate_unique_target_names path targets in
        Ok { name; version; targets }
    | raw_line :: rest ->
        let line = raw_line |> String_util.strip_comment |> String.trim in
        if line = "" then
          parse_lines (line_number + 1) current_section top_level sections rest
        else if String_util.starts_with ~prefix:"[" line then
          let* next_section = parse_section_header path line_number line in
          let sections =
            match current_section with
            | None -> sections
            | Some section -> section :: sections
          in
          parse_lines (line_number + 1) (Some next_section) top_level sections rest
        else
          match String_util.split_once ~on:'=' line with
          | None -> error path line_number "expected 'key = value'"
          | Some (raw_key, raw_value) ->
              let key = String.trim raw_key in
              let value_text = String.trim raw_value in
              let* value = parse_value path line_number value_text in
              (match current_section with
              | None ->
                  let* top_level = add_binding path line_number key value top_level in
                  parse_lines (line_number + 1) current_section top_level sections rest
              | Some section ->
                  let* bindings =
                    add_binding path line_number key value section.bindings
                  in
                  let updated_section = { section with bindings } in
                  parse_lines (line_number + 1) (Some updated_section) top_level
                    sections rest)
  in
  parse_lines 1 None [] [] lines
