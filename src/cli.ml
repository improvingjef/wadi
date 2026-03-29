type build_options = {
  workspace_dir : string;
  verbose : bool;
  targets : string list;
  backend_request : Toolchain.backend_request;
}

type run_options = {
  workspace_dir : string;
  verbose : bool;
  target : string option;
  args : string list;
  backend_request : Toolchain.backend_request;
}

type test_options = {
  workspace_dir : string;
  verbose : bool;
  targets : string list;
  backend_request : Toolchain.backend_request;
}

type clean_options = {
  workspace_dir : string;
  verbose : bool;
  targets : string list;
}

type toolchain_options = { verbose : bool }

type command_result =
  | Exit_code of int
  | Forward_status of Unix.process_status

type command_doc = {
  name : string;
  signature : string;
  examples : string list;
}

type command =
  | Command : {
      doc : command_doc;
      parse : string list -> ('options, string) result;
      run : 'options -> command_result;
    }
      -> command

let ( let* ) = Result.bind

let build_doc =
  {
    name = "build";
    signature =
      "oasis build [--workspace DIR] [--backend auto|native|bytecode] [--verbose] [TARGET ...]";
    examples =
      [
        "oasis build";
        "oasis build hello";
        "oasis build --workspace examples/hello --verbose";
      ];
  }

let run_doc =
  {
    name = "run";
    signature =
      "oasis run [--workspace DIR] [--backend auto|native|bytecode] [--verbose] [TARGET] [-- ARG ...]";
    examples =
      [
        "oasis run";
        "oasis run hello";
        "oasis run hello -- --loud";
        "oasis run -- --port 8080";
      ];
  }

let test_doc =
  {
    name = "test";
    signature =
      "oasis test [--workspace DIR] [--backend auto|native|bytecode] [--verbose] [TARGET ...]";
    examples =
      [
        "oasis test";
        "oasis test unit";
        "oasis test unit integration";
        "oasis test --workspace examples/hello --verbose";
      ];
  }

let clean_doc =
  {
    name = "clean";
    signature = "oasis clean [--workspace DIR] [--verbose] [TARGET ...]";
    examples =
      [
        "oasis clean";
        "oasis clean hello";
        "oasis clean hello greeting";
        "oasis clean --workspace examples/hello --verbose";
      ];
  }

let toolchain_doc =
  {
    name = "toolchain";
    signature = "oasis toolchain";
    examples = [ "oasis toolchain" ];
  }

let render_usage docs =
  String.concat "\n"
    ([
       "Usage:";
     ]
    @ List.map (fun doc -> "  " ^ doc.signature) docs
    @ [
        "";
        "Examples:";
      ]
    @ List.concat_map
        (fun doc -> List.map (fun example -> "  " ^ example) doc.examples)
        docs)

let command_docs = [ build_doc; run_doc; test_doc; clean_doc; toolchain_doc ]

let usage () = render_usage command_docs

let command_usage doc = render_usage [ doc ]

let report_error message =
  prerr_endline ("oasis: " ^ message);
  Exit_code 1

let default_backend_request () = Toolchain.env_backend_request ()

let parse_build_args (args : string list) : (build_options, string) result =
  let* default_backend_request = default_backend_request () in
  let rec loop (options : build_options) = function
    | [] -> Ok { options with targets = List.rev options.targets }
    | "--workspace" :: dir :: rest ->
        loop { options with workspace_dir = dir } rest
    | "--workspace" :: [] -> Error "--workspace requires a directory"
    | "--backend" :: backend :: rest ->
        let* backend_request = Toolchain.parse_backend_request backend in
        loop { options with backend_request } rest
    | "--backend" :: [] ->
        Error "--backend requires auto, native, or bytecode"
    | ("--verbose" | "-v") :: rest ->
        loop { options with verbose = true } rest
    | "--help" :: _ -> Error (command_usage build_doc)
    | option :: _ when String_util.starts_with ~prefix:"-" option ->
        Error (Printf.sprintf "unknown option '%s'" option)
    | target :: rest -> loop { options with targets = target :: options.targets } rest
  in
  loop
    {
      workspace_dir = ".";
      verbose = false;
      targets = [];
      backend_request = default_backend_request;
    }
    args

let parse_run_args args =
  let* default_backend_request = default_backend_request () in
  let rec loop options = function
    | [] -> Ok { options with args = options.args }
    | "--" :: rest -> Ok { options with args = rest }
    | "--workspace" :: dir :: rest ->
        loop { options with workspace_dir = dir } rest
    | "--workspace" :: [] -> Error "--workspace requires a directory"
    | "--backend" :: backend :: rest ->
        let* backend_request = Toolchain.parse_backend_request backend in
        loop { options with backend_request } rest
    | "--backend" :: [] ->
        Error "--backend requires auto, native, or bytecode"
    | ("--verbose" | "-v") :: rest ->
        loop { options with verbose = true } rest
    | "--help" :: _ -> Error (command_usage run_doc)
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
  loop
    {
      workspace_dir = ".";
      verbose = false;
      target = None;
      args = [];
      backend_request = default_backend_request;
    }
    args

let parse_test_args (args : string list) : (test_options, string) result =
  let* default_backend_request = default_backend_request () in
  let rec loop (options : test_options) = function
    | [] -> Ok { options with targets = List.rev options.targets }
    | "--workspace" :: dir :: rest ->
        loop { options with workspace_dir = dir } rest
    | "--workspace" :: [] -> Error "--workspace requires a directory"
    | "--backend" :: backend :: rest ->
        let* backend_request = Toolchain.parse_backend_request backend in
        loop { options with backend_request } rest
    | "--backend" :: [] ->
        Error "--backend requires auto, native, or bytecode"
    | ("--verbose" | "-v") :: rest ->
        loop { options with verbose = true } rest
    | "--help" :: _ -> Error (command_usage test_doc)
    | option :: _ when String_util.starts_with ~prefix:"-" option ->
        Error (Printf.sprintf "unknown option '%s'" option)
    | target :: rest -> loop { options with targets = target :: options.targets } rest
  in
  loop
    {
      workspace_dir = ".";
      verbose = false;
      targets = [];
      backend_request = default_backend_request;
    }
    args

let parse_clean_args (args : string list) : (clean_options, string) result =
  let rec loop (options : clean_options) = function
    | [] -> Ok { options with targets = List.rev options.targets }
    | "--workspace" :: dir :: rest ->
        loop { options with workspace_dir = dir } rest
    | "--workspace" :: [] -> Error "--workspace requires a directory"
    | ("--verbose" | "-v") :: rest ->
        loop { options with verbose = true } rest
    | "--help" :: _ -> Error (command_usage clean_doc)
    | option :: _ when String_util.starts_with ~prefix:"-" option ->
        Error (Printf.sprintf "unknown option '%s'" option)
    | target :: rest -> loop { options with targets = target :: options.targets } rest
  in
  loop { workspace_dir = "."; verbose = false; targets = [] } args

let parse_toolchain_args args =
  match args with
  | [] -> Ok { verbose = false }
  | [ "--help" ] -> Error (command_usage toolchain_doc)
  | option :: _ when String_util.starts_with ~prefix:"-" option ->
      Error (Printf.sprintf "unknown option '%s'" option)
  | _ -> Error "toolchain does not accept positional arguments"

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
      | Manifest.Library _ | Manifest.Test _ -> None)
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
      | Some (Manifest.Test _) ->
          Error
            (Printf.sprintf
               "target '%s' is a test; oasis run only supports executables"
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
          ~verbose:options.verbose ~requested_targets:options.targets
          ~backend_request:options.backend_request workspace
      with
      | Ok _ -> Exit_code 0
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
              ~backend_request:options.backend_request workspace
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
                  Forward_status outcome.Process.unix_status)))

let run_tests (options : test_options) =
  match load_workspace options.workspace_dir with
  | Error message -> report_error message
  | Ok workspace -> (
      match
        Tester.run ~workspace_root:options.workspace_dir ~verbose:options.verbose
          ~backend_request:options.backend_request
          ~requested_targets:options.targets workspace
      with
      | Ok status -> Exit_code status
      | Error message -> report_error message)

let run_clean (options : clean_options) =
  if not (Fs.is_directory options.workspace_dir) then
    report_error
      (Printf.sprintf "workspace directory does not exist: %s"
         options.workspace_dir)
  else if options.targets = [] then (
    match
      Cleaner.clean_workspace ~workspace_root:options.workspace_dir
        ~verbose:options.verbose
    with
    | Ok () -> Exit_code 0
    | Error message -> report_error message)
  else
    match load_workspace options.workspace_dir with
    | Error message -> report_error message
    | Ok workspace -> (
        match
          Cleaner.clean_targets ~workspace_root:options.workspace_dir
            ~verbose:options.verbose ~requested_targets:options.targets
            workspace
        with
        | Ok () -> Exit_code 0
        | Error message -> report_error message)

let run_toolchain (_options : toolchain_options) =
  Toolchain.inspect () |> Toolchain.render_report |> print_endline;
  Exit_code 0

let commands =
  [
    Command { doc = build_doc; parse = parse_build_args; run = run_build };
    Command { doc = run_doc; parse = parse_run_args; run = run_executable };
    Command { doc = test_doc; parse = parse_test_args; run = run_tests };
    Command { doc = clean_doc; parse = parse_clean_args; run = run_clean };
    Command
      { doc = toolchain_doc; parse = parse_toolchain_args; run = run_toolchain };
  ]

let dispatch_command command args =
  match command with
  | Command { parse; run; _ } -> (
      match parse args with
      | Error message -> report_error message
      | Ok options -> run options)

let find_command name =
  List.find_opt
    (function
      | Command { doc; _ } -> doc.name = name)
    commands

let run argv =
  match Array.to_list argv with
  | _program :: command_name :: args -> (
      match find_command command_name with
      | Some command -> dispatch_command command args
      | None -> report_error (usage ()))
  | _ -> report_error (usage ())
