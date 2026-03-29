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

type graph_options = {
  workspace_dir : string;
  targets : string list;
  backend_request : Toolchain.backend_request;
  profile : string option;
}

type deps_options = {
  workspace_dir : string;
  targets : string list;
}

type env_options = {
  workspace_dir : string;
  profile : string option;
  subtool : Env_report.subtool;
  targets : string list;
  json : bool;
}

type repl_options = {
  workspace_dir : string;
  verbose : bool;
  target : string option;
  args : string list;
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

type completion_mode =
  | Render_script of string
  | Query of {
      previous : string list;
      current : string;
      describe : bool;
    }

type completion_options = {
  workspace_dir : string;
  mode : completion_mode;
}

type docs_options = unit

type toolchain_options = { verbose : bool }

type migrate_options = {
  workspace_dir : string;
  output_path : string option;
  stdout : bool;
  force : bool;
}

type command_result =
  | Exit_code of int
  | Forward_status of Unix.process_status

type completion_candidate = {
  value : string;
  hint : string option;
}

type completion_response =
  | Completion_candidates of completion_candidate list
  | Complete_directories

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

let output_option =
  {
    usage = "--output PATH";
    flags = [ "--output" ];
    description = "Write the generated manifest to PATH instead of oasis.toml.";
  }

let stdout_option =
  {
    usage = "--stdout";
    flags = [ "--stdout" ];
    description = "Print the generated manifest instead of writing a file.";
  }

let force_option =
  {
    usage = "--force";
    flags = [ "--force" ];
    description = "Overwrite an existing output path.";
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
      "Compute a fresh rebuild explanation from current inputs without compiling, linking, or materializing generated sources.";
  }

let backend_completion_words = [ "auto"; "native"; "bytecode" ]

let completion_protocol_name = "__oasis_completion"

let completion_protocol_version = "1"

let sanitize_completion_field text =
  let buffer = Buffer.create (String.length text) in
  String.iter
    (function
      | '\t' | '\n' | '\r' -> Buffer.add_char buffer ' '
      | ch -> Buffer.add_char buffer ch)
    text;
  Buffer.contents buffer

let completion_protocol_header kind =
  String.concat "\t"
    [ completion_protocol_name; completion_protocol_version; kind ]

let completion_candidate_line ?hint value =
  match hint with
  | Some hint ->
      String.concat "\t"
        [
          "candidate";
          sanitize_completion_field value;
          sanitize_completion_field hint;
        ]
  | None -> String.concat "\t" [ "candidate"; sanitize_completion_field value ]

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

let graph_doc =
  {
    name = "graph";
    summary = "Show target build order, module order, and pipeline shape without compiling.";
    signature =
      "oasis graph [--workspace DIR] [--profile NAME] [--backend auto|native|bytecode] [TARGET ...]";
    examples =
      [
        "oasis graph";
        "oasis graph hello";
        "oasis graph --profile release --backend bytecode hello";
      ];
    options = [ workspace_option; profile_option; backend_option; help_option ];
    completion_words = [];
  }

let deps_doc =
  {
    name = "deps";
    summary = "Resolve transitive external package requirements for selected targets.";
    signature = "oasis deps [--workspace DIR] [TARGET ...]";
    examples =
      [
        "oasis deps";
        "oasis deps hello";
        "oasis deps --workspace examples/hello greeting hello";
      ];
    options = [ workspace_option; help_option ];
    completion_words = [];
  }

let env_doc =
  {
    name = "env";
    summary =
      "Print the exact subprocess environment a build, run, test, or install step would inherit.";
    signature =
      "oasis env [--workspace DIR] [--profile NAME] [--json] SUBTOOL [TARGET ...]";
    examples =
      [
        "oasis env build";
        "oasis env --profile release build demo";
        "oasis env --json run demo";
        "oasis env run demo";
        "oasis env test unit";
      ];
    options = [ workspace_option; profile_option; json_option; help_option ];
    completion_words = [ "build"; "run"; "test"; "install" ];
  }

let repl_doc =
  {
    name = "repl";
    summary =
      "Build a bytecode toplevel with workspace libraries and packages already wired in.";
    signature =
      "oasis repl [--workspace DIR] [--profile NAME] [--verbose] [TARGET] [-- OCAML_ARG ...]";
    examples =
      [
        "oasis repl core";
        "oasis repl demo";
        "oasis repl --profile release core -- -noinit -noprompt";
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
    signature = "oasis completion [--workspace DIR] SHELL";
    examples = [ "oasis completion bash"; "oasis completion zsh"; "oasis completion fish" ];
    options = [ workspace_option; help_option ];
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

let migrate_doc =
  {
    name = "migrate";
    summary =
      "Scan dune files and emit a first-pass oasis.toml manifest with review comments.";
    signature =
      "oasis migrate [--workspace DIR] [--output PATH] [--stdout] [--force]";
    examples =
      [
        "oasis migrate --stdout";
        "oasis migrate --workspace ../old-project";
        "oasis migrate --output converted.oasis.toml --force";
      ];
    options =
      [ workspace_option; output_option; stdout_option; force_option; help_option ];
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
    graph_doc;
    run_doc;
    test_doc;
    clean_doc;
    deps_doc;
    env_doc;
    repl_doc;
    install_doc;
    docs_doc;
    completion_doc;
    toolchain_doc;
    explain_doc;
    migrate_doc;
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

let completion_query_command ?workspace_dir ?(describe = false) () =
  "oasis completion"
  ^
  (match workspace_dir with
  | Some dir -> " --workspace " ^ String_util.shell_quote dir
  | None -> "")
  ^ " --query"
  ^ if describe then " --describe" else ""

let render_bash_completion ?workspace_dir () =
  let query = completion_query_command ?workspace_dir ~describe:true () in
  String.concat "\n"
    [
      "_oasis_query() {";
      "  " ^ query ^ " --current \"$1\" -- \"${@:2}\" 2>/dev/null";
      "}";
      "_oasis_show_descriptions() {";
      "  local line";
      "  while IFS= read -r line; do";
      "    [[ -n \"$line\" ]] || continue";
      "    [[ \"$line\" == *$'\\t'* ]] || continue";
      "    printf '%s\\n' \"$line\" >&2";
      "  done";
      "}";
      "_oasis() {";
      "  local cur response first_line body record protocol version kind value description";
      "  local -a previous values described";
      "  cur=\"${COMP_WORDS[COMP_CWORD]}\"";
      "  previous=(\"${COMP_WORDS[@]:1:$((COMP_CWORD-1))}\")";
      "  response=\"$(_oasis_query \"$cur\" \"${previous[@]}\")\"";
      "  first_line=\"${response%%$'\\n'*}\"";
      "  IFS=$'\\t' read -r protocol version kind <<< \"$first_line\"";
      "  [[ \"$protocol\" == "
      ^ String_util.shell_quote completion_protocol_name
      ^ " ]] || return";
      "  [[ \"$version\" == "
      ^ String_util.shell_quote completion_protocol_version
      ^ " ]] || return";
      "  if [[ \"$kind\" == directories ]]; then";
      "    compopt -o filenames 2>/dev/null";
      "    compgen -V COMPREPLY -d -- \"$cur\"";
      "    return";
      "  fi";
      "  if [[ \"$response\" == *$'\\n'* ]]; then";
      "    body=\"${response#*$'\\n'}\"";
      "  else";
      "    body=''";
      "  fi";
      "  while IFS=$'\\t' read -r record value description; do";
      "    [[ \"$record\" == candidate ]] || continue";
      "    [[ -n \"$value\" ]] || continue";
      "    values+=(\"$value\")";
      "    if [[ -n \"$description\" ]]; then";
      "      described+=(\"$value\"$'\\t'$description)";
      "    fi";
      "  done <<< \"$body\"";
      "  compgen -V COMPREPLY -W \"$(printf '%s\\n' \"${values[@]}\")\" -- \"$cur\"";
      "  if [[ ${#described[@]} -gt 0 && ${#COMPREPLY[@]} -gt 1 ]]; then";
      "    _oasis_show_descriptions <<< \"$(printf '%s\\n' \"${described[@]}\")\"";
      "  fi";
      "}";
      "complete -F _oasis oasis";
      "";
    ]

let render_zsh_completion ?workspace_dir () =
  let query = completion_query_command ?workspace_dir ~describe:true () in
  String.concat "\n"
    [
      "#compdef oasis";
      "";
      "_oasis_query() {";
      "  " ^ query ^ " --current \"$1\" -- \"${@:2}\" 2>/dev/null";
      "}";
      "_oasis() {";
      "  local current response first_line body";
      "  local record protocol version kind value description";
      "  local -a previous suggestions";
      "  current=\"${words[CURRENT]}\"";
      "  previous=(\"${(@)words[2,CURRENT-1]}\")";
      "  response=\"$(_oasis_query \"$current\" \"${previous[@]}\")\"";
      "  first_line=\"${response%%$'\\n'*}\"";
      "  IFS=$'\\t' read -r protocol version kind <<< \"$first_line\"";
      "  [[ \"$protocol\" == "
      ^ String_util.shell_quote completion_protocol_name
      ^ " ]] || return";
      "  [[ \"$version\" == "
      ^ String_util.shell_quote completion_protocol_version
      ^ " ]] || return";
      "  if [[ \"$kind\" == directories ]]; then";
      "    _files -/";
      "    return";
      "  fi";
      "  if [[ \"$response\" == *$'\\n'* ]]; then";
      "    body=\"${response#*$'\\n'}\"";
      "  else";
      "    body=''";
      "  fi";
      "  while IFS=$'\\t' read -r record value description; do";
      "    [[ \"$record\" == candidate ]] || continue";
      "    if [[ -n \"$description\" ]]; then";
      "      suggestions+=(\"${value}:${description}\")";
      "    elif [[ -n \"$value\" ]]; then";
      "      suggestions+=(\"${value}\")";
      "    fi";
      "  done <<< \"$body\"";
      "  _describe 'value' suggestions";
      "}";
      "compdef _oasis oasis";
      "";
    ]

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

let render_fish_completion ?workspace_dir () =
  let query = completion_query_command ?workspace_dir ~describe:true () in
  String.concat "\n"
    [
      "function __oasis_complete";
      "  set -l previous (commandline -opc)";
      "  if test (count $previous) -gt 0";
      "    set previous $previous[2..-1]";
      "  else";
      "    set previous";
      "  end";
      "  set -l current (commandline -ct)";
      "  set -l response (" ^ query ^ " --current \"$current\" -- $previous 2>/dev/null)";
      "  set -l tab (printf '\\t')";
      "  if test (count $response) -eq 0";
      "    return";
      "  end";
      "  set -l header (string split $tab -- $response[1])";
      "  if test (count $header) -lt 3";
      "    return";
      "  end";
      "  if test \"$header[1]\" != "
      ^ String_util.shell_quote completion_protocol_name
      ^ " -o \"$header[2]\" != "
      ^ String_util.shell_quote completion_protocol_version
      ^ "";
      "    return";
      "  end";
      "  if test \"$header[3]\" = directories";
      "    __fish_complete_directories \"$current\"";
      "    return";
      "  end";
      "  for line in $response[2..-1]";
      "    set -l fields (string split $tab -- $line)";
      "    if test (count $fields) -lt 2 -o \"$fields[1]\" != candidate";
      "      continue";
      "    end";
      "    if test (count $fields) -ge 3";
      "      printf '%s\\t%s\\n' \"$fields[2]\" \"$fields[3]\"";
      "    else";
      "      printf '%s\\n' \"$fields[2]\"";
      "    end";
      "  end";
      "end";
      "complete -c oasis -f -a '(__oasis_complete)'";
      "";
    ]

let completion_script ?workspace_dir shell =
  match shell with
  | "bash" -> Ok (render_bash_completion ?workspace_dir ())
  | "zsh" -> Ok (render_zsh_completion ?workspace_dir ())
  | "fish" -> Ok (render_fish_completion ?workspace_dir ())
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

let parse_run_args (args : string list) : (run_options, string) result =
  let* default_backend_request = default_backend_request () in
  let rec loop (options : run_options) = function
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

let parse_graph_args (args : string list) : (graph_options, string) result =
  let* default_backend_request = default_backend_request () in
  let rec loop (options : graph_options) = function
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
    | "--help" :: _ -> Error (command_usage graph_doc)
    | option :: _ when String_util.starts_with ~prefix:"-" option ->
        Error (Printf.sprintf "unknown option '%s'" option)
    | target :: rest -> loop { options with targets = target :: options.targets } rest
  in
  loop
    {
      workspace_dir = ".";
      targets = [];
      backend_request = default_backend_request;
      profile = None;
    }
    args

let parse_deps_args (args : string list) : (deps_options, string) result =
  let rec loop (options : deps_options) = function
    | [] -> Ok { options with targets = List.rev options.targets }
    | "--workspace" :: dir :: rest ->
        loop { options with workspace_dir = dir } rest
    | "--workspace" :: [] -> Error "--workspace requires a directory"
    | "--help" :: _ -> Error (command_usage deps_doc)
    | option :: _ when String_util.starts_with ~prefix:"-" option ->
        Error (Printf.sprintf "unknown option '%s'" option)
    | target :: rest -> loop { options with targets = target :: options.targets } rest
  in
  loop { workspace_dir = "."; targets = [] } args

let parse_env_args (args : string list) : (env_options, string) result =
  let rec loop workspace_dir profile json subtool targets = function
    | [] -> (
        match subtool with
        | None -> Error "env requires a subtool name"
        | Some subtool ->
            Ok
              {
                workspace_dir;
                profile;
                subtool;
                targets = List.rev targets;
                json;
              } )
    | "--workspace" :: dir :: rest -> loop dir profile json subtool targets rest
    | "--workspace" :: [] -> Error "--workspace requires a directory"
    | "--profile" :: value :: rest ->
        loop workspace_dir (Some value) json subtool targets rest
    | "--profile" :: [] -> Error "--profile requires a name"
    | "--json" :: rest -> loop workspace_dir profile true subtool targets rest
    | "--help" :: _ -> Error (command_usage env_doc)
    | option :: _ when String_util.starts_with ~prefix:"-" option ->
        Error (Printf.sprintf "unknown option '%s'" option)
    | value :: rest -> (
        match subtool with
        | None ->
            let* subtool = Env_report.parse_subtool value in
            loop workspace_dir profile json (Some subtool) targets rest
        | Some Env_report.Run when targets <> [] ->
            Error "env run accepts at most one target"
        | Some _ ->
            loop workspace_dir profile json subtool (value :: targets) rest)
  in
  loop "." None false None [] args

let parse_repl_args (args : string list) : (repl_options, string) result =
  let rec loop (options : repl_options) = function
    | [] -> Ok options
    | "--" :: rest -> Ok { options with args = rest }
    | "--workspace" :: dir :: rest ->
        loop { options with workspace_dir = dir } rest
    | "--workspace" :: [] -> Error "--workspace requires a directory"
    | "--profile" :: value :: rest ->
        loop { options with profile = Some value } rest
    | "--profile" :: [] -> Error "--profile requires a name"
    | ("--verbose" | "-v") :: rest ->
        loop { options with verbose = true } rest
    | "--help" :: _ -> Error (command_usage repl_doc)
    | option :: _ when String_util.starts_with ~prefix:"-" option ->
        Error (Printf.sprintf "unknown option '%s'" option)
    | value :: rest -> (
        match options.target with
        | None -> loop { options with target = Some value } rest
        | Some _ -> Error "repl accepts at most one target before --")
  in
  loop
    { workspace_dir = "."; verbose = false; target = None; args = []; profile = None }
    args

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
  let rec loop workspace_dir shell query describe current previous = function
    | [] ->
        if query then
          Ok
            {
              workspace_dir;
              mode = Query { previous = List.rev previous; current; describe };
            }
        else (
          match shell with
          | Some shell -> Ok { workspace_dir; mode = Render_script shell }
          | None -> Error "completion requires a shell name")
    | "--workspace" :: dir :: rest ->
        loop dir shell query describe current previous rest
    | "--workspace" :: [] -> Error "--workspace requires a directory"
    | "--query" :: rest -> loop workspace_dir shell true describe current previous rest
    | "--describe" :: rest ->
        if query then loop workspace_dir shell query true current previous rest
        else Error "--describe is only supported with --query"
    | "--current" :: value :: rest ->
        if query then loop workspace_dir shell query describe value previous rest
        else Error "--current is only supported with --query"
    | "--current" :: [] -> Error "--current requires a value"
    | "--" :: rest ->
        if query then
          Ok
            {
              workspace_dir;
              mode =
                Query
                  {
                    previous = List.rev_append previous rest;
                    current;
                    describe;
                  };
            }
        else Error "completion accepts exactly one shell name"
    | "--help" :: _ when not query -> Error (command_usage completion_doc)
    | option :: _ when String_util.starts_with ~prefix:"-" option ->
        Error (Printf.sprintf "unknown option '%s'" option)
    | value :: rest ->
        if query then
          loop workspace_dir shell query describe current (value :: previous) rest
        else
          match shell with
          | None -> loop workspace_dir (Some value) query describe current previous rest
          | Some _ -> Error "completion accepts exactly one shell name"
  in
  loop "." None false false "" [] args

let parse_migrate_args args =
  let rec loop options = function
    | [] ->
        if options.stdout && Option.is_some options.output_path then
          Error "--stdout cannot be combined with --output"
        else Ok options
    | "--workspace" :: dir :: rest ->
        loop { options with workspace_dir = dir } rest
    | "--workspace" :: [] -> Error "--workspace requires a directory"
    | "--output" :: path :: rest ->
        loop { options with output_path = Some path } rest
    | "--output" :: [] -> Error "--output requires a path"
    | "--stdout" :: rest -> loop { options with stdout = true } rest
    | "--force" :: rest -> loop { options with force = true } rest
    | "--help" :: _ -> Error (command_usage migrate_doc)
    | option :: _ when String_util.starts_with ~prefix:"-" option ->
        Error (Printf.sprintf "unknown option '%s'" option)
    | _ :: _ -> Error "migrate does not accept positional arguments"
  in
  loop
    { workspace_dir = "."; output_path = None; stdout = false; force = false }
    args

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

let load_workspace_if_present workspace_dir =
  if not (Fs.is_directory workspace_dir) then
    Error
      (Printf.sprintf "workspace directory does not exist: %s" workspace_dir)
  else
    let manifest_path = Filename.concat workspace_dir Manifest.default_filename in
    if Fs.exists manifest_path then Manifest.load manifest_path |> Result.map Option.some
    else Ok None

let profile_names workspace =
  Manifest.default_profile workspace
  :: List.map (fun (profile : Manifest.profile) -> profile.name) workspace.profiles
  |> String_util.dedup_preserve

let all_target_names workspace =
  List.map Manifest.target_name workspace.Manifest.targets

let candidate ?hint value = { value; hint }

let target_candidate target =
  candidate ?hint:(Manifest.target_package_path target) (Manifest.target_name target)

let executable_target_names workspace =
  List.filter_map
    (function
      | Manifest.Executable executable -> Some executable.name
      | Manifest.Library _ | Manifest.Test _ -> None)
    workspace.Manifest.targets

let executable_target_candidates workspace =
  List.filter_map
    (function
      | Manifest.Executable executable ->
          Some
            (candidate ?hint:executable.package_path executable.name)
      | Manifest.Library _ | Manifest.Test _ -> None)
    workspace.Manifest.targets

let test_target_names workspace =
  List.filter_map
    (function
      | Manifest.Test test -> Some test.name
      | Manifest.Library _ | Manifest.Executable _ -> None)
    workspace.Manifest.targets

let test_target_candidates workspace =
  List.filter_map
    (function
      | Manifest.Test test -> Some (candidate ?hint:test.package_path test.name)
      | Manifest.Library _ | Manifest.Executable _ -> None)
    workspace.Manifest.targets

let installable_target_names workspace =
  List.filter_map
    (function
      | Manifest.Library library -> Some library.name
      | Manifest.Executable executable -> Some executable.name
      | Manifest.Test _ -> None)
    workspace.Manifest.targets

let installable_target_candidates workspace =
  List.filter_map
    (function
      | Manifest.Library library ->
          Some (candidate ?hint:library.package_path library.name)
      | Manifest.Executable executable ->
          Some (candidate ?hint:executable.package_path executable.name)
      | Manifest.Test _ -> None)
    workspace.Manifest.targets

let find_command_doc name =
  List.find_opt (fun (doc : command_doc) -> doc.name = name) command_docs

let option_expects_value = function
  | "--workspace" | "--profile" | "--backend" | "--prefix" | "--destdir"
  | "--output" ->
      true
  | _ -> false

let rec positional_argument_count = function
  | [] -> 0
  | "--" :: rest -> List.length rest
  | option :: _ :: rest when option_expects_value option ->
      positional_argument_count rest
  | option :: rest when String_util.starts_with ~prefix:"-" option ->
      positional_argument_count rest
  | _value :: rest -> 1 + positional_argument_count rest

let rec positional_arguments acc = function
  | [] -> List.rev acc
  | "--" :: rest -> List.rev_append acc rest
  | option :: _ :: rest when option_expects_value option ->
      positional_arguments acc rest
  | option :: rest when String_util.starts_with ~prefix:"-" option ->
      positional_arguments acc rest
  | value :: rest -> positional_arguments (value :: acc) rest

let positional_completion_candidates ?workspace command_name rest =
  match workspace with
  | None -> (
      match command_name with
      | "completion" when positional_argument_count rest = 0 ->
          List.map (fun word -> candidate word) completion_doc.completion_words
      | "env" when positional_argument_count rest = 0 ->
          List.map (fun word -> candidate word) env_doc.completion_words
      | _ -> [] )
  | Some workspace -> (
      match command_name with
      | "build" | "clean" | "graph" | "deps" | "explain" ->
          List.map target_candidate workspace.Manifest.targets
      | "run" ->
          if positional_argument_count rest = 0 then
            executable_target_candidates workspace
          else []
      | "test" -> test_target_candidates workspace
      | "repl" ->
          if positional_argument_count rest = 0 then
            List.map target_candidate workspace.Manifest.targets
          else []
      | "env" -> (
          match positional_arguments [] rest with
          | [] -> List.map (fun word -> candidate word) env_doc.completion_words
          | [ "build" ] -> List.map target_candidate workspace.Manifest.targets
          | [ "run" ] -> executable_target_candidates workspace
          | [ "test" ] -> test_target_candidates workspace
          | [ "install" ] -> installable_target_candidates workspace
          | _ -> [] )
      | "install" -> installable_target_candidates workspace
      | "completion" when positional_argument_count rest = 0 ->
          List.map (fun word -> candidate word) completion_doc.completion_words
      | "docs" | "toolchain" | "migrate" -> []
      | _ -> [])

let value_completion_candidates ?workspace = function
  | "--profile" -> (
      match workspace with
      | Some workspace ->
          List.map (fun word -> candidate word) (profile_names workspace)
      | None -> [])
  | "--backend" -> List.map (fun word -> candidate word) backend_completion_words
  | "--workspace" | "--prefix" | "--destdir" | "--output" -> []
  | _ -> []

let value_completion_response ?workspace = function
  | "--workspace" | "--prefix" | "--destdir" | "--output" ->
      Complete_directories
  | option_name ->
      Completion_candidates (value_completion_candidates ?workspace option_name)

let dedup_completion_candidates candidates =
  let seen = Hashtbl.create (List.length candidates) in
  let rec loop acc = function
    | [] -> List.rev acc
    | ({ value; _ } as candidate) :: rest ->
        if Hashtbl.mem seen value then loop acc rest
        else (
          Hashtbl.add seen value ();
          loop (candidate :: acc) rest)
  in
  loop [] candidates

let filter_completion_candidates ~current candidates =
  dedup_completion_candidates candidates
  |> List.filter (fun candidate ->
         current = "" || String_util.starts_with ~prefix:current candidate.value)

let completion_response workspace ~previous ~current =
  match previous with
  | [] ->
      Completion_candidates
        (filter_completion_candidates ~current
           (List.map (fun doc -> candidate doc.name) command_docs))
  | command_name :: rest -> (
      match find_command_doc command_name with
      | None ->
          Completion_candidates
            (filter_completion_candidates ~current
               (List.map (fun doc -> candidate doc.name) command_docs))
      | Some doc when List.mem "--" rest -> Completion_candidates []
      | Some doc -> (
          match List.rev previous with
          | option_name :: _ when option_expects_value option_name -> (
              match value_completion_response ?workspace option_name with
              | Complete_directories -> Complete_directories
              | Completion_candidates candidates ->
                  Completion_candidates
                    (filter_completion_candidates ~current candidates))
          | _ ->
              let flags = command_flag_words doc in
              let candidates =
                if String_util.starts_with ~prefix:"-" current then
                  List.map (fun flag -> candidate flag) flags
                else
                  positional_completion_candidates ?workspace:workspace
                    command_name rest
                  @ List.map (fun flag -> candidate flag) flags
              in
              Completion_candidates
                (filter_completion_candidates ~current candidates)))

let executable_targets (workspace : Manifest.workspace) : Manifest.executable list =
  List.filter_map
    (function
      | Manifest.Executable executable -> Some executable
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
      | Some (Manifest.Executable executable) -> Ok executable)
  | None -> (
      match executable_targets workspace with
      | [] -> Error "workspace does not define any executables to run"
      | [ executable ] -> Ok executable
      | executables ->
          Error
            (Printf.sprintf "workspace defines multiple executables; choose one: %s"
               (String.concat ", "
                  (List.map
                     (fun (executable : Manifest.executable) -> executable.name)
                     executables))))

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

let run_graph (options : graph_options) =
  match load_workspace options.workspace_dir with
  | Error message -> report_error message
  | Ok workspace -> (
      match
        Graph.plan ~workspace_root:options.workspace_dir
          ~requested_targets:options.targets
          ~backend_request:options.backend_request ?profile:options.profile
          workspace
      with
      | Ok report ->
          print_endline (Graph.render_report report);
          Exit_code 0
      | Error message -> report_error message)

let run_executable (options : run_options) =
  match load_workspace options.workspace_dir with
  | Error message -> report_error message
  | Ok workspace -> (
      match resolve_run_target workspace options.target with
      | Error message -> report_error message
      | Ok target -> (
          match
            Builder.build ~workspace_root:options.workspace_dir
              ~verbose:options.verbose ~requested_targets:[ target.name ]
              ~backend_request:options.backend_request ?profile:options.profile
              workspace
          with
          | Error message -> report_error message
          | Ok result -> (
              match find_built_executable target.name result.Builder.artifacts with
              | None ->
                  report_error
                    (Printf.sprintf
                       "internal error: build completed without executable '%s'"
                       target.name)
              | Some binary ->
                  print_endline
                    (Printf.sprintf "Running executable %s -> %s"
                       (target.name ^ Manifest.package_suffix target.package_path)
                       binary);
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

let run_deps (options : deps_options) =
  match load_workspace options.workspace_dir with
  | Error message -> report_error message
  | Ok workspace -> (
      let session = Toolchain.create_session () in
      match Deps.report_for_targets ~session workspace options.targets with
      | Ok report ->
          print_endline (Deps.render_report report);
          Exit_code 0
      | Error message -> report_error message)

let run_env (options : env_options) =
  match load_workspace options.workspace_dir with
  | Error message -> report_error message
  | Ok workspace -> (
      match
        Env_report.report ~workspace_root:options.workspace_dir
          ?profile:options.profile workspace options.subtool options.targets
      with
      | Ok report ->
          print_string
            (if options.json then Env_report.render_json_report report
             else Env_report.render_report report);
          Exit_code 0
      | Error message -> report_error message)

let run_repl (options : repl_options) =
  match load_workspace options.workspace_dir with
  | Error message -> report_error message
  | Ok workspace -> (
      match
        Repl.run ~workspace_root:options.workspace_dir ~verbose:options.verbose
          ?profile:options.profile ?target:options.target ~args:options.args
          workspace
      with
      | Ok status -> Forward_status status
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
  match load_workspace_if_present options.workspace_dir with
  | Error message -> report_error message
  | Ok workspace -> (
      match options.mode with
      | Render_script shell -> (
          let workspace_dir =
            if options.workspace_dir = "." then None else Some options.workspace_dir
          in
          match completion_script ?workspace_dir shell with
          | Ok script ->
              print_string script;
              Exit_code 0
          | Error message -> report_error message)
      | Query { previous; current; describe } ->
          (match completion_response workspace ~previous ~current with
          | Complete_directories ->
              print_endline (completion_protocol_header "directories");
              Exit_code 0
          | Completion_candidates candidates ->
              print_endline (completion_protocol_header "candidates");
              List.iter
                (fun candidate ->
                  match (describe, candidate.hint) with
                  | true, Some hint ->
                      print_endline
                        (completion_candidate_line ~hint candidate.value)
                  | _ -> print_endline (completion_candidate_line candidate.value))
                candidates;
              Exit_code 0))

let run_toolchain (_options : toolchain_options) =
  Toolchain.inspect () |> Toolchain.render_report |> print_endline;
  Exit_code 0

let run_migrate (options : migrate_options) =
  if not (Fs.is_directory options.workspace_dir) then
    report_error
      (Printf.sprintf "workspace directory does not exist: %s"
         options.workspace_dir)
  else
    match Migrate.run ~workspace_root:options.workspace_dir with
    | Error message -> report_error message
    | Ok migration ->
        if options.stdout then (
          print_string migration.Migrate.manifest;
          Exit_code 0)
        else
          let output_path =
            match options.output_path with
            | Some path -> path
            | None ->
                Filename.concat options.workspace_dir Manifest.default_filename
          in
          if Fs.exists output_path && not options.force then
            report_error
              (Printf.sprintf
                 "refusing to overwrite existing file %s; rerun with --force or \
                  use --stdout"
                 output_path)
          else if Fs.is_directory output_path then
            report_error
              (Printf.sprintf "output path is a directory: %s" output_path)
          else (
            Fs.write_file output_path migration.manifest;
            print_endline ("Wrote migration manifest " ^ output_path);
            Exit_code 0)

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
    Command { doc = graph_doc; parse = parse_graph_args; run = run_graph };
    Command { doc = run_doc; parse = parse_run_args; run = run_executable };
    Command { doc = test_doc; parse = parse_test_args; run = run_tests };
    Command { doc = clean_doc; parse = parse_clean_args; run = run_clean };
    Command { doc = deps_doc; parse = parse_deps_args; run = run_deps };
    Command { doc = env_doc; parse = parse_env_args; run = run_env };
    Command { doc = repl_doc; parse = parse_repl_args; run = run_repl };
    Command { doc = install_doc; parse = parse_install_args; run = run_install };
    Command { doc = docs_doc; parse = parse_docs_args; run = run_docs };
    Command
      { doc = completion_doc; parse = parse_completion_args; run = run_completion };
    Command
      { doc = toolchain_doc; parse = parse_toolchain_args; run = run_toolchain };
    Command { doc = explain_doc; parse = parse_explain_args; run = run_explain };
    Command { doc = migrate_doc; parse = parse_migrate_args; run = run_migrate };
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
