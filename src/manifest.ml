type value =
  | String of string
  | Int of int
  | Bool of bool
  | Strings of string list

type env_binding = string * string

type sandbox =
  | Workspace
  | Target

type target_options = {
  actions : string list;
  preprocess : string list;
  ppx : string list;
  compile_flags : string list;
  link_flags : string list;
  env : env_binding list;
  sandbox : sandbox option;
}

type library = {
  name : string;
  public_name : string option;
  wrapped : bool;
  dir : string;
  package_path : string option;
  modules : string list;
  deps : string list;
  packages : string list;
  options : target_options;
}

type runnable = {
  name : string;
  public_name : string option;
  dir : string;
  package_path : string option;
  main : string;
  modules : string list;
  deps : string list;
  packages : string list;
  options : target_options;
}

type executable = runnable

type test_target = runnable

type command_tool = {
  name : string;
  package_path : string option;
  argv : string list;
  cwd : string option;
  env : env_binding list;
  deps : string list;
}

type ppx_tool = {
  name : string;
  package_path : string option;
  argv : string list;
  deps : string list;
}

type action = {
  name : string;
  package_path : string option;
  argv : string list;
  cwd : string option;
  deps : string list;
  outputs : string list;
  env : env_binding list;
  stdin : string option;
  sandbox : sandbox option;
}

type profile = {
  name : string;
  options : target_options;
  target_overrides : (string * target_options) list;
}

type workspace_defaults = {
  default_profile : string;
  options : target_options;
}

type target =
  | Library of library
  | Executable of executable
  | Test of test_target

type workspace = {
  name : string option;
  version : int;
  defaults : workspace_defaults;
  targets : target list;
  actions : action list;
  preprocessors : command_tool list;
  ppx_tools : ppx_tool list;
  profiles : profile list;
}

type loaded_manifest = {
  workspace : workspace;
  members : string list;
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

type profile_override = {
  profile_name : string;
  target_kind : string;
  target_name : string;
  options : target_options;
  line : int;
}

let default_filename = "oasis.toml"

let default_profile_name = "default"

let empty_target_options =
  {
    actions = [];
    preprocess = [];
    ppx = [];
    compile_flags = [];
    link_flags = [];
    env = [];
    sandbox = None;
  }

let ( let* ) = Result.bind

let error path line message =
  Error (Printf.sprintf "%s:%d: %s" path line message)

let target_name = function
  | Library library -> library.name
  | Executable executable -> executable.name
  | Test test -> test.name

let target_public_name = function
  | Library library -> library.public_name
  | Executable executable -> executable.public_name
  | Test test -> test.public_name

let install_name name = function
  | Some public_name when String.trim public_name <> "" -> public_name
  | Some _ | None -> name

let target_install_name = function
  | Library library -> install_name library.name library.public_name
  | Executable executable -> install_name executable.name executable.public_name
  | Test test -> install_name test.name test.public_name

let target_deps = function
  | Library library -> library.deps
  | Executable executable -> executable.deps
  | Test test -> test.deps

let target_package_path = function
  | Library library -> library.package_path
  | Executable executable -> executable.package_path
  | Test test -> test.package_path

let package_label = function
  | Some package_path -> package_path
  | None -> "root"

let package_suffix package_path =
  match package_path with
  | Some package_path -> " (" ^ package_path ^ ")"
  | None -> ""

let target_display_name target =
  target_name target ^ package_suffix (target_package_path target)

let action_display_name (action : action) =
  action.name ^ package_suffix action.package_path

let command_tool_display_name (tool : command_tool) =
  tool.name ^ package_suffix tool.package_path

let ppx_tool_display_name (tool : ppx_tool) =
  tool.name ^ package_suffix tool.package_path

let target_packages = function
  | Library library -> library.packages
  | Executable executable -> executable.packages
  | Test test -> test.packages

let target_kind_name = function
  | Library _ -> "library"
  | Executable _ -> "executable"
  | Test _ -> "test"

let target_dir = function
  | Library library -> library.dir
  | Executable executable -> executable.dir
  | Test test -> test.dir

let target_options = function
  | Library library -> library.options
  | Executable executable -> executable.options
  | Test test -> test.options

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
  else if text = "true" then Ok (Bool true)
  else if text = "false" then Ok (Bool false)
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

let optional_string path section field =
  match find_binding field section.bindings with
  | None -> Ok None
  | Some { value = String value; _ } -> Ok (Some value)
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

let optional_bool path section field =
  match find_binding field section.bindings with
  | None -> Ok None
  | Some { value = Bool value; _ } -> Ok (Some value)
  | Some binding ->
      error path binding.line
        (Printf.sprintf "field '%s' must be a boolean" field)

let allowed_fields path section fields =
  match
    List.find_opt (fun binding -> not (List.mem binding.key fields)) section.bindings
  with
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

let validate_named_list path line label items =
  let seen = Hashtbl.create (List.length items) in
  let rec loop = function
    | [] -> Ok ()
    | item :: rest ->
        if item = "" then
          error path line (Printf.sprintf "%s cannot contain an empty entry" label)
        else if String.contains item '/' then
          error path line
            (Printf.sprintf "%s entries must be simple names: '%s'" label item)
        else if String.contains item '.' then
          error path line
            (Printf.sprintf "%s entries must not contain dots: '%s'" label item)
        else if Hashtbl.mem seen item then
          error path line
            (Printf.sprintf "duplicate %s entry '%s'" label item)
        else (
          Hashtbl.add seen item ();
          loop rest)
  in
  loop items

let validate_string_list path line label items =
  let rec loop = function
    | [] -> Ok ()
    | item :: rest ->
        if item = "" then
          error path line (Printf.sprintf "%s cannot contain an empty entry" label)
        else loop rest
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

let validate_relative_path ~allow_dot path line label value =
  let segments = String.split_on_char '/' value in
  if value = "" then
    error path line (Printf.sprintf "%s cannot be empty" label)
  else if (not allow_dot) && value = "." then
    error path line (Printf.sprintf "%s cannot be '.'" label)
  else if not (Filename.is_relative value) then
    error path line
      (Printf.sprintf "%s must be relative to the workspace: '%s'" label value)
  else if List.exists (fun segment -> segment = "..") segments then
    error path line
      (Printf.sprintf "%s must not escape the workspace: '%s'" label value)
  else Ok ()

let validate_relative_paths path line label values =
  let rec loop = function
    | [] -> Ok ()
    | value :: rest ->
        let* () = validate_relative_path ~allow_dot:false path line label value in
        loop rest
  in
  loop values

let validate_member_paths path line members =
  let* () = validate_relative_paths path line "members" members in
  let seen = Hashtbl.create (List.length members) in
  let rec loop = function
    | [] -> Ok ()
    | member :: rest ->
        if Hashtbl.mem seen member then
          error path line (Printf.sprintf "duplicate members entry '%s'" member)
        else (
          Hashtbl.add seen member ();
          loop rest)
  in
  loop members

let parse_env_binding path line value =
  match String_util.split_once ~on:'=' value with
  | Some (raw_name, raw_value) ->
      let name = String.trim raw_name in
      if name = "" then
        error path line
          "environment entries must look like NAME=value with a non-empty name"
      else Ok (name, raw_value)
  | None ->
      error path line
        "environment entries must look like NAME=value with a non-empty name"

let validate_env_bindings path line bindings =
  let seen = Hashtbl.create (List.length bindings) in
  let rec loop = function
    | [] -> Ok ()
    | (name, _) :: rest ->
        if Hashtbl.mem seen name then
          error path line
            (Printf.sprintf "duplicate environment entry '%s'" name)
        else (
          Hashtbl.add seen name ();
          loop rest)
  in
  loop bindings

let optional_env_bindings path section field =
  let* values = optional_strings path section field in
  let rec loop acc = function
    | [] ->
        let bindings = List.rev acc in
        let* () = validate_env_bindings path section.line bindings in
        Ok bindings
    | value :: rest ->
        let* binding = parse_env_binding path section.line value in
        loop (binding :: acc) rest
  in
  loop [] values

let parse_sandbox path line value =
  match String.lowercase_ascii (String.trim value) with
  | "workspace" -> Ok Workspace
  | "target" -> Ok Target
  | _ ->
      error path line
        "sandbox must be one of: target, workspace"

let optional_sandbox path section field =
  match find_binding field section.bindings with
  | None -> Ok None
  | Some { value = String value; line; _ } ->
      let* sandbox = parse_sandbox path line value in
      Ok (Some sandbox)
  | Some binding ->
      error path binding.line
        (Printf.sprintf "field '%s' must be a string" field)

let parse_target_options path section =
  let* actions = optional_strings path section "actions" in
  let* preprocess = optional_strings path section "preprocess" in
  let* ppx = optional_strings path section "ppx" in
  let* compile_flags = optional_strings path section "compile_flags" in
  let* link_flags = optional_strings path section "link_flags" in
  let* env = optional_env_bindings path section "env" in
  let* sandbox = optional_sandbox path section "sandbox" in
  let* () = validate_named_list path section.line "actions" actions in
  let* () = validate_named_list path section.line "preprocess" preprocess in
  let* () = validate_named_list path section.line "ppx" ppx in
  let* () = validate_string_list path section.line "compile_flags" compile_flags in
  let* () = validate_string_list path section.line "link_flags" link_flags in
  Ok { actions; preprocess; ppx; compile_flags; link_flags; env; sandbox }

let parse_library path section name =
  let* () =
    allowed_fields path section
      [
        "public_name";
        "wrapped";
        "dir";
        "modules";
        "deps";
        "packages";
        "actions";
        "preprocess";
        "ppx";
        "compile_flags";
        "link_flags";
        "env";
        "sandbox";
      ]
  in
  let* public_name = optional_string path section "public_name" in
  let* wrapped =
    match optional_bool path section "wrapped" with
    | Ok (Some value) -> Ok value
    | Ok None -> Ok false
    | Error _ as error -> error
  in
  let* dir = required_string path section "dir" in
  let* modules = required_strings path section "modules" in
  let* deps = optional_strings path section "deps" in
  let* packages = optional_strings path section "packages" in
  let* options = parse_target_options path section in
  let* () =
    validate_identifier_list ~allow_empty:false path section.line "modules"
      modules
  in
  let* () = validate_identifier_list ~allow_empty:true path section.line "deps" deps in
  let* () = validate_package_list path section.line packages in
  Ok
    (Library
       {
         name;
         public_name;
         wrapped;
         dir;
         package_path = None;
         modules;
         deps;
         packages;
         options;
       })

let parse_runnable path section name =
  let* () =
    allowed_fields path section
      [
        "public_name";
        "dir";
        "main";
        "modules";
        "deps";
        "packages";
        "actions";
        "preprocess";
        "ppx";
        "compile_flags";
        "link_flags";
        "env";
        "sandbox";
      ]
  in
  let* public_name = optional_string path section "public_name" in
  let* dir = required_string path section "dir" in
  let* main = required_string path section "main" in
  let* modules = optional_strings path section "modules" in
  let* deps = optional_strings path section "deps" in
  let* packages = optional_strings path section "packages" in
  let* options = parse_target_options path section in
  let* () =
    validate_identifier_list ~allow_empty:true path section.line "modules"
      modules
  in
  let* () = validate_identifier_list ~allow_empty:true path section.line "deps" deps in
  let* () = validate_package_list path section.line packages in
  if main = "" then error path section.line "main cannot be empty"
  else if String.contains main '/' || String.contains main '.' then
    error path section.line "main must be a file stem without path or extension"
  else if List.mem main modules then
    error path section.line "main should not be repeated in modules"
  else
    Ok
      {
        name;
        public_name;
        dir;
        package_path = None;
        main;
        modules;
        deps;
        packages;
        options;
      }

let parse_executable path section name =
  let* executable = parse_runnable path section name in
  Ok (Executable executable)

let parse_test path section name =
  let* test = parse_runnable path section name in
  Ok (Test test)

let parse_action path section name =
  let* () =
    allowed_fields path section
      [ "argv"; "cwd"; "deps"; "outputs"; "env"; "stdin"; "sandbox" ]
  in
  let* argv = required_strings path section "argv" in
  let* cwd = optional_string path section "cwd" in
  let* deps = optional_strings path section "deps" in
  let* outputs = required_strings path section "outputs" in
  let* env = optional_env_bindings path section "env" in
  let* stdin = optional_string path section "stdin" in
  let* sandbox = optional_sandbox path section "sandbox" in
  let* () = validate_string_list path section.line "argv" argv in
  let* () = validate_relative_paths path section.line "deps" deps in
  let* () = validate_relative_paths path section.line "outputs" outputs in
  let* () =
    if outputs = [] then
      error path section.line "outputs cannot be empty"
    else Ok ()
  in
  let* () =
    match cwd with
    | None -> Ok ()
    | Some cwd -> validate_relative_path ~allow_dot:true path section.line "cwd" cwd
  in
  Ok
    {
      name;
      package_path = None;
      argv;
      cwd;
      deps;
      outputs;
      env;
      stdin;
      sandbox;
    }

let parse_command_tool label path section name =
  let* () = allowed_fields path section [ "argv"; "cwd"; "env"; "deps" ] in
  let* argv = required_strings path section "argv" in
  let* cwd = optional_string path section "cwd" in
  let* env = optional_env_bindings path section "env" in
  let* deps = optional_strings path section "deps" in
  let* () = validate_string_list path section.line "argv" argv in
  let* () = validate_relative_paths path section.line "deps" deps in
  let* () =
    if argv = [] then
      error path section.line (Printf.sprintf "%s argv cannot be empty" label)
    else Ok ()
  in
  let* () =
    match cwd with
    | None -> Ok ()
    | Some cwd -> validate_relative_path ~allow_dot:true path section.line "cwd" cwd
  in
  Ok { name; package_path = None; argv; cwd; env; deps }

let parse_ppx_tool path section name =
  let* () = allowed_fields path section [ "argv"; "deps" ] in
  let* argv = required_strings path section "argv" in
  let* deps = optional_strings path section "deps" in
  let* () = validate_string_list path section.line "argv" argv in
  let* () = validate_relative_paths path section.line "deps" deps in
  let* () =
    if argv = [] then error path section.line "ppx argv cannot be empty" else Ok ()
  in
  Ok { name; package_path = None; argv; deps }

let parse_defaults path section =
  let* () =
    allowed_fields path section
      [
        "profile";
        "actions";
        "preprocess";
        "ppx";
        "compile_flags";
        "link_flags";
        "env";
        "sandbox";
      ]
  in
  let* default_profile =
    match find_binding "profile" section.bindings with
    | None -> Ok default_profile_name
    | Some { value = String value; _ } when String.trim value <> "" -> Ok value
    | Some { value = String _; line; _ } ->
        error path line "profile cannot be empty"
    | Some binding -> error path binding.line "profile must be a string"
  in
  let* options = parse_target_options path section in
  Ok { default_profile; options }

let parse_profile path section name =
  let* () =
    allowed_fields path section
      [
        "actions";
        "preprocess";
        "ppx";
        "compile_flags";
        "link_flags";
        "env";
        "sandbox";
      ]
  in
  let* options = parse_target_options path section in
  Ok (name, options, section.line)

let parse_profile_override path section profile_name target_kind target_name =
  let* () =
    allowed_fields path section
      [
        "actions";
        "preprocess";
        "ppx";
        "compile_flags";
        "link_flags";
        "env";
        "sandbox";
      ]
  in
  let* options = parse_target_options path section in
  Ok { profile_name; target_kind; target_name; options; line = section.line }

let parse_top_level path bindings =
  let allowed = [ "workspace"; "version"; "members" ] in
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
  let members =
    match find_binding "members" bindings with
    | None -> Ok []
    | Some { value = Strings members; line; _ } ->
        let* () = validate_member_paths path line members in
        Ok members
    | Some binding -> error path binding.line "members must be an array of strings"
  in
  let* name = name in
  let* version = version in
  let* members = members in
  Ok (name, version, members)

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

let validate_unique_named path label items =
  let seen = Hashtbl.create (List.length items) in
  let rec loop = function
    | [] -> Ok ()
    | (name, line) :: rest ->
        if Hashtbl.mem seen name then
          error path line
            (Printf.sprintf "duplicate %s '%s'" label name)
        else (
          Hashtbl.add seen name ();
          loop rest)
  in
  loop items

let merge_env_bindings (base : env_binding list)
    (override_bindings : env_binding list) =
  let table = Hashtbl.create (List.length base + List.length override_bindings) in
  List.iter (fun (name, value) -> Hashtbl.replace table name value) base;
  List.iter (fun (name, value) -> Hashtbl.replace table name value) override_bindings;
  let ordered_names =
    List.map fst base @ List.map fst override_bindings |> String_util.dedup_preserve
  in
  List.filter_map
    (fun name ->
      match Hashtbl.find_opt table name with
      | Some value -> Some (name, value)
      | None -> None)
    ordered_names

let merge_target_options (base : target_options)
    (override_options : target_options) =
  {
    actions = String_util.dedup_preserve (base.actions @ override_options.actions);
    preprocess =
      String_util.dedup_preserve (base.preprocess @ override_options.preprocess);
    ppx = String_util.dedup_preserve (base.ppx @ override_options.ppx);
    compile_flags = base.compile_flags @ override_options.compile_flags;
    link_flags = base.link_flags @ override_options.link_flags;
    env = merge_env_bindings base.env override_options.env;
    sandbox =
      (match override_options.sandbox with
      | Some _ as sandbox -> sandbox
      | None -> base.sandbox);
  }

let build_profiles path targets profile_sections override_sections =
  let* () =
    validate_unique_named path "profile" (List.map (fun (name, _, line) -> (name, line)) profile_sections)
  in
  let target_index = Hashtbl.create (List.length targets) in
  List.iter
    (fun target ->
      Hashtbl.replace target_index (target_name target) (target_kind_name target))
    targets;
  let override_keys =
    List.map
      (fun override ->
        ((override.profile_name ^ ":" ^ override.target_name), override.line))
      override_sections
  in
  let* () = validate_unique_named path "profile target override" override_keys in
  let* () =
    let rec loop = function
      | [] -> Ok ()
      | override :: rest -> (
          match Hashtbl.find_opt target_index override.target_name with
          | None ->
              error path override.line
                (Printf.sprintf
                   "profile '%s' overrides unknown target '%s'"
                   override.profile_name override.target_name)
          | Some actual_kind ->
              if actual_kind <> override.target_kind then
                error path override.line
                  (Printf.sprintf
                     "profile '%s' override kind mismatch for target '%s': \
                      expected %s but manifest defines %s"
                     override.profile_name override.target_name
                     override.target_kind actual_kind)
              else loop rest)
    in
    loop override_sections
  in
  let profile_names =
    String_util.dedup_preserve
      (List.map (fun (name, _, _) -> name) profile_sections
      @ List.map (fun override -> override.profile_name) override_sections)
  in
  let profile_options name =
    match List.find_opt (fun (profile_name, _, _) -> profile_name = name) profile_sections with
    | Some (_, options, _) -> options
    | None -> empty_target_options
  in
  let overrides_for name =
    List.filter_map
      (fun override ->
        if override.profile_name = name then
          Some (override.target_name, override.options)
        else None)
      override_sections
  in
  Ok
    (List.map
       (fun name ->
         {
           name;
           options = profile_options name;
           target_overrides = overrides_for name;
         })
       profile_names)

let default_defaults =
  { default_profile = default_profile_name; options = empty_target_options }

let default_profile (workspace : workspace) = workspace.defaults.default_profile

let find_profile (workspace : workspace) (name : string) =
  List.find_opt (fun (profile : profile) -> profile.name = name)
    workspace.profiles

let resolve_target_options (workspace : workspace) profile_name target =
  let base = merge_target_options workspace.defaults.options (target_options target) in
  match find_profile workspace profile_name with
  | None -> Ok base
  | Some profile ->
      let with_profile = merge_target_options base profile.options in
      let override_options =
        match
          List.find_opt
            (fun (name, _) -> name = target_name target)
            profile.target_overrides
        with
        | Some (_, options) -> options
        | None -> empty_target_options
      in
      Ok (merge_target_options with_profile override_options)

let find_scoped tool_name package_path items get_name get_package_path =
  let exact_match item =
    get_name item = tool_name && get_package_path item = package_path
  in
  let root_match item = get_name item = tool_name && get_package_path item = None in
  match package_path with
  | Some _ -> (
      match List.find_opt exact_match items with
      | Some _ as item -> item
      | None -> List.find_opt root_match items)
  | None -> List.find_opt root_match items

let find_action (workspace : workspace) ?package_path (name : string) =
  find_scoped name package_path workspace.actions
    (fun (action : action) -> action.name)
    (fun (action : action) -> action.package_path)

let find_preprocessor (workspace : workspace) ?package_path (name : string) =
  find_scoped name package_path workspace.preprocessors
    (fun (tool : command_tool) -> tool.name)
    (fun (tool : command_tool) -> tool.package_path)

let find_ppx_tool (workspace : workspace) ?package_path (name : string) =
  find_scoped name package_path workspace.ppx_tools
    (fun (tool : ppx_tool) -> tool.name)
    (fun (tool : ppx_tool) -> tool.package_path)

let rebase_target_dir member_path dir =
  if dir = "." then member_path else Filename.concat member_path dir

let normalize_relative_path value =
  let rec strip value =
    if String_util.starts_with ~prefix:"./" value then
      let next = String.sub value 2 (String.length value - 2) in
      strip next
    else value
  in
  strip value

let rebase_relative_path ~allow_dot member_path value =
  let value = normalize_relative_path value in
  if allow_dot && value = "." then member_path else Filename.concat member_path value

let rebase_command_argv member_path = function
  | [] -> []
  | prog :: args as argv ->
      if Filename.is_relative prog && String.contains prog '/' then
        rebase_relative_path ~allow_dot:false member_path prog :: args
      else argv

let rebase_target member_path = function
  | Library library ->
      Library
        {
          library with
          dir = rebase_target_dir member_path library.dir;
          package_path = Some member_path;
        }
  | Executable executable ->
      Executable
        {
          executable with
          dir = rebase_target_dir member_path executable.dir;
          package_path = Some member_path;
        }
  | Test test ->
      Test
        {
          test with
          dir = rebase_target_dir member_path test.dir;
          package_path = Some member_path;
        }

let rebase_action member_path (action : action) =
  {
    action with
    package_path = Some member_path;
    argv = rebase_command_argv member_path action.argv;
    cwd =
      Option.map (rebase_relative_path ~allow_dot:true member_path) action.cwd;
    deps = List.map (rebase_relative_path ~allow_dot:false member_path) action.deps;
  }

let rebase_preprocessor member_path (tool : command_tool) =
  {
    tool with
    package_path = Some member_path;
    argv = rebase_command_argv member_path tool.argv;
    cwd = Option.map (rebase_relative_path ~allow_dot:true member_path) tool.cwd;
    deps = List.map (rebase_relative_path ~allow_dot:false member_path) tool.deps;
  }

let rebase_ppx_tool member_path (tool : ppx_tool) =
  {
    tool with
    package_path = Some member_path;
    argv = rebase_command_argv member_path tool.argv;
    deps = List.map (rebase_relative_path ~allow_dot:false member_path) tool.deps;
  }

let member_error member_manifest_path message =
  Error (Printf.sprintf "%s: %s" member_manifest_path message)

let member_workspace_feature_error member_manifest_path feature =
  member_error member_manifest_path
    (Printf.sprintf "member manifests may not define %s; keep workspace-wide \
                     configuration in the root manifest"
       feature)

let load_local path =
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
        let* name, version, members = parse_top_level path top_level in
        let rec collect_sections defaults_opt targets actions preprocessors ppx_tools
            profiles overrides = function
          | [] ->
              let* () = validate_unique_target_names path (List.rev targets) in
              let* () =
                validate_unique_named path "action"
                  (List.map (fun (action : action) -> (action.name, 1)) actions)
              in
              let* () =
                validate_unique_named path "preprocess tool"
                  (List.map
                     (fun (tool : command_tool) -> (tool.name, 1))
                     preprocessors)
              in
              let* () =
                validate_unique_named path "ppx tool"
                  (List.map (fun (tool : ppx_tool) -> (tool.name, 1)) ppx_tools)
              in
              let targets = List.rev targets in
              let* profiles =
                build_profiles path targets (List.rev profiles) (List.rev overrides)
              in
              Ok
                {
                  workspace =
                    {
                      name;
                      version;
                      defaults =
                        (match defaults_opt with
                        | Some defaults -> defaults
                        | None -> default_defaults);
                      targets;
                      actions = List.rev actions;
                      preprocessors = List.rev preprocessors;
                      ppx_tools = List.rev ppx_tools;
                      profiles;
                    };
                  members;
                }
          | section :: rest -> (
              match section.path with
              | [ "defaults" ] ->
                  let* defaults = parse_defaults path section in
                  let* () =
                    match defaults_opt with
                    | None -> Ok ()
                    | Some _ -> error path section.line "duplicate [defaults] section"
                  in
                  collect_sections (Some defaults) targets actions preprocessors
                    ppx_tools profiles overrides rest
              | [ "library"; target_name ] ->
                  let* target = parse_library path section target_name in
                  collect_sections defaults_opt (target :: targets) actions
                    preprocessors ppx_tools profiles overrides rest
              | [ "executable"; target_name ] ->
                  let* target = parse_executable path section target_name in
                  collect_sections defaults_opt (target :: targets) actions
                    preprocessors ppx_tools profiles overrides rest
              | [ "test"; target_name ] ->
                  let* target = parse_test path section target_name in
                  collect_sections defaults_opt (target :: targets) actions
                    preprocessors ppx_tools profiles overrides rest
              | [ "action"; action_name ] ->
                  let* action = parse_action path section action_name in
                  collect_sections defaults_opt targets (action :: actions)
                    preprocessors ppx_tools profiles overrides rest
              | [ "preprocess"; tool_name ] ->
                  let* tool =
                    parse_command_tool "preprocess" path section tool_name
                  in
                  collect_sections defaults_opt targets actions
                    (tool :: preprocessors) ppx_tools profiles overrides rest
              | [ "ppx"; tool_name ] ->
                  let* tool = parse_ppx_tool path section tool_name in
                  collect_sections defaults_opt targets actions preprocessors
                    (tool :: ppx_tools) profiles overrides rest
              | [ "profile"; profile_name ] ->
                  let* profile = parse_profile path section profile_name in
                  collect_sections defaults_opt targets actions preprocessors
                    ppx_tools (profile :: profiles) overrides rest
              | [ "profile"; profile_name; target_kind; target_name ] ->
                  let* override =
                    parse_profile_override path section profile_name target_kind
                      target_name
                  in
                  collect_sections defaults_opt targets actions preprocessors
                    ppx_tools profiles (override :: overrides) rest
              | [ kind; _ ] ->
                  error path section.line
                    (Printf.sprintf
                       "unknown section kind '%s'; expected defaults, action, \
                        preprocess, ppx, profile, library, executable, or test"
                       kind)
              | _ ->
                  error path section.line
                    "section path is not supported by this manifest version")
        in
        collect_sections None [] [] [] [] [] [] sections
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

let rec load path =
  let* loaded = load_local path in
  if loaded.members = [] then Ok loaded.workspace
  else
    let root_workspace = loaded.workspace in
    let root_dir = Filename.dirname path in
    let rec load_members merged_targets merged_actions merged_preprocessors
        merged_ppx_tools = function
      | [] ->
          let merged_workspace =
            {
              root_workspace with
              targets = List.rev merged_targets;
              actions = List.rev merged_actions;
              preprocessors = List.rev merged_preprocessors;
              ppx_tools = List.rev merged_ppx_tools;
            }
          in
          let* () = validate_unique_target_names path merged_workspace.targets in
          Ok merged_workspace
      | member_path :: rest ->
          let member_dir = Filename.concat root_dir member_path in
          let member_manifest_path =
            Filename.concat member_dir default_filename
          in
          let* () =
            if not (Fs.is_directory member_dir) then
              member_error member_manifest_path
                (Printf.sprintf "member directory does not exist: %s" member_dir)
            else if not (Fs.exists member_manifest_path) then
              member_error member_manifest_path
                "member manifest not found"
            else Ok ()
          in
          let* member_workspace = load member_manifest_path in
          let* () =
            match member_workspace.name with
            | None -> Ok ()
            | Some _ ->
                member_workspace_feature_error member_manifest_path
                  "a top-level workspace name"
          in
          let* () =
            if member_workspace.defaults <> default_defaults then
              member_workspace_feature_error member_manifest_path
                "defaults sections"
            else Ok ()
          in
          let* () =
            if member_workspace.profiles <> [] then
              member_workspace_feature_error member_manifest_path "profile sections"
            else Ok ()
          in
          let rebased_targets =
            List.map (rebase_target member_path) member_workspace.targets
          in
          let rebased_actions =
            List.map (rebase_action member_path) member_workspace.actions
          in
          let rebased_preprocessors =
            List.map (rebase_preprocessor member_path) member_workspace.preprocessors
          in
          let rebased_ppx_tools =
            List.map (rebase_ppx_tool member_path) member_workspace.ppx_tools
          in
          load_members
            (List.rev_append rebased_targets merged_targets)
            (List.rev_append rebased_actions merged_actions)
            (List.rev_append rebased_preprocessors merged_preprocessors)
            (List.rev_append rebased_ppx_tools merged_ppx_tools)
            rest
    in
    load_members (List.rev root_workspace.targets) (List.rev root_workspace.actions)
      (List.rev root_workspace.preprocessors) (List.rev root_workspace.ppx_tools)
      loaded.members
