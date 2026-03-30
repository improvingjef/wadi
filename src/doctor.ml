type check_state = Pass | Warn | Fail
type check = { name : string; state : check_state; details : string list }
type summary = { passed : int; warned : int; failed : int }

type report = {
  workspace_name : string option;
  workspace_root : string;
  profile : string;
  requested_targets : string list;
  backend_request : Toolchain.backend_request;
  checks : check list;
  summary : summary;
}

type lock_policy = Ignore_lock | Warn_locked | Require_locked

let ( let* ) = Result.bind

let resolve_profile workspace = function
  | Some profile when String.trim profile <> "" -> profile
  | Some _ | None -> Manifest.default_profile workspace

let check name state details = { name; state; details }
let state_name = function Pass -> "pass" | Warn -> "warn" | Fail -> "fail"

let summarize checks =
  List.fold_left
    (fun summary check ->
      match check.state with
      | Pass -> { summary with passed = summary.passed + 1 }
      | Warn -> { summary with warned = summary.warned + 1 }
      | Fail -> { summary with failed = summary.failed + 1 })
    { passed = 0; warned = 0; failed = 0 }
    checks

let render_requested_targets requested_targets =
  if requested_targets = [] then "all" else String.concat ", " requested_targets

let render_result render_ok = function
  | Ok value -> render_ok value
  | Error message -> "error: " ^ String.trim message

let manifest_check ~workspace_root ~profile workspace requested_targets =
  let target_names = List.map Manifest.target_name workspace.Manifest.targets in
  check "manifest" Pass
    [
      "manifest: " ^ Filename.concat workspace_root Manifest.default_filename;
      "profile: " ^ profile;
      ("targets: "
      ^ match target_names with [] -> "none" | targets -> String.concat ", " targets);
      "requested-targets: " ^ render_requested_targets requested_targets;
    ]

let graph_check workspace requested_targets =
  match Builder.resolve_build_order workspace requested_targets with
  | Ok order ->
      check "graph" Pass
        [
          ("build-order: "
          ^
          match List.map Manifest.target_display_name order with
          | [] -> "none"
          | names -> String.concat " -> " names);
        ]
  | Error message -> check "graph" Fail [ String.trim message ]

let toolchain_check ~session backend_request =
  let report = Toolchain.inspect ~session () in
  let details =
    [
      Toolchain.render_command_report "ocamlc" report.ocamlc;
      Toolchain.render_command_report "ocamlopt" report.ocamlopt;
      Toolchain.render_command_report "ocamldep" report.ocamldep;
      Toolchain.render_command_report "ocamlfind" report.ocamlfind;
      "backend-request: " ^ Toolchain.backend_request_name backend_request;
      "selected-backend: " ^ render_result Toolchain.backend_name report.selected_backend;
      "compiler-version: " ^ render_result Fun.id report.compiler_version;
      "stdlib: " ^ render_result Fun.id report.stdlib;
      (match report.unix_dir with
      | Ok (Some path) -> "unix-library-dir: " ^ path
      | Ok None -> "unix-library-dir: unavailable"
      | Error message -> "unix-library-dir: error: " ^ String.trim message);
      "package-roots: "
      ^ render_result
          (function [] -> "none" | roots -> String.concat ", " roots)
          report.package_roots;
    ]
  in
  let state =
    match (report.selected_backend, report.compiler_version, report.stdlib) with
    | Ok _, Ok _, Ok _ -> (
        match report.package_roots with Ok _ -> Pass | Error _ -> Warn)
    | _ -> Fail
  in
  check "toolchain" state details

let deps_check ~session workspace requested_targets =
  match Deps.report_for_targets ~session workspace requested_targets with
  | Error message -> check "packages" Fail [ String.trim message ]
  | Ok report ->
      let target_details =
        List.map
          (fun (target : Deps.target_report) ->
            Printf.sprintf "%s: %s"
              (Manifest.target_display_name target.target)
              (match target.closure_packages with
              | [] -> "no external packages"
              | packages -> String.concat ", " packages))
          report.targets
      in
      let package_roots =
        match report.package_roots with
        | Ok [] -> [ "package-roots: none" ]
        | Ok roots -> [ "package-roots: " ^ String.concat ", " roots ]
        | Error message -> [ "package-roots: error: " ^ String.trim message ]
      in
      let state = match report.package_roots with Ok _ -> Pass | Error _ -> Warn in
      check "packages" state (package_roots @ target_details)

let lock_check ~lock_policy ~workspace_root workspace requested_targets =
  match lock_policy with
  | Ignore_lock -> check "lock" Pass [ "lock validation skipped" ]
  | Warn_locked | Require_locked -> (
      let lock_path = Locker.default_lock_path workspace_root in
      match Locker.validate_current ~workspace_root workspace requested_targets with
      | Ok () -> check "lock" Pass [ "lock file is current: " ^ lock_path ]
      | Error message ->
          let state =
            match lock_policy with
            | Require_locked -> Fail
            | Warn_locked | Ignore_lock -> Warn
          in
          check "lock" state [ String.trim message ])

let with_temp_dir prefix f =
  let path = Filename.temp_file prefix ".tmp" in
  Unix.unlink path;
  Unix.mkdir path 0o755;
  Fun.protect ~finally:(fun () -> Fs.remove_tree path) (fun () -> f path)

let generated_release_artifact_paths =
  [
    "docs/cli.md";
    "completions/wadi.bash";
    "completions/_wadi";
    "completions/wadi.fish";
    "package/share/doc/wadi/cli.md";
    "package/share/bash-completion/completions/wadi";
    "package/share/zsh/site-functions/_wadi";
    "package/share/fish/vendor_completions.d/wadi.fish";
  ]

let generated_release_metadata_paths =
  [ "wadi.opam"; "Formula/wadi.rb"; "dist/release-assets.json" ]

let has_any_generated_paths workspace_root paths =
  List.exists
    (fun relative_path -> Fs.exists (Filename.concat workspace_root relative_path))
    paths

let generator_summary output =
  match List.rev (String_util.split_lines output) with
  | line :: _ -> line
  | [] -> "no output"

let compare_generated_paths ~workspace_root ~generated_root relative_paths =
  List.filter_map
    (fun relative_path ->
      let workspace_path = Filename.concat workspace_root relative_path in
      let generated_path = Filename.concat generated_root relative_path in
      match (Fs.exists workspace_path, Fs.exists generated_path) with
      | true, true ->
          if Fs.read_file workspace_path = Fs.read_file generated_path then None
          else Some (relative_path ^ " drifted")
      | false, true -> Some (relative_path ^ " is missing from the workspace")
      | true, false -> Some (relative_path ^ " was not regenerated by the generator")
      | false, false ->
          Some
            (relative_path ^ " is missing from both the workspace and regenerated output"))
    relative_paths

let render_drift_details label drifted =
  match drifted with
  | [] -> label ^ ": current"
  | drifted -> label ^ ": " ^ String.concat ", " drifted

let generated_assets_check workspace_root =
  let release_artifacts_script =
    Filename.concat workspace_root "scripts/generate_release_artifacts.sh"
  in
  let packaging_manifests_script =
    Filename.concat workspace_root "scripts/generate_packaging_manifests.sh"
  in
  let release_artifacts_applicable =
    Fs.exists release_artifacts_script
    || has_any_generated_paths workspace_root generated_release_artifact_paths
  in
  let release_metadata_applicable =
    Fs.exists packaging_manifests_script
    || has_any_generated_paths workspace_root generated_release_metadata_paths
  in
  if (not release_artifacts_applicable) && not release_metadata_applicable then None
  else
    Some
      (with_temp_dir "wadi-doctor-generated-assets" (fun temp_root ->
           let details = ref [] in
           let warned = ref false in
           let note_warning detail =
             warned := true;
             details := !details @ [ detail ]
           in
           (if release_artifacts_applicable then
              if not (Fs.exists release_artifacts_script) then
                note_warning
                  ("release-artifacts: generator missing: " ^ release_artifacts_script)
              else
                let output_dir = Filename.concat temp_root "release-artifacts" in
                let regenerated =
                  Process.run_capture ~cwd:workspace_root
                    ~env:[ ("WADI_BIN", Fs.resolve_executable Sys.executable_name) ]
                    "/bin/sh"
                    [ release_artifacts_script; "--output-dir"; output_dir ]
                in
                if regenerated.status <> 0 then
                  note_warning
                    (Printf.sprintf "release-artifacts: regeneration failed (%s): %s"
                       (Process.status_to_text regenerated.unix_status)
                       (generator_summary regenerated.output))
                else
                  let drifted =
                    compare_generated_paths ~workspace_root ~generated_root:output_dir
                      generated_release_artifact_paths
                  in
                  if drifted = [] then
                    details := !details @ [ "release-artifacts: current" ]
                  else note_warning (render_drift_details "release-artifacts" drifted));
           (if release_metadata_applicable then
              if not (Fs.exists packaging_manifests_script) then
                note_warning
                  ("release-metadata: generator missing: " ^ packaging_manifests_script)
              else
                let output_dir = Filename.concat temp_root "release-metadata" in
                let asset_index_output =
                  Filename.concat output_dir "dist/release-assets.json"
                in
                let regenerated =
                  Process.run_capture ~cwd:workspace_root
                    ~env:[ ("WADI_BIN", Fs.resolve_executable Sys.executable_name) ]
                    "/bin/sh"
                    [
                      packaging_manifests_script;
                      "--output-dir";
                      output_dir;
                      "--source-archive-dir";
                      Filename.concat output_dir "dist";
                      "--asset-index-output";
                      asset_index_output;
                    ]
                in
                if regenerated.status <> 0 then
                  note_warning
                    (Printf.sprintf "release-metadata: regeneration failed (%s): %s"
                       (Process.status_to_text regenerated.unix_status)
                       (generator_summary regenerated.output))
                else
                  let drifted =
                    compare_generated_paths ~workspace_root ~generated_root:output_dir
                      generated_release_metadata_paths
                  in
                  if drifted = [] then
                    details := !details @ [ "release-metadata: current" ]
                  else note_warning (render_drift_details "release-metadata" drifted));
           if !warned then
             check "generated-assets" Warn
               (!details @ [ "Refresh generated assets with `make sync-generated`." ])
           else check "generated-assets" Pass !details))

let report ~workspace_root ?(requested_targets = []) ?(backend_request = Toolchain.Auto)
    ?profile ~lock_policy workspace =
  let workspace_root = Fs.realpath workspace_root in
  let profile = resolve_profile workspace profile in
  let session = Toolchain.create_session () in
  let checks =
    [
      manifest_check ~workspace_root ~profile workspace requested_targets;
      graph_check workspace requested_targets;
      toolchain_check ~session backend_request;
      deps_check ~session workspace requested_targets;
      lock_check ~lock_policy ~workspace_root workspace requested_targets;
    ]
    @
    match generated_assets_check workspace_root with
    | Some check -> [ check ]
    | None -> []
  in
  let summary = summarize checks in
  Ok
    {
      workspace_name = workspace.Manifest.name;
      workspace_root;
      profile;
      requested_targets;
      backend_request;
      checks;
      summary;
    }

let has_failures (report : report) = report.summary.failed > 0

let render_check (check : check) =
  String.concat "\n"
    (Printf.sprintf "%s: %s" check.name (state_name check.state)
    :: List.map (fun detail -> "- " ^ detail) check.details)

let render_report (report : report) =
  String.concat "\n"
    ([
       ("Workspace: "
       ^ match report.workspace_name with Some name -> name | None -> "unnamed");
       "Workspace-root: " ^ report.workspace_root;
       "Profile: " ^ report.profile;
       "Requested-targets: " ^ render_requested_targets report.requested_targets;
       "Backend-request: " ^ Toolchain.backend_request_name report.backend_request;
       Printf.sprintf "Summary: pass=%d warn=%d fail=%d" report.summary.passed
         report.summary.warned report.summary.failed;
     ]
    @ List.concat_map (fun check -> [ ""; render_check check ]) report.checks
    @ [ "" ])

let json_string text = "\"" ^ String_util.json_escape text ^ "\""
let json_array render items = "[" ^ String.concat ", " (List.map render items) ^ "]"
let json_option render = function Some value -> render value | None -> "null"

let render_json_check (check : check) =
  String.concat "\n"
    [
      "    {";
      "      \"name\": " ^ json_string check.name ^ ",";
      "      \"state\": " ^ json_string (state_name check.state) ^ ",";
      "      \"details\": " ^ json_array json_string check.details;
      "    }";
    ]

let render_json_report (report : report) =
  let checks =
    match report.checks with
    | [] -> "[]"
    | checks -> "[\n" ^ String.concat ",\n" (List.map render_json_check checks) ^ "\n  ]"
  in
  String.concat "\n"
    [
      "{";
      "  \"workspace\": " ^ json_option json_string report.workspace_name ^ ",";
      "  \"workspace_root\": " ^ json_string report.workspace_root ^ ",";
      "  \"profile\": " ^ json_string report.profile ^ ",";
      "  \"requested_targets\": " ^ json_array json_string report.requested_targets ^ ",";
      "  \"backend_request\": "
      ^ json_string (Toolchain.backend_request_name report.backend_request)
      ^ ",";
      "  \"summary\": {";
      "    \"pass\": " ^ string_of_int report.summary.passed ^ ",";
      "    \"warn\": " ^ string_of_int report.summary.warned ^ ",";
      "    \"fail\": " ^ string_of_int report.summary.failed;
      "  },";
      "  \"checks\": " ^ checks;
      "}";
      "";
    ]
