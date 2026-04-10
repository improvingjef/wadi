let starts_with ~prefix text =
  let prefix_length = String.length prefix in
  String.length text >= prefix_length
  && String.sub text 0 prefix_length = prefix

let ends_with ~suffix text =
  let suffix_length = String.length suffix in
  let text_length = String.length text in
  text_length >= suffix_length
  && String.sub text (text_length - suffix_length) suffix_length = suffix

let split_once ~on text =
  let rec loop index =
    if index >= String.length text then None
    else if text.[index] = on then
      Some
        (String.sub text 0 index, String.sub text (index + 1)
           (String.length text - index - 1))
    else loop (index + 1)
  in
  loop 0

let strip_comment line =
  match String.index_opt line '#' with
  | Some index -> String.sub line 0 index
  | None -> line

let split_whitespace text =
  let is_whitespace = function
    | ' ' | '\t' | '\n' | '\r' -> true
    | _ -> false
  in
  let rec skip index =
    if index < String.length text && is_whitespace text.[index] then
      skip (index + 1)
    else index
  in
  let rec take start index =
    if index < String.length text && not (is_whitespace text.[index]) then
      take start (index + 1)
    else (String.sub text start (index - start), index)
  in
  let rec loop index acc =
    let index = skip index in
    if index >= String.length text then List.rev acc
    else
      let item, next_index = take index index in
      loop next_index (item :: acc)
  in
  loop 0 []

let dedup_preserve items =
  let seen = Hashtbl.create (List.length items) in
  let rec loop acc = function
    | [] -> List.rev acc
    | item :: rest ->
        if Hashtbl.mem seen item then loop acc rest
        else (
          Hashtbl.add seen item ();
          loop (item :: acc) rest)
  in
  loop [] items

let read_file path =
  let channel = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr channel)
    (fun () ->
      let buffer = Buffer.create 1024 in
      (try
         while true do
           Buffer.add_string buffer (input_line channel);
           Buffer.add_char buffer '\n'
         done
       with
      | End_of_file -> ());
      Buffer.contents buffer)

let write_file path contents =
  let channel = open_out_bin path in
  Fun.protect
    ~finally:(fun () -> close_out_noerr channel)
    (fun () -> output_string channel contents)

let absolute_path path =
  if Filename.is_relative path then Filename.concat (Sys.getcwd ()) path else path

let normalize_dir_path path =
  if path = "" || path = "." then "."
  else if ends_with ~suffix:"/" path then path
  else path ^ "/"

let relative_to_root ~root_dir path =
  let root_dir = absolute_path root_dir in
  let normalized_root = normalize_dir_path root_dir in
  if path = root_dir then "."
  else if starts_with ~prefix:normalized_root path then
    String.sub path (String.length normalized_root)
      (String.length path - String.length normalized_root)
  else path

let ensure_dir path =
  let rec loop path =
    if path = "" || path = "." then ()
    else if Sys.file_exists path then (
      if not (Sys.is_directory path) then
        failwith (Printf.sprintf "expected %s to be a directory" path))
    else
      let parent = Filename.dirname path in
      if parent <> path then loop parent;
      if not (Sys.file_exists path) then Sys.mkdir path 0o755
  in
  loop path

let rec remove_tree path =
  if Sys.file_exists path then
    if Sys.is_directory path then (
      Sys.readdir path
      |> Array.iter (fun entry -> remove_tree (Filename.concat path entry));
      Sys.rmdir path)
    else Sys.remove path

let manifest_path_default () =
  match Sys.getenv_opt "BOOTSTRAP_MODULE_MANIFEST" with
  | Some path when String.trim path <> "" -> absolute_path path
  | Some _ | None -> absolute_path "oasis.toml"

let parse_string_value text =
  let trimmed = String.trim text in
  let length = String.length trimmed in
  if length >= 2 && trimmed.[0] = '"' && trimmed.[length - 1] = '"' then
    String.sub trimmed 1 (length - 2)
  else failwith ("expected a quoted string, got " ^ trimmed)

let parse_bool_value text =
  match String.lowercase_ascii (String.trim text) with
  | "true" -> true
  | "false" -> false
  | value -> failwith ("expected true or false, got " ^ value)

let parse_string_array text =
  let trimmed = String.trim text in
  let length = String.length trimmed in
  if length < 2 || trimmed.[0] <> '[' || trimmed.[length - 1] <> ']' then
    failwith ("expected a string array, got " ^ trimmed)
  else
    let rec skip index =
      if index < length - 1 then
        match trimmed.[index] with
        | ' ' | '\t' | '\n' | '\r' | ',' -> skip (index + 1)
        | _ -> index
      else index
    in
    let rec parse_string index =
      if index >= length - 1 || trimmed.[index] <> '"' then
        failwith ("expected a quoted string in " ^ trimmed)
      else
        let buffer = Buffer.create 32 in
        let rec loop cursor =
          if cursor >= length - 1 then failwith ("unterminated string in " ^ trimmed)
          else
            match trimmed.[cursor] with
            | '"' -> (Buffer.contents buffer, cursor + 1)
            | '\\' ->
                if cursor + 1 >= length - 1 then
                  failwith ("dangling escape in " ^ trimmed)
                else (
                  Buffer.add_char buffer trimmed.[cursor + 1];
                  loop (cursor + 2))
            | ch ->
                Buffer.add_char buffer ch;
                loop (cursor + 1)
        in
        loop (index + 1)
    in
    let rec loop index acc =
      let index = skip index in
      if index >= length - 1 then List.rev acc
      else
        let item, next_index = parse_string index in
        loop next_index (item :: acc)
    in
    loop 1 []

type target_options = {
  mutable compile_flags : string list option;
  mutable env : string list option;
}

let empty_target_options () = { compile_flags = None; env = None }

type library_section = {
  name : string;
  mutable dir : string option;
  mutable modules : string list option;
  mutable packages : string list option;
  mutable deps : string list option;
  mutable wrapped : bool option;
  mutable compile_flags : string list option;
  mutable env : string list option;
  mutable actions : string list option;
  mutable preprocess : string list option;
  mutable ppx : string list option;
}

let empty_library name =
  {
    name;
    dir = None;
    modules = None;
    packages = None;
    deps = None;
    wrapped = None;
    compile_flags = None;
    env = None;
    actions = None;
    preprocess = None;
    ppx = None;
  }

type manifest_state = {
  defaults : target_options;
  mutable default_profile : string option;
  profiles : (string, target_options) Hashtbl.t;
  profile_library_overrides : (string, target_options) Hashtbl.t;
  libraries : (string, library_section) Hashtbl.t;
  mutable library_order : string list;
}

let empty_manifest_state () =
  {
    defaults = empty_target_options ();
    default_profile = None;
    profiles = Hashtbl.create 8;
    profile_library_overrides = Hashtbl.create 8;
    libraries = Hashtbl.create 8;
    library_order = [];
  }

let profile_library_key profile library = profile ^ "\x1f" ^ library

let ensure_library state name =
  match Hashtbl.find_opt state.libraries name with
  | Some library -> library
  | None ->
      let library = empty_library name in
      Hashtbl.add state.libraries name library;
      state.library_order <- state.library_order @ [ name ];
      library

let ensure_profile_options table key =
  match Hashtbl.find_opt table key with
  | Some options -> options
  | None ->
      let options = empty_target_options () in
      Hashtbl.add table key options;
      options

let parse_env_binding binding =
  match split_once ~on:'=' binding with
  | Some (name, value) when String.trim name <> "" -> (name, value)
  | _ -> failwith ("expected NAME=VALUE env binding, got " ^ binding)

let merge_env_bindings base override_bindings =
  let table = Hashtbl.create (List.length base + List.length override_bindings) in
  List.iter (fun (name, value) -> Hashtbl.replace table name value) base;
  List.iter (fun (name, value) -> Hashtbl.replace table name value) override_bindings;
  let ordered_names =
    List.map fst base @ List.map fst override_bindings |> dedup_preserve
  in
  List.filter_map
    (fun name ->
      match Hashtbl.find_opt table name with
      | Some value -> Some (name, value)
      | None -> None)
    ordered_names

let set_target_option (options : target_options) key value =
  match key with
  | "compile_flags" -> options.compile_flags <- Some (parse_string_array value)
  | "env" -> options.env <- Some (parse_string_array value)
  | _ -> ()

let set_library_field (library : library_section) key value =
  match key with
  | "dir" -> library.dir <- Some (parse_string_value value)
  | "modules" -> library.modules <- Some (parse_string_array value)
  | "packages" -> library.packages <- Some (parse_string_array value)
  | "deps" -> library.deps <- Some (parse_string_array value)
  | "wrapped" -> library.wrapped <- Some (parse_bool_value value)
  | "compile_flags" -> library.compile_flags <- Some (parse_string_array value)
  | "env" -> library.env <- Some (parse_string_array value)
  | "actions" -> library.actions <- Some (parse_string_array value)
  | "preprocess" -> library.preprocess <- Some (parse_string_array value)
  | "ppx" -> library.ppx <- Some (parse_string_array value)
  | _ -> ()

let parse_section_header line =
  let trimmed = String.trim line in
  let length = String.length trimmed in
  if length >= 2 && trimmed.[0] = '[' && trimmed.[length - 1] = ']' then
    Some
      (String.sub trimmed 1 (length - 2)
      |> String.split_on_char '.'
      |> List.map String.trim
      |> List.filter (fun part -> part <> ""))
  else None

let handle_assignment state section key value =
  match section with
  | [ "defaults" ] ->
      if key = "profile" then state.default_profile <- Some (parse_string_value value)
      else set_target_option state.defaults key value
  | [ "profile"; profile ] ->
      let options = ensure_profile_options state.profiles profile in
      set_target_option options key value
  | [ "profile"; profile; "library"; library_name ] ->
      let options =
        ensure_profile_options state.profile_library_overrides
          (profile_library_key profile library_name)
      in
      set_target_option options key value
  | [ "library"; library_name ] ->
      let library = ensure_library state library_name in
      set_library_field library key value
  | _ -> ()

let parse_manifest path =
  let lines = read_file path |> String.split_on_char '\n' in
  let state = empty_manifest_state () in
  let rec loop current_section pending_key pending_buffer = function
    | [] ->
        Option.iter
          (fun key ->
            match current_section, pending_buffer with
            | Some section, Some buffer -> handle_assignment state section key buffer
            | _ -> ())
          pending_key;
        state
    | raw_line :: rest ->
        let line = raw_line |> strip_comment |> String.trim in
        if pending_key <> None then
          let buffer =
            match pending_buffer with
            | Some buffer when buffer = "" -> line
            | Some buffer -> buffer ^ "\n" ^ line
            | None -> line
          in
          if String.contains line ']' then (
            match current_section, pending_key with
            | Some section, Some key ->
                handle_assignment state section key buffer;
                loop current_section None None rest
            | _ -> loop current_section None None rest)
          else loop current_section pending_key (Some buffer) rest
        else if line = "" then loop current_section None None rest
        else
          match parse_section_header line with
          | Some section -> loop (Some section) None None rest
          | None -> (
              match current_section, split_once ~on:'=' line with
              | Some section, Some (raw_key, raw_value) ->
                  let key = String.trim raw_key in
                  let value = String.trim raw_value in
                  if value <> "" && value.[0] = '[' && not (String.contains value ']') then
                    loop current_section (Some key) (Some value) rest
                  else (
                    handle_assignment state section key value;
                    loop current_section None None rest)
              | _ -> loop current_section None None rest)
  in
  loop None None None lines

let choose_library manifest_path state =
  let libraries =
    List.filter_map
      (fun name -> Hashtbl.find_opt state.libraries name)
      state.library_order
  in
  let requested_name =
    match Sys.getenv_opt "BOOTSTRAP_LIBRARY" with
    | Some name when String.trim name <> "" -> Some (String.trim name)
    | Some _ | None -> None
  in
  match requested_name with
  | Some name -> (
      match List.find_opt (fun library -> library.name = name) libraries with
      | Some library -> library
      | None ->
          failwith
            (Printf.sprintf "bootstrap library '%s' was not found in %s" name
               manifest_path))
  | None -> (
      match List.find_opt (fun library -> library.name = "oasis_core") libraries with
      | Some library -> library
      | None -> (
          match libraries with
          | [ library ] -> library
          | [] ->
              failwith
                (Printf.sprintf "no [library.*] section found in %s" manifest_path)
          | libraries ->
              failwith
                (Printf.sprintf
                   "multiple libraries found in %s; set BOOTSTRAP_LIBRARY to \
                    choose one (%s)"
                   manifest_path
                   (String.concat ", "
                      (List.map (fun library -> library.name) libraries)))))

let option_list = function
  | Some items -> items
  | None -> []

let library_files manifest_path root_dir library =
  let dir =
    match library.dir with
    | Some dir -> dir
    | None ->
        failwith
          (Printf.sprintf "library '%s' is missing a dir setting in %s"
             library.name manifest_path)
  in
  let modules =
    match library.modules with
    | Some modules -> modules
    | None ->
        failwith
          (Printf.sprintf "library '%s' is missing a modules setting in %s"
             library.name manifest_path)
  in
  List.concat_map
    (fun module_name ->
      let base = Filename.concat (Filename.concat root_dir dir) module_name in
      let mli_path = base ^ ".mli" in
      let ml_path = base ^ ".ml" in
      let files =
        (if Sys.file_exists mli_path then [ mli_path ] else [])
        @ (if Sys.file_exists ml_path then [ ml_path ] else [])
      in
      if files = [] then
        failwith
          (Printf.sprintf
             "library '%s' declares module '%s' but no source file exists under %s"
             library.name module_name dir)
      else files)
    modules

let ordered_module_files ?(keep_interfaces = false) files =
  let dep_output_path = Filename.temp_file "oasis-bootstrap-modules" ".txt" in
  let ocamldep =
    match Sys.getenv_opt "OCAMLDEP" with
    | Some path when String.trim path <> "" -> path
    | Some _ | None -> "ocamldep"
  in
  let command =
    String.concat " "
      (List.map Filename.quote (ocamldep :: "-sort" :: files))
      ^ " > "
      ^ Filename.quote dep_output_path
      ^ " 2>&1"
  in
  let status = Sys.command command in
  let output = read_file dep_output_path in
  Sys.remove dep_output_path;
  if status <> 0 then
    failwith
      (Printf.sprintf "ocamldep -sort failed while ordering bootstrap modules:\n%s"
         output)
  else
    output |> split_whitespace
    |> List.filter (fun path ->
           if keep_interfaces then
             Filename.check_suffix path ".ml" || Filename.check_suffix path ".mli"
           else Filename.check_suffix path ".ml")
    |> dedup_preserve

let module_stems files =
  files
  |> List.map (fun path -> Filename.basename path |> Filename.remove_extension)
  |> dedup_preserve

let render_make_variable name values =
  name ^ " := " ^ String.concat " " values

let shell_quote = Filename.quote

let render_env_words env =
  env
  |> List.map (fun (name, value) -> name ^ "=" ^ shell_quote value)
  |> String.concat " "

let effective_library_options (state : manifest_state) (library : library_section) =
  let default_profile =
    match state.default_profile with
    | Some profile -> profile
    | None -> "default"
  in
  let profile_options =
    match Hashtbl.find_opt state.profiles default_profile with
    | Some options -> options
    | None -> empty_target_options ()
  in
  let profile_library_options =
    match
      Hashtbl.find_opt state.profile_library_overrides
        (profile_library_key default_profile library.name)
    with
    | Some options -> options
    | None -> empty_target_options ()
  in
  let compile_flags =
    option_list state.defaults.compile_flags @ option_list library.compile_flags
    @ option_list profile_options.compile_flags
    @ option_list profile_library_options.compile_flags
  in
  let env =
    let defaults_env = option_list state.defaults.env |> List.map parse_env_binding in
    let library_env = option_list library.env |> List.map parse_env_binding in
    let profile_env =
      option_list profile_options.env |> List.map parse_env_binding
    in
    let profile_library_env =
      option_list profile_library_options.env |> List.map parse_env_binding
    in
    merge_env_bindings defaults_env library_env
    |> fun env -> merge_env_bindings env profile_env
    |> fun env -> merge_env_bindings env profile_library_env
  in
  (default_profile, compile_flags, env)

let require_metadata_only_support manifest_path library =
  let unsupported label values =
    if values <> [] then
      failwith
        (Printf.sprintf
           "bootstrap metadata helper cannot model library '%s' in %s because \
            it uses %s; falling back to the full planner"
           library.name manifest_path label)
  in
  if library.wrapped = Some true then
    failwith
      (Printf.sprintf
         "bootstrap metadata helper cannot model wrapped library '%s' in %s; \
          falling back to the full planner"
         library.name manifest_path);
  unsupported "workspace library deps" (option_list library.deps);
  unsupported "actions" (option_list library.actions);
  unsupported "preprocessors" (option_list library.preprocess);
  unsupported "ppx rewriters" (option_list library.ppx)

let seed_snapshot_dir ~seed_root ~profile library =
  Filename.concat seed_root
    (Filename.concat profile (Printf.sprintf "library-%s" library.name))

let resolve_seed_root ~root_dir path =
  if Filename.is_relative path then Filename.concat root_dir path else path

let snapshot_or_relative ~root_dir ~snapshot_dir source_path =
  let relative_path = relative_to_root ~root_dir source_path in
  if relative_path <> source_path
     && not (starts_with ~prefix:"_bootstrap/" relative_path)
  then relative_path
  else
    let destination =
      Filename.concat snapshot_dir (Filename.basename source_path)
    in
    let contents = read_file source_path in
    if Sys.file_exists destination && read_file destination = contents then ()
    else write_file destination contents;
    relative_to_root ~root_dir destination

let seed_compile_paths ~root_dir ?seed_root ~profile library ordered_files =
  match seed_root with
  | None -> List.map (relative_to_root ~root_dir) ordered_files
  | Some seed_root ->
      let seed_root = resolve_seed_root ~root_dir seed_root in
      let snapshot_dir = seed_snapshot_dir ~seed_root ~profile library in
      if Sys.file_exists snapshot_dir then remove_tree snapshot_dir;
      ensure_dir snapshot_dir;
      List.map (snapshot_or_relative ~root_dir ~snapshot_dir) ordered_files

type output_format =
  | Mod_use
  | Ml_paths
  | Compile_paths
  | Packages
  | Seed_metadata

type command_options = {
  manifest_path : string;
  format : output_format;
  seed_root : string option;
}

let parse_output_format value =
  match String.lowercase_ascii (String.trim value) with
  | "mod_use" | "mod-use" -> Mod_use
  | "ml_paths" | "ml-paths" -> Ml_paths
  | "compile_paths" | "compile-paths" -> Compile_paths
  | "packages" -> Packages
  | "seed_metadata" | "seed-metadata" -> Seed_metadata
  | value ->
      failwith
        ("unknown --format value '" ^ value
       ^ "'; expected mod_use, ml-paths, compile-paths, packages, or \
          seed-metadata")

let parse_args () =
  let rec loop options index =
    if index >= Array.length Sys.argv then options
    else
      match Sys.argv.(index) with
      | "--manifest" ->
          if index + 1 >= Array.length Sys.argv then
            failwith "--manifest requires a path"
          else
            loop
              { options with manifest_path = absolute_path Sys.argv.(index + 1) }
              (index + 2)
      | "--format" ->
          if index + 1 >= Array.length Sys.argv then
            failwith
              "--format requires mod_use, ml-paths, compile-paths, packages, or \
               seed-metadata"
          else
            loop
              { options with format = parse_output_format Sys.argv.(index + 1) }
              (index + 2)
      | "--seed-root" ->
          if index + 1 >= Array.length Sys.argv then
            failwith "--seed-root requires a path"
          else
            loop
              { options with seed_root = Some Sys.argv.(index + 1) }
              (index + 2)
      | "--help" ->
          failwith
            "usage: ocaml scripts/render_bootstrap_mod_use.ml [--manifest PATH] [--format mod_use|ml-paths|compile-paths|packages|seed-metadata] [--seed-root DIR]"
      | option when starts_with ~prefix:"-" option ->
          failwith ("unknown option '" ^ option ^ "'")
      | _ -> failwith "render_bootstrap_mod_use.ml does not accept positional arguments"
  in
  loop
    { manifest_path = manifest_path_default (); format = Mod_use; seed_root = None }
    1

let () =
  try
    let options = parse_args () in
    let manifest_path = options.manifest_path in
    let root_dir = Filename.dirname manifest_path in
    let state = parse_manifest manifest_path in
    let library = choose_library manifest_path state in
    match options.format with
    | Mod_use ->
        let module_files =
          library_files manifest_path root_dir library |> ordered_module_files
        in
        List.iter
          (fun path -> Printf.printf "#mod_use %S;;\n" path)
          module_files
    | Ml_paths ->
        let module_files =
          library_files manifest_path root_dir library |> ordered_module_files
        in
        List.iter print_endline module_files
    | Compile_paths ->
        let module_files =
          library_files manifest_path root_dir library
          |> ordered_module_files ~keep_interfaces:true
        in
        List.iter print_endline module_files
    | Packages ->
        List.iter print_endline (option_list library.packages)
    | Seed_metadata ->
        require_metadata_only_support manifest_path library;
        let ordered_files =
          library_files manifest_path root_dir library
          |> ordered_module_files ~keep_interfaces:true
        in
        let profile, compile_flags, env = effective_library_options state library in
        let compile_paths =
          seed_compile_paths ~root_dir ?seed_root:options.seed_root ~profile
            library ordered_files
        in
        let lines =
          [
            "# Generated by oasis __bootstrap_makefile --format seed-metadata.";
            "# Edit oasis.toml instead of this file.";
            "# Refresh with: make refresh-bootstrap-seed-metadata";
            "BOOTSTRAP_LIBRARY_PROFILE := " ^ profile;
            render_make_variable "BOOTSTRAP_LIBRARY_COMPILE_SOURCES" compile_paths;
            render_make_variable "BOOTSTRAP_LIBRARY_MODULE_STEMS"
              (module_stems ordered_files);
            render_make_variable "BOOTSTRAP_LIBRARY_PACKAGES"
              (option_list library.packages);
            "BOOTSTRAP_LIBRARY_ENV_PREFIX := " ^ render_env_words env;
            "BOOTSTRAP_LIBRARY_COMPILE_FLAGS := "
            ^ String.concat " " compile_flags;
          ]
        in
        List.iter print_endline lines
  with
  | Failure message ->
      prerr_endline ("oasis bootstrap loader: " ^ message);
      exit 1
