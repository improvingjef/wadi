type target_lock = {
  target : Manifest.target;
  direct_workspace_deps : string list;
  external_packages : string list;
  resolved_packages : (string * string) list;
}

type report = {
  version : int;
  workspace_name : string option;
  manifest_path : string;
  manifest_digest : string;
  requested_targets : string list;
  resolved_targets : string list;
  toolchain : Toolchain.report;
  packages : string list;
  package_paths : (string * string) list;
  targets : target_lock list;
}

type locked_target = {
  name : string;
  external_packages : string list;
  resolved_packages : (string * string) list;
}

type snapshot = {
  version : int;
  manifest_path : string;
  manifest_digest : string;
  package_paths : (string * string) list;
  targets : locked_target list;
}

type json =
  | JObject of (string * json) list
  | JArray of json list
  | JString of string
  | JNumber of string
  | JBool of bool
  | JNull

let ( let* ) = Result.bind

let json_string text = "\"" ^ String_util.json_escape text ^ "\""

let json_null = "null"

let json_option render = function
  | Some value -> render value
  | None -> json_null

let json_array render items =
  "[" ^ String.concat "," (List.map render items) ^ "]"

let json_object fields =
  "{"
  ^ String.concat ","
      (List.map
         (fun (name, value) -> json_string name ^ ":" ^ value)
         fields)
  ^ "}"

let json_result render = function
  | Ok value -> json_object [ ("ok", render value) ]
  | Error message ->
      json_object [ ("error", json_string (String.trim message)) ]

let json_command (command : Toolchain.resolved_command) =
  json_object
    [
      ("configured", json_string command.configured);
      ("resolved", json_option json_string command.resolved);
    ]

let create ~workspace_root workspace requested_targets =
  let session = Toolchain.create_session () in
  let* deps_report = Deps.report_for_targets ~session workspace requested_targets in
  let packages =
    deps_report.targets
    |> List.map (fun (target : Deps.target_report) -> target.closure_packages)
    |> List.concat |> String_util.dedup_preserve
  in
  let* package_resolution = Toolchain.resolve_packages ~session packages in
  let targets =
    List.map
      (fun (target : Deps.target_report) ->
        {
          target = target.target;
          direct_workspace_deps = target.direct_workspace_deps;
          external_packages = target.closure_packages;
      resolved_packages = target.package_resolution.package_paths;
        })
      deps_report.targets
  in
  let manifest_path = Manifest.default_filename in
  let manifest_digest =
    Digest.file (Filename.concat workspace_root manifest_path) |> Digest.to_hex
  in
  Ok
    {
      version = 1;
      workspace_name = workspace.Manifest.name;
      manifest_path;
      manifest_digest;
      requested_targets;
      resolved_targets =
        List.map
          (fun (target : Deps.target_report) ->
            Manifest.target_name target.target)
          deps_report.targets;
      toolchain = Toolchain.inspect ~session ();
      packages;
      package_paths = package_resolution.package_paths;
      targets;
    }

let default_lock_path workspace_root =
  Filename.concat workspace_root "oasis.lock"

let json_error path index message =
  Error (Printf.sprintf "%s:%d: %s" path index message)

let parse_json path text =
  let length = String.length text in
  let rec skip_whitespace index =
    if index < length then
      match text.[index] with
      | ' ' | '\t' | '\n' | '\r' -> skip_whitespace (index + 1)
      | _ -> index
    else index
  in
  let rec parse_value index =
    let index = skip_whitespace index in
    if index >= length then json_error path index "unexpected end of file"
    else
      match text.[index] with
      | '{' -> parse_object (index + 1)
      | '[' -> parse_array (index + 1)
      | '"' ->
          let* value, next_index = Manifest.parse_quoted_string path 1 text index in
          Ok (JString value, next_index)
      | 't' -> parse_literal index "true" (JBool true)
      | 'f' -> parse_literal index "false" (JBool false)
      | 'n' -> parse_literal index "null" JNull
      | '-' | '0' .. '9' -> parse_number index
      | ch ->
          json_error path index
            (Printf.sprintf "unexpected character %C in JSON value" ch)
  and parse_literal index literal value =
    let literal_length = String.length literal in
    if
      index + literal_length <= length
      && String.sub text index literal_length = literal
    then Ok (value, index + literal_length)
    else json_error path index ("expected " ^ literal)
  and parse_number index =
    let rec scan index =
      if index < length then
        match text.[index] with
        | '0' .. '9' | '-' | '+' | '.' | 'e' | 'E' -> scan (index + 1)
        | _ -> index
      else index
    in
    let next_index = scan index in
    Ok (JNumber (String.sub text index (next_index - index)), next_index)
  and parse_array index =
    let rec loop index acc =
      let index = skip_whitespace index in
      if index >= length then json_error path index "unterminated JSON array"
      else if text.[index] = ']' then Ok (JArray (List.rev acc), index + 1)
      else
        let* value, next_index = parse_value index in
        let next_index = skip_whitespace next_index in
        if next_index >= length then
          json_error path next_index "unterminated JSON array"
        else
          match text.[next_index] with
          | ',' -> loop (next_index + 1) (value :: acc)
          | ']' -> Ok (JArray (List.rev (value :: acc)), next_index + 1)
          | ch ->
              json_error path next_index
                (Printf.sprintf "unexpected character %C in JSON array" ch)
    in
    loop index []
  and parse_object index =
    let rec loop index acc =
      let index = skip_whitespace index in
      if index >= length then json_error path index "unterminated JSON object"
      else if text.[index] = '}' then Ok (JObject (List.rev acc), index + 1)
      else
        let* key, next_index =
          match parse_value index with
          | Ok (JString key, next_index) -> Ok (key, next_index)
          | Ok _ -> json_error path index "JSON object keys must be strings"
          | Error _ as error -> error
        in
        let next_index = skip_whitespace next_index in
        if next_index >= length || text.[next_index] <> ':' then
          json_error path next_index "expected ':' after JSON object key"
        else
          let* value, next_index = parse_value (next_index + 1) in
          let next_index = skip_whitespace next_index in
          if next_index >= length then
            json_error path next_index "unterminated JSON object"
          else
            match text.[next_index] with
            | ',' -> loop (next_index + 1) ((key, value) :: acc)
            | '}' -> Ok (JObject (List.rev ((key, value) :: acc)), next_index + 1)
            | ch ->
                json_error path next_index
                  (Printf.sprintf "unexpected character %C in JSON object" ch)
    in
    loop index []
  in
  let* value, next_index = parse_value 0 in
  let next_index = skip_whitespace next_index in
  if next_index <> length then
    json_error path next_index "unexpected trailing JSON content"
  else Ok value

let json_field name = function
  | JObject fields -> (
      match List.assoc_opt name fields with
      | Some value -> Ok value
      | None -> Error ("missing JSON field " ^ name) )
  | _ -> Error "expected a JSON object"

let json_string_value = function
  | JString value -> Ok value
  | _ -> Error "expected a JSON string"

let json_array_value = function
  | JArray items -> Ok items
  | _ -> Error "expected a JSON array"

let json_int_value = function
  | JNumber value -> (
      try Ok (int_of_string value) with
      | Failure _ -> Error ("invalid JSON integer " ^ value) )
  | _ -> Error "expected a JSON integer"

let json_string_field name json =
  let* value = json_field name json in
  json_string_value value

let json_array_field name json =
  let* value = json_field name json in
  json_array_value value

let json_int_field name json =
  let* value = json_field name json in
  json_int_value value

let json_string_list_field name json =
  let* items = json_array_field name json in
  let rec loop acc = function
    | [] -> Ok (List.rev acc)
    | item :: rest ->
        let* value = json_string_value item in
        loop (value :: acc) rest
  in
  loop [] items

let json_object_fields = function
  | JObject fields -> Ok fields
  | _ -> Error "expected a JSON object"

let parse_locked_target json =
  let* _ = json_object_fields json in
  let* name = json_string_field "name" json in
  let* external_packages = json_string_list_field "external_packages" json in
  let* resolved_packages_json = json_array_field "resolved_packages" json in
  let rec loop acc = function
    | [] -> Ok (List.rev acc)
    | package_json :: rest ->
        let* _ = json_object_fields package_json in
        let* package_name = json_string_field "name" package_json in
        let* package_path = json_string_field "path" package_json in
        loop ((package_name, package_path) :: acc) rest
  in
  let* resolved_packages = loop [] resolved_packages_json in
  Ok { name; external_packages; resolved_packages }

let parse_package_paths json =
  let rec loop acc = function
    | [] -> Ok (List.rev acc)
    | package_json :: rest ->
        let* _ = json_object_fields package_json in
        let* package_name = json_string_field "name" package_json in
        let* package_path = json_string_field "path" package_json in
        loop ((package_name, package_path) :: acc) rest
  in
  let* packages_json = json_array_value json in
  loop [] packages_json

let load_snapshot lock_path =
  let* json = parse_json lock_path (Fs.read_file lock_path) in
  let* _ = json_object_fields json in
  let* version = json_int_field "version" json in
  if version <> 1 then
    Error
      (Printf.sprintf "unsupported lock file version %d in %s" version lock_path)
  else
    let* manifest_json = json_field "manifest" json in
    let* _ = json_object_fields manifest_json in
    let* manifest_path = json_string_field "path" manifest_json in
    let* manifest_digest = json_string_field "digest" manifest_json in
    let* package_paths =
      let* package_paths_json = json_field "package_paths" json in
      parse_package_paths package_paths_json
    in
    let* targets_json = json_array_field "targets" json in
    let rec loop acc = function
      | [] -> Ok (List.rev acc)
      | target_json :: rest ->
          let* target = parse_locked_target target_json in
          loop (target :: acc) rest
    in
    let* targets = loop [] targets_json in
    Ok { version; manifest_path; manifest_digest; package_paths; targets }

let render_names names =
  match names with
  | [] -> "none"
  | names -> String.concat ", " names

let normalized_names names =
  List.sort_uniq String.compare names

let package_map packages =
  let table = Hashtbl.create (List.length packages) in
  List.iter (fun (name, path) -> Hashtbl.replace table name path) packages;
  table

let compare_package_paths ~label locked current =
  let locked_map = package_map locked in
  let current_map = package_map current in
  let differences = ref [] in
  List.iter
    (fun (package_name, current_path) ->
      match Hashtbl.find_opt locked_map package_name with
      | None ->
          differences :=
            (Printf.sprintf
               "%s now resolves package '%s' at %s, but oasis.lock does not \
                record that package"
               label package_name current_path)
            :: !differences
      | Some locked_path when locked_path = current_path -> ()
      | Some locked_path ->
          differences :=
            (Printf.sprintf
               "%s package '%s' path drifted: locked %s, current %s"
               label package_name locked_path current_path)
            :: !differences)
    current;
  List.iter
    (fun (package_name, locked_path) ->
      if not (Hashtbl.mem current_map package_name) then
        differences :=
          (Printf.sprintf
             "%s no longer resolves package '%s', but oasis.lock still points \
              at %s"
             label package_name locked_path)
          :: !differences)
    locked;
  List.rev !differences

let compare_target lock_target (current_target : target_lock) =
  let label = Manifest.target_display_name current_target.target in
  let external_packages = normalized_names current_target.external_packages in
  let locked_packages = normalized_names lock_target.external_packages in
  let package_differences =
    compare_package_paths ~label lock_target.resolved_packages
      current_target.resolved_packages
  in
  if external_packages = locked_packages then package_differences
  else
    (Printf.sprintf
       "%s external package closure drifted: locked [%s], current [%s]"
       label
       (render_names lock_target.external_packages)
       (render_names current_target.external_packages))
    :: package_differences

let render_validation_error lock_path differences =
  String.concat "\n"
    (("lock validation failed against " ^ lock_path ^ ":")
    :: List.map (fun difference -> "- " ^ difference) differences
    @ [ "Refresh the snapshot with `oasis lock`." ])

let validate_current ~workspace_root workspace requested_targets =
  let lock_path = default_lock_path workspace_root in
  if not (Fs.exists lock_path) then
    Error
      (Printf.sprintf
         "lock validation requested, but %s does not exist; run `oasis lock` first"
         lock_path)
  else
    let* snapshot =
      load_snapshot lock_path |> Result.map_error (fun message ->
          Printf.sprintf "failed to read %s\n%s" lock_path message)
    in
    let* current = create ~workspace_root workspace requested_targets in
    let differences = ref [] in
    if snapshot.manifest_path <> current.manifest_path then
      differences :=
        (Printf.sprintf "lock file records manifest %s, but the workspace uses %s"
           snapshot.manifest_path current.manifest_path)
        :: !differences;
    if snapshot.manifest_digest <> current.manifest_digest then
      differences :=
        "workspace manifest digest changed since oasis.lock was written"
        :: !differences;
    differences :=
      List.rev_append
        (compare_package_paths ~label:"workspace package closure"
           snapshot.package_paths current.package_paths)
        !differences;
    let target_index = Hashtbl.create (List.length snapshot.targets) in
    List.iter
      (fun target -> Hashtbl.replace target_index target.name target)
      snapshot.targets;
    List.iter
      (fun (target : target_lock) ->
        match
          Hashtbl.find_opt target_index (Manifest.target_name target.target)
        with
        | Some lock_target ->
            differences :=
              List.rev_append (compare_target lock_target target) !differences
        | None ->
            differences :=
              (Printf.sprintf
                 "oasis.lock does not contain a snapshot for target %s"
                 (Manifest.target_display_name target.target))
              :: !differences)
      current.targets;
    match List.rev !differences with
    | [] -> Ok ()
    | differences -> Error (render_validation_error lock_path differences)

let render_target (target_lock : target_lock) =
  json_object
    [
      ("name", json_string (Manifest.target_name target_lock.target));
      ("kind", json_string (Manifest.target_kind_name target_lock.target));
      ( "package_path",
        json_option json_string
          (Manifest.target_package_path target_lock.target) );
      ("workspace_deps", json_array json_string target_lock.direct_workspace_deps);
      ("external_packages", json_array json_string target_lock.external_packages);
      ( "resolved_packages",
        json_array
          (fun (package_name, package_path) ->
            json_object
              [
                ("name", json_string package_name);
                ("path", json_string package_path);
              ])
          target_lock.resolved_packages );
    ]

let render_json (report : report) =
  json_object
    [
      ("version", string_of_int report.version);
      ("workspace", json_option json_string report.workspace_name);
      ( "manifest",
        json_object
          [
            ("path", json_string report.manifest_path);
            ("digest", json_string report.manifest_digest);
          ] );
      ("requested_targets", json_array json_string report.requested_targets);
      ("resolved_targets", json_array json_string report.resolved_targets);
      ( "toolchain",
        json_object
          [
            ("ocamlc", json_command report.toolchain.ocamlc);
            ("ocamlopt", json_command report.toolchain.ocamlopt);
            ("ocamldep", json_command report.toolchain.ocamldep);
            ("ocamlfind", json_command report.toolchain.ocamlfind);
            ( "selected_backend",
              json_result
                (fun backend ->
                  json_string (Toolchain.backend_name backend))
                report.toolchain.selected_backend );
            ( "compiler_version",
              json_result json_string report.toolchain.compiler_version );
            ("stdlib", json_result json_string report.toolchain.stdlib);
            ( "unix_library_dir",
              json_result (json_option json_string) report.toolchain.unix_dir );
            ( "package_roots",
              json_result (json_array json_string) report.toolchain.package_roots );
          ] );
      ("packages", json_array json_string report.packages);
      ( "package_paths",
        json_array
          (fun (package_name, package_path) ->
            json_object
              [
                ("name", json_string package_name);
                ("path", json_string package_path);
              ])
          report.package_paths );
      ("targets", json_array render_target report.targets);
    ]
  ^ "\n"
