type subtool =
  | Build
  | Action
  | Run
  | Test
  | Bench
  | Install

type context = {
  target : string;
  label : string;
  env : (string * string) list;
}

type report = {
  workspace_name : string option;
  subtool : subtool;
  profile : string;
  requested : string list;
  changed_only : bool;
  contexts : context list;
}

let ( let* ) = Result.bind

let subtool_name = function
  | Build -> "build"
  | Action -> "action"
  | Run -> "run"
  | Test -> "test"
  | Bench -> "bench"
  | Install -> "install"

let parse_subtool value =
  match String.lowercase_ascii (String.trim value) with
  | "build" -> Ok Build
  | "action" -> Ok Action
  | "run" -> Ok Run
  | "test" -> Ok Test
  | "bench" -> Ok Bench
  | "install" -> Ok Install
  | value ->
      Error
        (Printf.sprintf
           "unknown env subtool '%s'; expected build, action, run, test, bench, or install"
           value)

let resolve_profile workspace = function
  | Some profile when String.trim profile <> "" -> profile
  | Some _ | None -> Manifest.default_profile workspace

let display_name name package_path =
  name ^ Manifest.package_suffix package_path

let target_index (workspace : Manifest.workspace) =
  let index = Hashtbl.create (List.length workspace.targets) in
  List.iter
    (fun target -> Hashtbl.replace index (Manifest.target_name target) target)
    workspace.targets;
  index

let resolve_named_targets workspace requested_targets =
  let requested_targets = String_util.dedup_preserve requested_targets in
  if requested_targets = [] then Ok workspace.Manifest.targets
  else
    let index = target_index workspace in
    let rec loop acc = function
      | [] -> Ok (List.rev acc)
      | name :: rest -> (
          match Hashtbl.find_opt index name with
          | Some target -> loop (target :: acc) rest
          | None -> Error (Printf.sprintf "unknown target '%s'" name))
    in
    loop [] requested_targets

let executable_targets (workspace : Manifest.workspace) =
  List.filter_map
    (function
      | Manifest.Executable executable -> Some executable
      | Manifest.Library _ | Manifest.Test _ -> None)
    workspace.targets

let test_targets (workspace : Manifest.workspace) =
  List.filter_map
    (function
      | Manifest.Test test -> Some test
      | Manifest.Library _ | Manifest.Executable _ -> None)
    workspace.targets

type bench_request = {
  name : string;
  package_path : string option;
  executable : Manifest.executable;
  env : Manifest.env_binding list;
}

let installable_targets (workspace : Manifest.workspace) =
  List.filter
    (function
      | Manifest.Library _ | Manifest.Executable _ -> true
      | Manifest.Test _ -> false)
    workspace.targets

let resolve_run_target workspace requested_target =
  match requested_target with
  | Some name -> (
      match
        List.find_opt
          (fun target -> Manifest.target_name target = name)
          workspace.Manifest.targets
      with
      | Some (Manifest.Executable executable) -> Ok executable
      | Some (Manifest.Library _) ->
          Error
            (Printf.sprintf
               "target '%s' is a library; wadi env run only supports executables"
               name)
      | Some (Manifest.Test _) ->
          Error
            (Printf.sprintf
               "target '%s' is a test; wadi env run only supports executables"
               name)
      | None -> Error (Printf.sprintf "unknown target '%s'" name))
  | None -> (
      match executable_targets workspace with
      | [] -> Error "workspace does not define any executables to run"
      | [ executable ] -> Ok executable
      | executables ->
          Error
            (Printf.sprintf
               "workspace defines multiple executables; choose one: %s"
               (String.concat ", "
                  (List.map
                     (fun (executable : Manifest.executable) -> executable.name)
                     executables))))

let resolve_test_targets workspace requested_targets =
  let requested_targets = String_util.dedup_preserve requested_targets in
  if requested_targets = [] then
    match test_targets workspace with
    | [] -> Error "workspace does not define any tests to run"
    | tests -> Ok tests
  else
    let index = target_index workspace in
    let rec loop acc = function
      | [] -> Ok (List.rev acc)
      | name :: rest -> (
          match Hashtbl.find_opt index name with
          | Some (Manifest.Test test) -> loop (test :: acc) rest
          | Some target ->
              Error
                (Printf.sprintf
                   "target '%s' is %s '%s'; wadi env test only supports tests"
                   name
                   (Manifest.target_kind_name target)
                   (Manifest.target_name target))
          | None -> Error (Printf.sprintf "unknown target '%s'" name))
    in
    loop [] requested_targets

let resolve_bench_targets workspace requested_targets =
  let requested_targets = String_util.dedup_preserve requested_targets in
  let executable_request (executable : Manifest.executable) =
    { name = executable.name; package_path = executable.package_path; executable; env = [] }
  in
  let declared_bench_request (bench : Manifest.bench_target) =
    match
      List.find_opt
        (fun target -> Manifest.target_name target = bench.executable)
        workspace.Manifest.targets
    with
    | Some (Manifest.Executable executable) ->
        Ok
          {
            name = bench.name;
            package_path = bench.package_path;
            executable;
            env = bench.env;
          }
    | Some (Manifest.Library _) ->
        Error
          (Printf.sprintf
             "bench '%s' points at library '%s'; wadi env bench requires executable targets"
             bench.name bench.executable)
    | Some (Manifest.Test _) ->
        Error
          (Printf.sprintf
             "bench '%s' points at test '%s'; wadi env bench requires executable targets"
             bench.name bench.executable)
    | None ->
        Error
          (Printf.sprintf "bench '%s' points at unknown executable '%s'" bench.name
             bench.executable)
  in
  if requested_targets = [] then
    match workspace.Manifest.benches with
    | bench :: benches ->
        let rec loop acc = function
          | [] -> Ok (List.rev acc)
          | bench :: rest ->
              let* resolved = declared_bench_request bench in
              loop (resolved :: acc) rest
        in
        loop [] (bench :: benches)
    | [] -> (
        match executable_targets workspace with
        | [] -> Error "workspace does not define any benchmarks or executables to benchmark"
        | executables -> Ok (List.map executable_request executables))
  else
    let index = target_index workspace in
    let rec loop acc = function
      | [] -> Ok (List.rev acc)
      | name :: rest -> (
          match Manifest.find_bench workspace name with
          | Some bench ->
              let* resolved = declared_bench_request bench in
              loop (resolved :: acc) rest
          | None -> (
              match Hashtbl.find_opt index name with
              | Some (Manifest.Executable executable) ->
                  loop (executable_request executable :: acc) rest
              | Some (Manifest.Library _) ->
                  Error
                    (Printf.sprintf
                       "target '%s' is a library; wadi env bench only supports executables or [bench.*] declarations"
                       name)
              | Some (Manifest.Test _) ->
                  Error
                    (Printf.sprintf
                       "target '%s' is a test; wadi env bench only supports executables or [bench.*] declarations"
                       name)
              | None -> Error (Printf.sprintf "unknown target '%s'" name)))
    in
    loop [] requested_targets

let resolve_install_targets workspace requested_targets =
  let requested_targets = String_util.dedup_preserve requested_targets in
  if requested_targets = [] then
    match installable_targets workspace with
    | [] ->
        Error "workspace does not define any installable libraries or executables"
    | targets -> Ok targets
  else
    let index = target_index workspace in
    let rec loop acc = function
      | [] -> Ok (List.rev acc)
      | name :: rest -> (
          match Hashtbl.find_opt index name with
          | Some (Manifest.Library _ as target)
          | Some (Manifest.Executable _ as target) ->
              loop (target :: acc) rest
          | Some (Manifest.Test _) ->
              Error
                (Printf.sprintf
                   "target '%s' is a test; wadi env install only supports libraries and executables"
                   name)
          | None -> Error (Printf.sprintf "unknown target '%s'" name))
    in
    loop [] requested_targets

let full_env bindings =
  Process.merged_environment_bindings bindings
  |> List.sort (fun (left, _) (right, _) -> String.compare left right)

let host_env () = full_env []

let changed_env ~host_env bindings =
  let host_index = Hashtbl.create (List.length host_env) in
  List.iter (fun (name, value) -> Hashtbl.replace host_index name value) host_env;
  List.filter
    (fun (name, value) ->
      match Hashtbl.find_opt host_index name with
      | Some host_value when host_value = value -> false
      | Some _ | None -> true)
    (full_env bindings)

let context ~changed_only ~host_env target label bindings =
  {
    target;
    label;
    env =
      if changed_only then changed_env ~host_env bindings else full_env bindings;
  }

let target_label target =
  Printf.sprintf "%s %s"
    (Manifest.target_kind_name target)
    (Manifest.target_display_name target)

let build_contexts ~workspace_root ~profile ~changed_only ~host_env
    ~include_compiler ~include_actions ~include_preprocessors workspace order =
  let rec loop acc = function
    | [] -> Ok (List.rev acc)
    | target :: rest ->
        let* pipeline =
          Builder.resolve_pipeline ~workspace_root workspace ~profile target
        in
        let label = target_label target in
        let target_env =
          let pipeline : Builder.resolved_pipeline = pipeline in
          pipeline.options.env
        in
        let compiler_contexts =
          if include_compiler then
            [ context ~changed_only ~host_env label "compiler-linker" target_env ]
          else []
        in
        let action_contexts =
          if include_actions then
            List.map
              (fun (action : Manifest.action) ->
                context ~changed_only ~host_env label
                  ("action " ^ Manifest.action_display_name action)
                  (Manifest.merge_env_bindings target_env action.env))
              pipeline.actions
          else []
        in
        let preprocessor_contexts =
          if include_preprocessors then
            List.map
              (fun (tool : Manifest.command_tool) ->
                context ~changed_only ~host_env label
                  ("preprocess " ^ Manifest.command_tool_display_name tool)
                  (Manifest.merge_env_bindings target_env tool.env))
              pipeline.preprocessors
          else []
        in
        let contexts = compiler_contexts @ action_contexts @ preprocessor_contexts in
        loop (List.rev_append contexts acc) rest
  in
  loop [] order

let report ~workspace_root ?profile ?(changed_only = false) workspace subtool
    requested_targets =
  let profile = resolve_profile workspace profile in
  let host_env = host_env () in
  let* requested, runtime_contexts =
    match subtool with
    | Build ->
        let* targets = resolve_named_targets workspace requested_targets in
        Ok
          ( List.map Manifest.target_name targets,
            [] )
    | Action ->
        let* targets = resolve_named_targets workspace requested_targets in
        Ok
          ( List.map Manifest.target_name targets,
            [] )
    | Run ->
        if List.length requested_targets > 1 then
          Error "env run accepts at most one executable target"
        else
          let requested_target =
            match requested_targets with
            | [] -> None
            | [ target ] -> Some target
            | _ -> None
          in
          let* executable = resolve_run_target workspace requested_target in
          Ok
            ( [ executable.name ],
              [ context ~changed_only ~host_env
                  (Printf.sprintf "executable %s"
                     (Manifest.target_display_name (Manifest.Executable executable)))
                  "runtime" [] ] )
    | Test ->
        let* tests = resolve_test_targets workspace requested_targets in
        Ok
          ( List.map (fun (test : Manifest.test_target) -> test.name) tests,
            List.map
              (fun (test : Manifest.test_target) ->
                context ~changed_only ~host_env
                  (Printf.sprintf "test %s"
                     (Manifest.target_display_name (Manifest.Test test)))
                  "runtime" [])
              tests )
    | Bench ->
        let* benches = resolve_bench_targets workspace requested_targets in
        Ok
          ( List.map
              (fun (bench : bench_request) -> bench.executable.name)
              benches,
            List.map
              (fun (bench : bench_request) ->
                context ~changed_only ~host_env
                  (Printf.sprintf "bench %s"
                     (display_name bench.name bench.package_path))
                  "runtime" bench.env)
              benches )
    | Install ->
        let* targets = resolve_install_targets workspace requested_targets in
        Ok (List.map Manifest.target_name targets, [])
  in
  let* order = Builder.resolve_build_order workspace requested in
  let* build_contexts =
    build_contexts ~workspace_root ~profile ~changed_only ~host_env workspace
      ~include_compiler:(subtool <> Action)
      ~include_actions:true
      ~include_preprocessors:(subtool <> Action)
      order
  in
  let contexts = build_contexts @ runtime_contexts in
  let contexts =
    if changed_only then List.filter (fun (context : context) -> context.env <> []) contexts
    else contexts
  in
  Ok
    {
      workspace_name = workspace.Manifest.name;
      subtool;
      profile;
      requested =
        if requested_targets = [] then requested else requested_targets;
      changed_only;
      contexts;
    }

let render_context (context : context) =
  String.concat "\n"
    ([
       "Target: " ^ context.target;
       "Context: " ^ context.label;
     ]
    @ List.map
        (fun (name, value) -> name ^ "=" ^ value)
        context.env)

let render_report (report : report) =
  String.concat "\n\n"
    ([
       String.concat "\n"
         [
           "Workspace: "
           ^
           (match report.workspace_name with
           | Some name -> name
           | None -> "unnamed");
           "Subtool: " ^ subtool_name report.subtool;
           "Profile: " ^ report.profile;
           "View: "
           ^ if report.changed_only then "changed-only" else "full";
           "Requested-targets: "
           ^
           (match report.requested with
           | [] -> "all"
           | requested -> String.concat ", " requested);
         ];
     ]
    @ List.map render_context report.contexts)
    ^ "\n"

let json_string value = "\"" ^ String_util.json_escape value ^ "\""

let json_string_or_null = function
  | Some value -> json_string value
  | None -> "null"

let json_string_list values =
  "[" ^ String.concat ", " (List.map json_string values) ^ "]"

let json_env bindings =
  "{"
  ^
  String.concat ", "
    (List.map
       (fun (name, value) -> json_string name ^ ": " ^ json_string value)
       bindings)
  ^ "}"

let render_context_json (context : context) =
  String.concat "\n"
    [
      "    {";
      "      \"target\": " ^ json_string context.target ^ ",";
      "      \"context\": " ^ json_string context.label ^ ",";
      "      \"env\": " ^ json_env context.env;
      "    }";
    ]

let render_json_report (report : report) =
  let contexts =
    match report.contexts with
    | [] -> "[]"
    | contexts ->
        "[\n"
        ^ String.concat ",\n" (List.map render_context_json contexts)
        ^ "\n  ]"
  in
  String.concat "\n"
    [
      "{";
      "  \"workspace\": " ^ json_string_or_null report.workspace_name ^ ",";
      "  \"subtool\": " ^ json_string (subtool_name report.subtool) ^ ",";
      "  \"profile\": " ^ json_string report.profile ^ ",";
      "  \"view\": "
      ^ json_string
          (if report.changed_only then "changed-only" else "full")
      ^ ",";
      "  \"requested_targets\": " ^ json_string_list report.requested ^ ",";
      "  \"contexts\": " ^ contexts;
      "}";
      "";
    ]
