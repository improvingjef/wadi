let starts_with ~prefix text =
  let prefix_length = String.length prefix in
  String.length text >= prefix_length
  && String.sub text 0 prefix_length = prefix

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
  let channel = open_in path in
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

let absolute_path path =
  if Filename.is_relative path then Filename.concat (Sys.getcwd ()) path else path

let manifest_path () =
  match Sys.getenv_opt "BOOTSTRAP_MODULE_MANIFEST" with
  | Some path when String.trim path <> "" -> absolute_path path
  | Some _ | None -> absolute_path "oasis.toml"

type library_section = {
  name : string;
  dir : string option;
  modules : string list option;
  packages : string list option;
}

let empty_library name = { name; dir = None; modules = None; packages = None }

type section_kind =
  | Library_section of string
  | Other_section
  | Not_a_section

let section_kind line =
  let trimmed = String.trim line in
  if starts_with ~prefix:"[" trimmed && trimmed.[String.length trimmed - 1] = ']'
  then
    let raw = String.sub trimmed 1 (String.length trimmed - 2) in
    match String.split_on_char '.' raw with
    | [ "library"; name ] -> Library_section name
    | _ -> Other_section
  else Not_a_section

let parse_string_value text =
  let trimmed = String.trim text in
  let length = String.length trimmed in
  if length >= 2 && trimmed.[0] = '"' && trimmed.[length - 1] = '"' then
    String.sub trimmed 1 (length - 2)
  else failwith ("expected a quoted string, got " ^ trimmed)

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

let parse_libraries path =
  let lines = read_file path |> String.split_on_char '\n' in
  let rec finalize current libraries =
    match current with
    | None -> libraries
    | Some library -> library :: libraries
  in
  let rec loop current array_key array_buffer libraries = function
    | [] -> List.rev (finalize current libraries)
    | raw_line :: rest ->
        let line = raw_line |> strip_comment |> String.trim in
        if array_key <> None then
          let buffer =
            match array_buffer with
            | Some buffer when buffer = "" -> line
            | Some buffer -> buffer ^ "\n" ^ line
            | None -> line
          in
          if String.contains line ']' then
            let current =
              match current, array_key with
              | Some library, Some "modules" ->
                  Some { library with modules = Some (parse_string_array buffer) }
              | Some library, Some "packages" ->
                  Some
                    { library with packages = Some (parse_string_array buffer) }
              | _ -> current
            in
            loop current None None libraries rest
          else loop current array_key (Some buffer) libraries rest
        else if line = "" then
          loop current None None libraries rest
        else
          match section_kind line with
          | Library_section name ->
              let libraries = finalize current libraries in
              loop (Some (empty_library name)) None None libraries rest
          | Other_section ->
              let libraries = finalize current libraries in
              loop None None None libraries rest
          | Not_a_section -> (
              match current, split_once ~on:'=' line with
              | Some library, Some (raw_key, raw_value) ->
                  let key = String.trim raw_key in
                  let value = String.trim raw_value in
                  if key = "dir" then
                    loop
                      (Some { library with dir = Some (parse_string_value value) })
                      None None libraries rest
                  else if key = "modules" then
                    if String.contains value ']' then
                      loop
                        (Some
                           {
                             library with
                             modules = Some (parse_string_array value);
                           })
                        None None libraries rest
                    else loop current (Some "modules") (Some value) libraries rest
                  else if key = "packages" then
                    if String.contains value ']' then
                      loop
                        (Some
                           {
                             library with
                             packages = Some (parse_string_array value);
                           })
                        None None libraries rest
                    else loop current (Some "packages") (Some value) libraries rest
                  else loop current None None libraries rest
              | _ -> loop current None None libraries rest)
  in
  loop None None None [] lines

let choose_library libraries =
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
               (manifest_path ())))
  | None -> (
      match List.find_opt (fun library -> library.name = "oasis_core") libraries with
      | Some library -> library
      | None -> (
          match libraries with
          | [ library ] -> library
          | [] ->
              failwith
                (Printf.sprintf "no [library.*] section found in %s"
                   (manifest_path ()))
          | libraries ->
              failwith
                (Printf.sprintf
                   "multiple libraries found in %s; set BOOTSTRAP_LIBRARY to \
                    choose one (%s)"
                   (manifest_path ())
                   (String.concat ", " (List.map (fun library -> library.name) libraries)))))

let library_files root_dir library =
  let dir =
    match library.dir with
    | Some dir -> dir
    | None ->
        failwith
          (Printf.sprintf "library '%s' is missing a dir setting in %s"
             library.name (manifest_path ()))
  in
  let modules =
    match library.modules with
    | Some modules -> modules
    | None ->
        failwith
          (Printf.sprintf "library '%s' is missing a modules setting in %s"
             library.name (manifest_path ()))
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

type output_format =
  | Mod_use
  | Ml_paths
  | Compile_paths
  | Packages

let output_format () =
  let rec loop index =
    if index >= Array.length Sys.argv then Mod_use
    else
      match Sys.argv.(index) with
      | "--format" ->
          if index + 1 >= Array.length Sys.argv then
            failwith "--format requires mod_use, ml-paths, compile-paths, or packages"
          else (
            match String.lowercase_ascii (String.trim Sys.argv.(index + 1)) with
            | "mod_use" | "mod-use" -> Mod_use
            | "ml_paths" | "ml-paths" -> Ml_paths
            | "compile_paths" | "compile-paths" -> Compile_paths
            | "packages" -> Packages
            | value ->
                failwith
                  ("unknown --format value '" ^ value
                 ^ "'; expected mod_use, ml-paths, compile-paths, or packages"))
      | _ -> loop (index + 1)
  in
  loop 1

let () =
  try
    let module_manifest_path = manifest_path () in
    let root_dir = Filename.dirname module_manifest_path in
    let library =
      module_manifest_path |> parse_libraries |> choose_library
    in
    match output_format () with
    | Mod_use ->
        let module_files =
          library_files root_dir library |> ordered_module_files
        in
        List.iter
          (fun path -> Printf.printf "#mod_use %S;;\n" path)
          module_files
    | Ml_paths ->
        let module_files =
          library_files root_dir library |> ordered_module_files
        in
        List.iter print_endline module_files
    | Compile_paths ->
        let module_files =
          library_files root_dir library |> ordered_module_files ~keep_interfaces:true
        in
        List.iter print_endline module_files
    | Packages ->
        List.iter print_endline
          (match library.packages with
          | Some packages -> packages
          | None -> [])
  with
  | Failure message ->
      prerr_endline ("oasis bootstrap loader: " ^ message);
      exit 1
