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

let render_json report =
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
