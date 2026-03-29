type build_options = {
  workspace_dir : string;
  verbose : bool;
  targets : string list;
  backend_request : Toolchain.backend_request;
  profile : string option;
}

type run_options = {
  workspace_dir : string;
  verbose : bool;
  target : string option;
  args : string list;
  backend_request : Toolchain.backend_request;
  profile : string option;
}

type test_options = {
  workspace_dir : string;
  verbose : bool;
  targets : string list;
  backend_request : Toolchain.backend_request;
  profile : string option;
}

type clean_options = {
  workspace_dir : string;
  verbose : bool;
  targets : string list;
  profile : string option;
}

type install_options = {
  workspace_dir : string;
  verbose : bool;
  targets : string list;
  backend_request : Toolchain.backend_request;
  profile : string option;
  prefix : string option;
  destdir : string option;
}

type explain_options = {
  workspace_dir : string;
  targets : string list;
  profile : string option;
  json : bool;
  current : bool;
  backend_request : Toolchain.backend_request;
  backend_specified : bool;
}

type completion_options = { shell : string }

type docs_options = unit

type toolchain_options = { verbose : bool }

type command_result =
  | Exit_code of int
  | Forward_status of Unix.process_status

type option_doc = {
  usage : string;
  flags : string list;
  description : string;
}

type command_doc = {
  name : string;
  summary : string;
  signature : string;
  examples : string list;
  options : option_doc list;
  completion_words : string list;
}

type command =
  | Command : {
      doc : command_doc;
      parse : string list -> ('options, string) result;
      run : 'options -> command_result;
    }
      -> command

let ( let* ) = Result.bind

let workspace_option =
  {
    usage = "--workspace DIR";
    flags = [ "--workspace" ];
    description = "Read the workspace manifest from DIR.";
  }

let profile_option =
  {
    usage = "--profile NAME";
    flags = [ "--profile" ];
    description = "Select the workspace profile to resolve and build.";
  }

let backend_option =
  {
    usage = "--backend auto|native|bytecode";
    flags = [ "--backend" ];
    description = "Choose the compiler backend or let oasis auto-resolve it.";
  }

let verbose_option =
  {
    usage = "--verbose, -v";
    flags = [ "--verbose"; "-v" ];
    description = "Print detailed process execution as commands run.";
  }

let help_option =
  {
    usage = "--help";
    flags = [ "--help" ];
    description = "Print command-specific usage text.";
  }

let prefix_option =
  {
    usage = "--prefix DIR";
    flags = [ "--prefix" ];
    description = "Stage installed files under DIR instead of the default profile root.";
  }

let destdir_option =
  {
    usage = "--destdir DIR";
    flags = [ "--destdir" ];
    description =
      "Prepend DIR to the resolved install prefix for packaging-style staging.";
  }

let json_option =
  {
    usage = "--json";
    flags = [ "--json" ];
    description = "Print machine-readable JSON output instead of the text report.";
  }

let current_option =
  {
    usage = "--current";
    flags = [ "--current" ];
    description =
      "Compute a fresh rebuild explanation from current inputs without compiling or linking.";
  }

let build_doc =
  {
    name = "build";
    summary = "Compile libraries, executables, and tests into predictable artifact roots.";
    signature =
      "oasis build [--workspace DIR] [--profile NAME] [--backend auto|native|bytecode] [--verbose] [TARGET ...]";
    examples =
      [
        "oasis build";
        "oasis build hello";
        "oasis build --workspace examples/hello --profile release --verbose";
      ];
    options = [ workspace_option; profile_option; backend_option; verbose_option; help_option ];
    completion_words = [];
  }

let run_doc =
  {
    name = "run";
    summary = "Build and launch an executable target with exact argv forwarding.";
    signature =
      "oasis run [--workspace DIR] [--profile NAME] [--backend auto|native|bytecode] [--verbose] [TARGET] [-- ARG ...]";
    examples =
      [
        "oasis run";
        "oasis run hello";
        "oasis run --profile release hello -- --loud";
        "oasis run -- --port 8080";
      ];
    options = [ workspace_option; profile_option; backend_option; verbose_option; help_option ];
    completion_words = [];
  }

let test_doc =
  {
    name = "test";
    summary = "Build and execute declared test targets with a direct failure summary.";
    signature =
      "oasis test [--workspace DIR] [--profile NAME] [--backend auto|native|bytecode] [--verbose] [TARGET ...]";
    examples =
      [
        "oasis test";
        "oasis test unit";
        "oasis test unit integration";
        "oasis test --workspace examples/hello --profile ci --verbose";
      ];
    options = [ workspace_option; profile_option; backend_option; verbose_option; help_option ];
    completion_words = [];
  }

let clean_doc =
  {
    name = "clean";
    summary = "Remove the whole artifact tree or only the requested target outputs.";
    signature = "oasis clean [--workspace DIR] [--profile NAME] [--verbose] [TARGET ...]";
    examples =
      [
        "oasis clean";
        "oasis clean hello";
        "oasis clean hello greeting";
        "oasis clean --workspace examples/hello --profile release --verbose";
      ];
    options = [ workspace_option; profile_option; verbose_option; help_option ];
    completion_words = [];
  }

let install_doc =
  {
    name = "install";
    summary = "Stage installable libraries, executables, and metadata under a prefix.";
    signature =
      "oasis install [--workspace DIR] [--profile NAME] [--backend auto|native|bytecode] [--prefix DIR] [--destdir DIR] [--verbose] [TARGET ...]";
    examples =
      [
        "oasis install";
        "oasis install hello";
        "oasis install --prefix _stage hello greeting";
        "oasis install --prefix /usr/local --destdir _pkg hello";
      ];
    options =
      [
        workspace_option;
        profile_option;
        backend_option;
        prefix_option;
        destdir_option;
        verbose_option;
        help_option;
      ];
    completion_words = [];
  }

let docs_doc =
  {
    name = "docs";
    summary = "Render markdown CLI reference directly from the live command table.";
    signature = "oasis docs";
    examples = [ "oasis docs" ];
    options = [ help_option ];
    completion_words = [];
  }

let completion_doc =
  {
    name = "completion";
    summary = "Generate shell completion scripts from the live command table.";
    signature = "oasis completion SHELL";
    examples = [ "oasis completion bash"; "oasis completion zsh"; "oasis completion fish" ];
    options = [ help_option ];
    completion_words = [ "bash"; "zsh"; "fish" ];
  }

let toolchain_doc =
  {
    name = "toolchain";
    summary = "Print the resolved OCaml toolchain, backend, and package search roots.";
    signature = "oasis toolchain";
    examples = [ "oasis toolchain" ];
    options = [ help_option ];
    completion_words = [];
  }

let explain_doc =
  {
    name = "explain";
    summary = "Show why a target rebuilt or reused artifacts and which commands were planned.";
    signature =
      "oasis explain [--workspace DIR] [--profile NAME] [--backend auto|native|bytecode] [--current] [--json] [TARGET ...]";
    examples =
      [
        "oasis explain";
        "oasis explain hello";
        "oasis explain --current hello";
        "oasis explain --current --backend bytecode hello";
        "oasis explain --json hello";
        "oasis explain --profile release greeting hello";
      ];
    options =
      [
        workspace_option;
        profile_option;
        backend_option;
        current_option;
        json_option;
        help_option;
      ];
    completion_words = [];
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

let command_docs =
  [
    build_doc;
    run_doc;
    test_doc;
    clean_doc;
    install_doc;
    docs_doc;
    completion_doc;
    toolchain_doc;
    explain_doc;
  ]

let usage () = render_usage command_docs

let command_usage doc = render_usage [ doc ]

let render_options_markdown options =
  match options with
  | [] -> [ "No options." ]
  | options ->
      List.map
        (fun option_doc ->
          Printf.sprintf "- `%s`: %s" option_doc.usage option_doc.description)
        options

let render_examples_markdown examples =
  List.map (fun example -> "- `" ^ example ^ "`") examples

let render_markdown docs =
  String.concat "\n"
    ([
       "# Oasis CLI";
       "";
       "Generated from the live command table.";
     ]
    @ List.concat_map
        (fun doc ->
          [
            "";
            "## " ^ doc.name;
            "";
            doc.summary;
            "";
            "Usage:";
            "";
            "`" ^ doc.signature ^ "`";
            "";
            "Options:";
          ]
          @ render_options_markdown doc.options
          @ [ ""; "Examples:" ]
          @ render_examples_markdown doc.examples)
        docs
    @ [ "" ])

let command_flag_words doc =
  List.concat_map (fun option_doc -> option_doc.flags) doc.options

let shell_words doc = command_flag_words doc @ doc.completion_words

let shell_word_list words = String.concat " " words

let render_bash_completion docs =
  let render_case doc =
    let option_words = shell_word_list (command_flag_words doc) in
    let completion_words = shell_word_list doc.completion_words in
    String.concat "\n"
      [
        "    " ^ doc.name ^ ")";
        "      if [[ \"$cur\" == -* ]]; then";
        "        COMPREPLY=( $(compgen -W \"" ^ option_words ^ "\" -- \"$cur\") )";
        "      else";
        "        COMPREPLY=( $(compgen -W \"" ^ completion_words ^ "\" -- \"$cur\") )";
        "      fi";
        "      ;;";
      ]
  in
  String.concat "\n"
    ([
       "_oasis() {";
       "  local cur command";
       "  cur=\"${COMP_WORDS[COMP_CWORD]}\"";
       "  if [[ $COMP_CWORD -eq 1 ]]; then";
       "    COMPREPLY=( $(compgen -W \"" ^ shell_word_list (List.map (fun doc -> doc.name) docs)
       ^ "\" -- \"$cur\") )";
       "    return 0";
       "  fi";
       "  command=\"${COMP_WORDS[1]}\"";
       "  case \"$command\" in";
     ]
    @ List.concat_map (fun doc -> [ render_case doc ]) docs
    @ [ "  esac"; "}"; "complete -F _oasis oasis"; "" ])

let render_zsh_completion docs =
  let command_names = shell_word_list (List.map (fun doc -> doc.name) docs) in
  let render_case doc =
    let words = shell_word_list (shell_words doc) in
    String.concat "\n"
      [
        "    " ^ doc.name ^ ")";
        "      _values 'value' " ^ words;
        "      ;;";
      ]
  in
  String.concat "\n"
    ([
       "#compdef oasis";
       "";
       "local context state line";
       "_arguments -C \\";
       "  '1:command:->command' \\";
       "  '*::arg:->args'";
       "";
       "case $state in";
       "  command)";
       "    _values 'command' " ^ command_names;
       "    ;;";
       "  args)";
       "    case $line[1] in";
     ]
    @ List.concat_map (fun doc -> [ render_case doc ]) docs
    @ [ "    esac"; "    ;;"; "esac"; "" ])

let long_flag_name flag =
  if String_util.starts_with ~prefix:"--" flag then
    Some (String.sub flag 2 (String.length flag - 2))
  else None

let short_flag_name flag =
  if String_util.starts_with ~prefix:"-" flag && not (String_util.starts_with ~prefix:"--" flag)
  then Some (String.sub flag 1 (String.length flag - 1))
  else None

let render_fish_option command_name (option_doc : option_doc) =
  let long_flags = List.filter_map long_flag_name option_doc.flags in
  let short_flags = List.filter_map short_flag_name option_doc.flags in
  let flag_parts =
    (match short_flags with
    | short :: _ -> [ "-s"; short ]
    | [] -> [])
    @
    (match long_flags with
    | long :: _ -> [ "-l"; long ]
    | [] -> [])
  in
  if flag_parts = [] then ""
  else
    String.concat " "
      ([ "complete"; "-c"; "oasis"; "-n"; "__fish_seen_subcommand_from " ^ command_name ]
      @ flag_parts
      @ [ "-d"; String_util.shell_quote option_doc.description ])

let render_fish_completion docs =
  let command_names = shell_word_list (List.map (fun doc -> doc.name) docs) in
  String.concat "\n"
    ([
       "complete -c oasis -f -n '__fish_use_subcommand' -a '" ^ command_names ^ "'";
     ]
    @ List.concat_map
        (fun doc ->
          let option_lines =
            List.filter_map
              (fun option_doc ->
                let line = render_fish_option doc.name option_doc in
                if line = "" then None else Some line)
              doc.options
          in
          let word_line =
            match doc.completion_words with
            | [] -> []
            | words ->
                [
                  "complete -c oasis -f -n '__fish_seen_subcommand_from "
                  ^ doc.name
                  ^ "' -a '"
                  ^ shell_word_list words
                  ^ "'";
                ]
          in
          option_lines @ word_line)
        docs
    @ [ "" ])

let completion_script shell docs =
  match shell with
  | "bash" -> Ok (render_bash_completion docs)
  | "zsh" -> Ok (render_zsh_completion docs)
  | "fish" -> Ok (render_fish_completion docs)
  | shell ->
      Error
        (Printf.sprintf "unknown shell '%s'; expected bash, fish, or zsh" shell)

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
    | "--profile" :: profile :: rest ->
        loop { options with profile = Some profile } rest
    | "--profile" :: [] -> Error "--profile requires a name"
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
      profile = None;
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
    | "--profile" :: profile :: rest ->
        loop { options with profile = Some profile } rest
    | "--profile" :: [] -> Error "--profile requires a name"
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
      profile = None;
    }
    args

let parse_test_args (args : string list) : (test_options, string) result =
  let* default_backend_request = default_backend_request () in
  let rec loop (options : test_options) = function
    | [] -> Ok { options with targets = List.rev options.targets }
    | "--workspace" :: dir :: rest ->
        loop { options with workspace_dir = dir } rest
    | "--workspace" :: [] -> Error "--workspace requires a directory"
    | "--profile" :: profile :: rest ->
        loop { options with profile = Some profile } rest
    | "--profile" :: [] -> Error "--profile requires a name"
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
      profile = None;
    }
    args

let parse_clean_args (args : string list) : (clean_options, string) result =
  let rec loop (options : clean_options) = function
    | [] -> Ok { options with targets = List.rev options.targets }
    | "--workspace" :: dir :: rest ->
        loop { options with workspace_dir = dir } rest
    | "--workspace" :: [] -> Error "--workspace requires a directory"
    | "--profile" :: profile :: rest ->
        loop { options with profile = Some profile } rest
    | "--profile" :: [] -> Error "--profile requires a name"
    | ("--verbose" | "-v") :: rest ->
        loop { options with verbose = true } rest
    | "--help" :: _ -> Error (command_usage clean_doc)
    | option :: _ when String_util.starts_with ~prefix:"-" option ->
        Error (Printf.sprintf "unknown option '%s'" option)
    | target :: rest -> loop { options with targets = target :: options.targets } rest
  in
  loop { workspace_dir = "."; verbose = false; targets = []; profile = None } args

let parse_toolchain_args args =
  match args with
  | [] -> Ok { verbose = false }
  | [ "--help" ] -> Error (command_usage toolchain_doc)
  | option :: _ when String_util.starts_with ~prefix:"-" option ->
      Error (Printf.sprintf "unknown option '%s'" option)
  | _ -> Error "toolchain does not accept positional arguments"

let parse_docs_args args =
  match args with
  | [] -> Ok ()
  | [ "--help" ] -> Error (command_usage docs_doc)
  | option :: _ when String_util.starts_with ~prefix:"-" option ->
      Error (Printf.sprintf "unknown option '%s'" option)
  | _ -> Error "docs does not accept positional arguments"

let parse_completion_args args =
  match args with
  | [ "--help" ] -> Error (command_usage completion_doc)
  | [ shell ] -> Ok { shell }
  | [] -> Error "completion requires a shell name"
  | option :: _ when String_util.starts_with ~prefix:"-" option ->
      Error (Printf.sprintf "unknown option '%s'" option)
  | _ -> Error "completion accepts exactly one shell name"

let parse_install_args (args : string list) : (install_options, string) result =
  let* default_backend_request = default_backend_request () in
  let rec loop (options : install_options) = function
    | [] -> Ok { options with targets = List.rev options.targets }
    | "--workspace" :: dir :: rest ->
        loop { options with workspace_dir = dir } rest
    | "--workspace" :: [] -> Error "--workspace requires a directory"
    | "--profile" :: profile :: rest ->
        loop { options with profile = Some profile } rest
    | "--profile" :: [] -> Error "--profile requires a name"
    | "--backend" :: backend :: rest ->
        let* backend_request = Toolchain.parse_backend_request backend in
        loop { options with backend_request } rest
    | "--backend" :: [] ->
        Error "--backend requires auto, native, or bytecode"
    | "--prefix" :: prefix :: rest ->
        loop { options with prefix = Some prefix } rest
    | "--prefix" :: [] -> Error "--prefix requires a directory"
    | "--destdir" :: destdir :: rest ->
        loop { options with destdir = Some destdir } rest
    | "--destdir" :: [] -> Error "--destdir requires a directory"
    | ("--verbose" | "-v") :: rest ->
        loop { options with verbose = true } rest
    | "--help" :: _ -> Error (command_usage install_doc)
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
      profile = None;
      prefix = None;
      destdir = None;
    }
    args

let parse_explain_args (args : string list) : (explain_options, string) result =
  let* default_backend_request = default_backend_request () in
  let rec loop (options : explain_options) = function
    | [] ->
        if options.backend_specified && not options.current then
          Error "--backend is only supported with --current"
        else Ok { options with targets = List.rev options.targets }
    | "--workspace" :: dir :: rest ->
        loop { options with workspace_dir = dir } rest
    | "--workspace" :: [] -> Error "--workspace requires a directory"
    | "--profile" :: profile :: rest ->
        loop { options with profile = Some profile } rest
    | "--profile" :: [] -> Error "--profile requires a name"
    | "--backend" :: backend :: rest ->
        let* backend_request = Toolchain.parse_backend_request backend in
        loop { options with backend_request; backend_specified = true } rest
    | "--backend" :: [] ->
        Error "--backend requires auto, native, or bytecode"
    | "--current" :: rest -> loop { options with current = true } rest
    | "--json" :: rest -> loop { options with json = true } rest
    | "--help" :: _ -> Error (command_usage explain_doc)
    | option :: _ when String_util.starts_with ~prefix:"-" option ->
        Error (Printf.sprintf "unknown option '%s'" option)
    | target :: rest -> loop { options with targets = target :: options.targets } rest
  in
  loop
    {
      workspace_dir = ".";
      targets = [];
      profile = None;
      json = false;
      current = false;
      backend_request = default_backend_request;
      backend_specified = false;
    }
    args

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

let resolve_profile workspace profile =
  match profile with
  | Some profile when String.trim profile <> "" -> profile
  | Some _ | None -> Manifest.default_profile workspace

let resolve_explain_targets workspace requested_targets =
  let requested_targets = String_util.dedup_preserve requested_targets in
  if requested_targets = [] then Ok workspace.Manifest.targets
  else
    let index = Hashtbl.create (List.length workspace.Manifest.targets) in
    List.iter
      (fun target ->
        Hashtbl.replace index (Manifest.target_name target) target)
      workspace.Manifest.targets;
    let rec loop acc = function
      | [] -> Ok (List.rev acc)
      | name :: rest -> (
          match Hashtbl.find_opt index name with
          | Some target -> loop (target :: acc) rest
          | None -> Error (Printf.sprintf "unknown target '%s'" name))
    in
    loop [] requested_targets

let run_build (options : build_options) =
  match load_workspace options.workspace_dir with
  | Error message -> report_error message
  | Ok workspace -> (
      match
        Builder.build ~workspace_root:options.workspace_dir
          ~verbose:options.verbose ~requested_targets:options.targets
          ~backend_request:options.backend_request ?profile:options.profile
          workspace
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
              ~backend_request:options.backend_request ?profile:options.profile
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
                  Forward_status outcome.Process.unix_status)))

let run_tests (options : test_options) =
  match load_workspace options.workspace_dir with
  | Error message -> report_error message
  | Ok workspace -> (
      match
        Tester.run ~workspace_root:options.workspace_dir ~verbose:options.verbose
          ~backend_request:options.backend_request
          ?profile:options.profile ~requested_targets:options.targets workspace
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
        ~profile:options.profile ~verbose:options.verbose
    with
    | Ok () -> Exit_code 0
    | Error message -> report_error message)
  else
    match load_workspace options.workspace_dir with
    | Error message -> report_error message
    | Ok workspace -> (
        match
          Cleaner.clean_targets ~workspace_root:options.workspace_dir
            ~profile:options.profile ~verbose:options.verbose
            ~requested_targets:options.targets
            workspace
        with
        | Ok () -> Exit_code 0
        | Error message -> report_error message)

let run_install (options : install_options) =
  match load_workspace options.workspace_dir with
  | Error message -> report_error message
  | Ok workspace -> (
      match
        Installer.install ~workspace_root:options.workspace_dir
          ~verbose:options.verbose ~backend_request:options.backend_request
          ?profile:options.profile ?prefix:options.prefix ?destdir:options.destdir
          ~requested_targets:options.targets workspace
      with
      | Ok status -> Exit_code status
      | Error message -> report_error message)

let run_docs (_options : docs_options) =
  print_string (render_markdown command_docs);
  Exit_code 0

let run_completion (options : completion_options) =
  match completion_script options.shell command_docs with
  | Ok script ->
      print_string script;
      Exit_code 0
  | Error message -> report_error message

let run_toolchain (_options : toolchain_options) =
  Toolchain.inspect () |> Toolchain.render_report |> print_endline;
  Exit_code 0

let run_explain (options : explain_options) =
  match load_workspace options.workspace_dir with
  | Error message -> report_error message
  | Ok workspace -> (
      match resolve_explain_targets workspace options.targets with
      | Error message -> report_error message
      | Ok targets ->
          let workspace_root = Fs.realpath options.workspace_dir in
          let profile = resolve_profile workspace options.profile in
          let render_reports reports =
            if options.json then
              match List.rev reports with
              | [] -> "[]"
              | [ report ] -> String.trim report
              | reports ->
                  "[\n" ^ String.concat ",\n" (List.map String.trim reports) ^ "\n]"
            else String.concat "\n\n" (List.rev reports)
          in
          if options.current then
            match
              Builder.explain_current ~workspace_root
                ~requested_targets:(List.map Manifest.target_name targets)
                ~backend_request:options.backend_request
                ?profile:options.profile workspace
            with
            | Error message -> report_error message
            | Ok reports ->
                let payloads =
                  List.rev_map
                    (fun (report : Builder.explain_report) ->
                      if options.json then report.json_report else report.report)
                    reports
                in
                print_endline (render_reports payloads);
                Exit_code 0
          else
            let rec loop reports = function
              | [] ->
                  print_endline (render_reports reports);
                  Exit_code 0
              | target :: rest ->
                  let out_dir =
                    Layout.target_out_dir ~profile workspace_root target
                  in
                  let report_path =
                    if options.json then Layout.explain_json_path out_dir
                    else Layout.explain_path out_dir
                  in
                  if Fs.exists report_path then
                    loop (Explain.load_report report_path :: reports) rest
                  else
                    report_error
                      (Printf.sprintf
                         "no explain data for %s '%s' in profile '%s'; build it \
                          first"
                         (Manifest.target_kind_name target)
                         (Manifest.target_name target) profile)
            in
            loop [] targets)

let commands =
  [
    Command { doc = build_doc; parse = parse_build_args; run = run_build };
    Command { doc = run_doc; parse = parse_run_args; run = run_executable };
    Command { doc = test_doc; parse = parse_test_args; run = run_tests };
    Command { doc = clean_doc; parse = parse_clean_args; run = run_clean };
    Command { doc = install_doc; parse = parse_install_args; run = run_install };
    Command { doc = docs_doc; parse = parse_docs_args; run = run_docs };
    Command
      { doc = completion_doc; parse = parse_completion_args; run = run_completion };
    Command
      { doc = toolchain_doc; parse = parse_toolchain_args; run = run_toolchain };
    Command { doc = explain_doc; parse = parse_explain_args; run = run_explain };
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
