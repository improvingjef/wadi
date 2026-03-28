type build_options = {
  workspace_dir : string;
  verbose : bool;
  targets : string list;
}

type run_options = {
  workspace_dir : string;
  verbose : bool;
  target : string option;
  args : string list;
}

let usage () =
  String.concat "\n"
    [
      "Usage:";
      "  oasis build [--workspace DIR] [--verbose] [TARGET ...]";
      "  oasis run [--workspace DIR] [--verbose] [TARGET] [-- ARG ...]";
      "";
      "Examples:";
      "  oasis build";
      "  oasis build hello";
      "  oasis build --workspace examples/hello --verbose";
      "  oasis run";
      "  oasis run hello";
      "  oasis run hello -- --loud";
    ]

let build_usage () =
  String.concat "\n"
    [
      "Usage:";
      "  oasis build [--workspace DIR] [--verbose] [TARGET ...]";
      "";
      "Examples:";
      "  oasis build";
      "  oasis build hello";
      "  oasis build --workspace examples/hello --verbose";
    ]

let run_usage () =
  String.concat "\n"
    [
      "Usage:";
      "  oasis run [--workspace DIR] [--verbose] [TARGET] [-- ARG ...]";
      "";
      "Examples:";
      "  oasis run";
      "  oasis run hello";
      "  oasis run hello -- --loud";
      "  oasis run -- --port 8080";
    ]

let report_error message =
  prerr_endline ("oasis: " ^ message);
  1

let parse_build_args args =
  let rec loop options = function
    | [] -> Ok { options with targets = List.rev options.targets }
    | "--workspace" :: dir :: rest ->
        loop { options with workspace_dir = dir } rest
    | "--workspace" :: [] -> Error "--workspace requires a directory"
    | ("--verbose" | "-v") :: rest ->
        loop { options with verbose = true } rest
    | "--help" :: _ -> Error (build_usage ())
    | option :: _ when String_util.starts_with ~prefix:"-" option ->
        Error (Printf.sprintf "unknown option '%s'" option)
    | target :: rest -> loop { options with targets = target :: options.targets } rest
  in
  loop { workspace_dir = "."; verbose = false; targets = [] } args

let parse_run_args args =
  let rec loop options = function
    | [] -> Ok options
    | "--" :: rest -> Ok { options with args = rest }
    | "--workspace" :: dir :: rest ->
        loop { options with workspace_dir = dir } rest
    | "--workspace" :: [] -> Error "--workspace requires a directory"
    | ("--verbose" | "-v") :: rest ->
        loop { options with verbose = true } rest
    | "--help" :: _ -> Error (run_usage ())
    | option :: _ when String_util.starts_with ~prefix:"-" option ->
        Error (Printf.sprintf "unknown option '%s'" option)
    | target :: rest -> (
        match options.target with
        | None -> loop { options with target = Some target } rest
        | Some _ ->
            Error
              "run accepts at most one target before '--'; use '--' to pass \
               program arguments")
  in
  loop { workspace_dir = "."; verbose = false; target = None; args = [] } args

let load_workspace workspace_dir =
  if not (Fs.is_directory workspace_dir) then
    Error
      (Printf.sprintf "workspace directory does not exist: %s" workspace_dir)
  else
    let manifest_path = Filename.concat workspace_dir Manifest.default_filename in
    if not (Fs.exists manifest_path) then
      Error (Printf.sprintf "manifest not found: %s" manifest_path)
    else Manifest.load manifest_path

let executable_names workspace =
  List.filter_map
    (function
      | Manifest.Executable executable -> Some executable.name
      | Manifest.Library _ -> None)
    workspace.Manifest.targets

let resolve_run_target workspace requested_target =
  match requested_target with
  | Some name -> (
      match
        List.find_opt
          (fun target -> Manifest.target_name target = name)
          workspace.Manifest.targets
      with
      | None -> Error (Printf.sprintf "unknown target '%s'" name)
      | Some (Manifest.Library _) ->
          Error
            (Printf.sprintf
               "target '%s' is a library; oasis run only supports executables"
               name)
      | Some (Manifest.Executable executable) -> Ok executable.name)
  | None -> (
      match executable_names workspace with
      | [] -> Error "workspace does not define any executables to run"
      | [ name ] -> Ok name
      | names ->
          Error
            (Printf.sprintf "workspace defines multiple executables; choose one: %s"
               (String.concat ", " names)))

let find_built_executable name artifacts =
  List.find_map
    (function
      | Builder.Built_executable executable when executable.name = name ->
          Some executable.binary
      | _ -> None)
    artifacts

let run_build (options : build_options) =
  match load_workspace options.workspace_dir with
  | Error message -> report_error message
  | Ok workspace -> (
      match
        Builder.build ~workspace_root:options.workspace_dir
          ~verbose:options.verbose ~requested_targets:options.targets workspace
      with
      | Ok _ -> 0
      | Error message -> report_error message)

let run_executable (options : run_options) =
  match load_workspace options.workspace_dir with
  | Error message -> report_error message
  | Ok workspace -> (
      match resolve_run_target workspace options.target with
      | Error message -> report_error message
      | Ok target_name -> (
          match
            Builder.build ~workspace_root:options.workspace_dir
              ~verbose:options.verbose ~requested_targets:[ target_name ]
              workspace
          with
          | Error message -> report_error message
          | Ok result -> (
              match find_built_executable target_name result.Builder.artifacts with
              | None ->
                  report_error
                    (Printf.sprintf
                       "internal error: build completed without executable '%s'"
                       target_name)
              | Some binary ->
                  let outcome =
                    Process.run_status ~verbose:options.verbose binary options.args
                  in
                  outcome.status)))

let run argv =
  match Array.to_list argv with
  | _program :: "build" :: args -> (
      match parse_build_args args with
      | Error message -> report_error message
      | Ok options -> run_build options)
  | _program :: "run" :: args -> (
      match parse_run_args args with
      | Error message -> report_error message
      | Ok options -> run_executable options)
  | _ -> report_error (usage ())
