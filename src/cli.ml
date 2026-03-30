type lock_policy =
  | Ignore_lock
  | Warn_locked
  | Require_locked

type build_options = {
  workspace_dir : string;
  verbose : bool;
  targets : string list;
  backend_request : Toolchain.backend_request;
  profile : string option;
  lock_policy : lock_policy;
}

type status_options = {
  workspace_dir : string;
  targets : string list;
  backend_request : Toolchain.backend_request;
  profile : string option;
  json : bool;
}

type doctor_options = {
  workspace_dir : string;
  targets : string list;
  backend_request : Toolchain.backend_request;
  profile : string option;
  json : bool;
  lock_policy : lock_policy;
}

type watch_options = {
  workspace_dir : string;
  poll_ms : int;
  debounce_ms : int;
  max_runs : int option;
  keep_going : bool;
  include_globs : string list;
  ignore_globs : string list;
  command_name : string option;
  command_args : string list;
}

type init_options = {
  dir : string;
  member_path : string option;
  name : string option;
  library : string option;
  executable : string option;
  bare : bool;
  force : bool;
}

type action_options = {
  workspace_dir : string;
  verbose : bool;
  targets : string list;
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

type bench_options = {
  workspace_dir : string;
  verbose : bool;
  targets : string list;
  backend_request : Toolchain.backend_request;
  profile : string option;
  json : bool;
  warmup : int option;
  iterations : int option;
}

type clean_options = {
  workspace_dir : string;
  verbose : bool;
  targets : string list;
  profile : string option;
}

type promote_options = {
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

type lock_options = {
  workspace_dir : string;
  targets : string list;
  output_path : string option;
  stdout : bool;
}

type ppx_options = {
  workspace_dir : string;
  verbose : bool;
  target : string option;
  module_name : string option;
  profile : string option;
  interface : bool;
  output_path : string option;
  plan : bool;
}

type vendor_options = {
  workspace_dir : string;
  source_dir : string option;
  git_url : string option;
  archive_url : string option;
  ref_name : string option;
  checksum : string option;
  name : string option;
  force : bool;
}

type env_options = {
  workspace_dir : string;
  profile : string option;
  subtool : Env_report.subtool;
  targets : string list;
  json : bool;
  changed_only : bool;
}

type repl_options = {
  workspace_dir : string;
  verbose : bool;
  target : string option;
  args : string list;
  profile : string option;
  script_path : string option;
  plan : bool;
  json : bool;
}

type install_options = {
  workspace_dir : string;
  verbose : bool;
  targets : string list;
  backend_request : Toolchain.backend_request;
  profile : string option;
  prefix : string option;
  destdir : string option;
  lock_policy : lock_policy;
}

type release_artifacts_options = { output_dir : string }

type sync_generated_options = unit

type package_options = {
  output_dir : string;
  opam_output : string option;
  formula_output : string option;
  checksums_output : string option;
  asset_index_output : string option;
  archive_input : Packager.archive_input option;
  source_archive_mode : Packager.source_archive_mode;
}

type release_cut_options = {
  version : string option;
  tag : bool;
}

type update_homebrew_tap_options = {
  tap_dir : string option;
  formula_path : string option;
  source_archive : string option;
  commit : bool;
  push : bool;
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
  | Complete_files

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
  watch_root_files : string list -> Watch.root_file list;
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
    description = "Choose the compiler backend or let wadi auto-resolve it.";
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

let output_dir_option =
  {
    usage = "--output-dir DIR";
    flags = [ "--output-dir" ];
    description = "Write generated files under DIR instead of the current directory.";
  }

let output_option =
  {
    usage = "--output PATH";
    flags = [ "--output" ];
    description = "Write the generated manifest to PATH instead of wadi.toml.";
  }

let ppx_output_option =
  {
    usage = "--output PATH";
    flags = [ "--output" ];
    description = "Write the transformed source to PATH instead of stdout.";
  }

let stdout_option =
  {
    usage = "--stdout";
    flags = [ "--stdout" ];
    description = "Print the generated output instead of writing a file.";
  }

let opam_output_option =
  {
    usage = "--opam-output PATH";
    flags = [ "--opam-output" ];
    description = "Write the generated opam package metadata to PATH.";
  }

let formula_output_option =
  {
    usage = "--formula-output PATH";
    flags = [ "--formula-output" ];
    description = "Write the generated Homebrew formula to PATH.";
  }

let checksums_output_option =
  {
    usage = "--checksums-output PATH";
    flags = [ "--checksums-output" ];
    description = "Write SHA256SUMS-style checksum lines for generated release assets.";
  }

let asset_index_output_option =
  {
    usage = "--asset-index-output PATH";
    flags = [ "--asset-index-output" ];
    description =
      "Write a machine-readable release asset index with names, URLs, sizes, and checksums.";
  }

let source_archive_option =
  {
    usage = "--source-archive PATH";
    flags = [ "--source-archive" ];
    description =
      "Reuse an explicit source archive when rendering packaging metadata instead of rebuilding one.";
  }

let formula_input_option =
  {
    usage = "--formula PATH";
    flags = [ "--formula" ];
    description = "Reuse an existing Homebrew formula file instead of rendering one.";
  }

let source_archive_dir_option =
  {
    usage = "--source-archive-dir DIR";
    flags = [ "--source-archive-dir" ];
    description =
      "Refresh the canonical source archive into DIR before rendering packaging metadata.";
  }

let reuse_source_archive_dir_option =
  {
    usage = "--reuse-source-archive-dir DIR";
    flags = [ "--reuse-source-archive-dir" ];
    description =
      "Reuse the canonical source archive already present in DIR without rebuilding it.";
  }

let source_archive_mode_option =
  {
    usage = "--source-archive-mode tracked|worktree";
    flags = [ "--source-archive-mode" ];
    description =
      "Choose whether rebuilt source archives come from tracked git paths only or from the live non-ignored worktree.";
  }

let version_option =
  {
    usage = "--version X.Y.Z";
    flags = [ "--version" ];
    description = "Set the canonical release version to X.Y.Z before regenerating metadata.";
  }

let tag_option =
  {
    usage = "--tag";
    flags = [ "--tag" ];
    description = "Create the annotated git tag that matches the refreshed release version.";
  }

let tap_dir_option =
  {
    usage = "--tap-dir DIR";
    flags = [ "--tap-dir" ];
    description = "Update the Homebrew tap checkout rooted at DIR.";
  }

let commit_option =
  {
    usage = "--commit";
    flags = [ "--commit" ];
    description = "Commit the rendered Homebrew formula into the tap checkout.";
  }

let push_option =
  {
    usage = "--push";
    flags = [ "--push" ];
    description = "Push the Homebrew tap checkout after committing the rendered formula.";
  }

let force_option =
  {
    usage = "--force";
    flags = [ "--force" ];
    description = "Overwrite existing generated files or output paths.";
  }

let json_option =
  {
    usage = "--json";
    flags = [ "--json" ];
    description = "Print machine-readable JSON output instead of the text report.";
  }

let changed_only_option =
  {
    usage = "--changed-only";
    flags = [ "--changed-only" ];
    description =
      "Show only environment bindings that differ from the inherited host environment.";
  }

let current_option =
  {
    usage = "--current";
    flags = [ "--current" ];
    description =
      "Compute a fresh rebuild explanation from current inputs without compiling, linking, or materializing generated sources.";
  }

let plan_option =
  {
    usage = "--plan";
    flags = [ "--plan" ];
    description =
      "Print the resolved REPL plan and exit without launching the toplevel.";
  }

let ppx_plan_option =
  {
    usage = "--plan";
    flags = [ "--plan" ];
    description =
      "Print the resolved preprocessor and PPX pipeline without dumping transformed source.";
  }

let script_option =
  {
    usage = "--script PATH";
    flags = [ "--script" ];
    description =
      "Read noninteractive toplevel phrases from PATH via stdin instead of passing a script file as an OCaml argv.";
  }

let warmup_option =
  {
    usage = "--warmup COUNT";
    flags = [ "--warmup" ];
    description = "Run each benchmark target COUNT warmup times before measuring.";
  }

let iterations_option =
  {
    usage = "--iterations COUNT";
    flags = [ "--iterations" ];
    description = "Run each benchmark target COUNT measured times.";
  }

let poll_ms_option =
  {
    usage = "--poll-ms COUNT";
    flags = [ "--poll-ms" ];
    description = "Poll the workspace for file changes every COUNT milliseconds.";
  }

let debounce_ms_option =
  {
    usage = "--debounce-ms COUNT";
    flags = [ "--debounce-ms" ];
    description =
      "Wait COUNT milliseconds after the first detected change before rerunning the watched subtool.";
  }

let max_runs_option =
  {
    usage = "--max-runs COUNT";
    flags = [ "--max-runs" ];
    description =
      "Exit after COUNT watched executions instead of running until interrupted.";
  }

let keep_going_option =
  {
    usage = "--keep-going";
    flags = [ "--keep-going" ];
    description =
      "Keep watching after a failed run instead of exiting with the first non-zero status.";
  }

let include_glob_option =
  {
    usage = "--include GLOB";
    flags = [ "--include" ];
    description =
      "Watch only paths matching GLOB. Repeat to narrow large workspaces to the relevant source trees.";
  }

let ignore_glob_option =
  {
    usage = "--ignore GLOB";
    flags = [ "--ignore" ];
    description =
      "Ignore paths matching GLOB in addition to the built-in .git, _wadi, and _bootstrap exclusions.";
  }

let dir_option =
  {
    usage = "--dir DIR";
    flags = [ "--dir" ];
    description =
      "Create or update the scaffold in DIR instead of the current directory.";
  }

let name_option =
  {
    usage = "--name NAME";
    flags = [ "--name" ];
    description = "Set the generated workspace or vendor name explicitly.";
  }

let member_option =
  {
    usage = "--member PATH";
    flags = [ "--member" ];
    description =
      "Scaffold a package-local manifest at PATH and register it under members = [...].";
  }

let library_name_option =
  {
    usage = "--library NAME";
    flags = [ "--library" ];
    description = "Scaffold a library target named NAME.";
  }

let executable_name_option =
  {
    usage = "--executable NAME";
    flags = [ "--executable" ];
    description = "Scaffold an executable target named NAME.";
  }

let bare_option =
  {
    usage = "--bare";
    flags = [ "--bare" ];
    description = "Write only a root manifest without any targets or source files.";
  }

let locked_option =
  {
    usage = "--locked";
    flags = [ "--locked" ];
    description =
      "Require wadi.lock to match the current manifest, recorded toolchain facts, and resolved package paths before continuing.";
  }

let warn_locked_option =
  {
    usage = "--warn-locked";
    flags = [ "--warn-locked" ];
    description =
      "Warn when wadi.lock is missing or stale against the current manifest, toolchain facts, or resolved package paths, but continue with the build or install.";
  }

let source_option =
  {
    usage = "--source DIR";
    flags = [ "--source" ];
    description = "Copy the vendored package from DIR into vendor/NAME.";
  }

let git_option =
  {
    usage = "--git URL";
    flags = [ "--git" ];
    description =
      "Clone the vendored package from URL into vendor/NAME and verify the pinned commit checksum.";
  }

let url_option =
  {
    usage = "--url URL";
    flags = [ "--url" ];
    description =
      "Download and extract the vendored source archive from URL into vendor/NAME and verify its checksum.";
  }

let ref_option =
  {
    usage = "--ref REV";
    flags = [ "--ref" ];
    description =
      "Checkout REV after cloning --git before validating the pinned checksum.";
  }

let checksum_option =
  {
    usage = "--checksum VALUE";
    flags = [ "--checksum" ];
    description =
      "Pin remote vendored sources. Git sources compare the resolved commit id; URL sources verify the downloaded archive digest (plain hex defaults to sha256:).";
  }

let interface_option =
  {
    usage = "--interface";
    flags = [ "--interface" ];
    description = "Inspect or apply the target module interface (`.mli`) instead of the implementation.";
  }

let backend_completion_words = [ "auto"; "native"; "bytecode" ]

let completion_protocol_name = "__wadi_completion"

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

let no_watch_root_files _ = []

let lock_flag_watch_root_files args =
  if List.exists (fun arg -> arg = "--locked" || arg = "--warn-locked") args then
    [ Watch.lock_root_file ]
  else []

let always_watch_lock_root_file _ = [ Watch.lock_root_file ]

let build_doc =
  {
    name = "build";
    summary = "Compile libraries, executables, and tests into predictable artifact roots.";
    signature =
      "wadi build [--workspace DIR] [--profile NAME] [--backend auto|native|bytecode] [--locked | --warn-locked] [--verbose] [TARGET ...]";
    examples =
      [
        "wadi build";
        "wadi build hello";
        "wadi build --locked hello";
        "wadi build --workspace examples/hello --profile release --verbose";
      ];
    options =
      [
        workspace_option;
        profile_option;
        backend_option;
        locked_option;
        warn_locked_option;
        verbose_option;
        help_option;
      ];
    completion_words = [];
    watch_root_files = lock_flag_watch_root_files;
  }

let status_doc =
  {
    name = "status";
    summary =
      "Summarize which targets are rebuilt, regenerated, or reused without compiling.";
    signature =
      "wadi status [--workspace DIR] [--profile NAME] [--backend auto|native|bytecode] [--json] [TARGET ...]";
    examples =
      [
        "wadi status";
        "wadi status hello";
        "wadi status --backend bytecode hello";
        "wadi status --json --profile release";
      ];
    options =
      [
        workspace_option;
        profile_option;
        backend_option;
        json_option;
        help_option;
      ];
    completion_words = [];
    watch_root_files = no_watch_root_files;
  }

let doctor_doc =
  {
    name = "doctor";
    summary =
      "Validate workspace configuration, toolchain health, package resolution, and lock drift.";
    signature =
      "wadi doctor [--workspace DIR] [--profile NAME] [--backend auto|native|bytecode] [--json] [--locked | --warn-locked] [TARGET ...]";
    examples =
      [
        "wadi doctor";
        "wadi doctor hello";
        "wadi doctor --locked hello";
        "wadi doctor --json --backend bytecode";
      ];
    options =
      [
        workspace_option;
        profile_option;
        backend_option;
        json_option;
        locked_option;
        warn_locked_option;
        help_option;
      ];
    completion_words = [];
    watch_root_files = always_watch_lock_root_file;
  }

let watch_doc =
  {
    name = "watch";
    summary =
      "Poll the workspace and rerun a selected wadi subtool whenever inputs change.";
    signature =
      "wadi watch [--workspace DIR] [--poll-ms COUNT] [--debounce-ms COUNT] [--max-runs COUNT] [--keep-going] [--include GLOB] [--ignore GLOB] SUBTOOL [ARG ...]";
    examples =
      [
        "wadi watch build";
        "wadi watch test unit";
        "wadi watch --keep-going --max-runs 2 build hello";
        "wadi watch --include 'lib/**' --include 'app/**' run demo";
        "wadi watch --ignore 'vendor/**' build";
        "wadi watch run demo -- --port 8080";
      ];
    options =
      [
        workspace_option;
        poll_ms_option;
        debounce_ms_option;
        max_runs_option;
        keep_going_option;
        include_glob_option;
        ignore_glob_option;
        help_option;
      ];
    completion_words = [];
    watch_root_files = no_watch_root_files;
  }

let init_doc =
  {
    name = "init";
    summary = "Scaffold a minimal wadi workspace without hand-writing the first manifest.";
    signature =
      "wadi init [--dir DIR] [--member PATH] [--name NAME] [--library NAME] [--executable NAME] [--bare] [--force]";
    examples =
      [
        "wadi init";
        "wadi init --name demo";
        "wadi init --dir monorepo --member packages/core --library core";
        "wadi init --dir examples/demo --library core --executable demo";
        "wadi init --dir scratch --bare";
      ];
    options =
      [
        dir_option;
        member_option;
        name_option;
        library_name_option;
        executable_name_option;
        bare_option;
        force_option;
        help_option;
      ];
    completion_words = [];
    watch_root_files = no_watch_root_files;
  }

let action_doc =
  {
    name = "action";
    summary =
      "Run declared generated-file actions for selected targets without compiling or linking.";
    signature =
      "wadi action [--workspace DIR] [--profile NAME] [--verbose] [TARGET ...]";
    examples =
      [
        "wadi action";
        "wadi action core";
        "wadi action demo";
        "wadi action --profile release core demo";
      ];
    options = [ workspace_option; profile_option; verbose_option; help_option ];
    completion_words = [];
    watch_root_files = no_watch_root_files;
  }

let ppx_doc =
  {
    name = "ppx";
    summary =
      "Inspect or dump the post-preprocess, post-PPX source for one target module.";
    signature =
      "wadi ppx [--workspace DIR] [--profile NAME] [--verbose] [--interface] [--plan] [--output PATH] TARGET [MODULE]";
    examples =
      [
        "wadi ppx demo";
        "wadi ppx demo main";
        "wadi ppx --interface core version";
        "wadi ppx --plan demo main";
        "wadi ppx --output _debug/main.ml demo main";
      ];
    options =
      [
        workspace_option;
        profile_option;
        verbose_option;
        interface_option;
        ppx_plan_option;
        ppx_output_option;
        help_option;
      ];
    completion_words = [];
    watch_root_files = no_watch_root_files;
  }

let run_doc =
  {
    name = "run";
    summary = "Build and launch an executable target with exact argv forwarding.";
    signature =
      "wadi run [--workspace DIR] [--profile NAME] [--backend auto|native|bytecode] [--verbose] [TARGET] [-- ARG ...]";
    examples =
      [
        "wadi run";
        "wadi run hello";
        "wadi run --profile release hello -- --loud";
        "wadi run -- --port 8080";
      ];
    options = [ workspace_option; profile_option; backend_option; verbose_option; help_option ];
    completion_words = [];
    watch_root_files = no_watch_root_files;
  }

let test_doc =
  {
    name = "test";
    summary = "Build and execute declared test targets with a direct failure summary.";
    signature =
      "wadi test [--workspace DIR] [--profile NAME] [--backend auto|native|bytecode] [--verbose] [TARGET ...]";
    examples =
      [
        "wadi test";
        "wadi test unit";
        "wadi test unit integration";
        "wadi test --workspace examples/hello --profile ci --verbose";
      ];
    options = [ workspace_option; profile_option; backend_option; verbose_option; help_option ];
    completion_words = [];
    watch_root_files = no_watch_root_files;
  }

let bench_doc =
  {
    name = "bench";
    summary =
      "Build executable targets and report stable benchmark timing summaries.";
    signature =
      "wadi bench [--workspace DIR] [--profile NAME] [--backend auto|native|bytecode] [--verbose] [--json] [--warmup COUNT] [--iterations COUNT] [TARGET ...]";
    examples =
      [
        "wadi bench";
        "wadi bench demo";
        "wadi bench --warmup 1 --iterations 5 demo";
        "wadi bench --json demo";
      ];
    options =
      [
        workspace_option;
        profile_option;
        backend_option;
        verbose_option;
        json_option;
        warmup_option;
        iterations_option;
        help_option;
      ];
    completion_words = [];
    watch_root_files = no_watch_root_files;
  }

let clean_doc =
  {
    name = "clean";
    summary = "Remove the whole artifact tree or only the requested target outputs.";
    signature = "wadi clean [--workspace DIR] [--profile NAME] [--verbose] [TARGET ...]";
    examples =
      [
        "wadi clean";
        "wadi clean hello";
        "wadi clean hello greeting";
        "wadi clean --workspace examples/hello --profile release --verbose";
      ];
    options = [ workspace_option; profile_option; verbose_option; help_option ];
    completion_words = [];
    watch_root_files = no_watch_root_files;
  }

let promote_doc =
  {
    name = "promote";
    summary =
      "Copy declared non-source action outputs back into the workspace on purpose.";
    signature =
      "wadi promote [--workspace DIR] [--profile NAME] [--verbose] [TARGET ...]";
    examples =
      [
        "wadi promote";
        "wadi promote snapshots";
        "wadi promote --profile release fixtures";
      ];
    options = [ workspace_option; profile_option; verbose_option; help_option ];
    completion_words = [];
    watch_root_files = no_watch_root_files;
  }

let graph_doc =
  {
    name = "graph";
    summary = "Show target build order, module order, and pipeline shape without compiling.";
    signature =
      "wadi graph [--workspace DIR] [--profile NAME] [--backend auto|native|bytecode] [TARGET ...]";
    examples =
      [
        "wadi graph";
        "wadi graph hello";
        "wadi graph --profile release --backend bytecode hello";
      ];
    options = [ workspace_option; profile_option; backend_option; help_option ];
    completion_words = [];
    watch_root_files = no_watch_root_files;
  }

let deps_doc =
  {
    name = "deps";
    summary = "Resolve transitive external package requirements for selected targets.";
    signature = "wadi deps [--workspace DIR] [TARGET ...]";
    examples =
      [
        "wadi deps";
        "wadi deps hello";
        "wadi deps --workspace examples/hello greeting hello";
      ];
    options = [ workspace_option; help_option ];
    completion_words = [];
    watch_root_files = no_watch_root_files;
  }

let lock_doc =
  {
    name = "lock";
    summary =
      "Snapshot resolved toolchain facts and external package paths into a machine-readable lock file.";
    signature =
      "wadi lock [--workspace DIR] [--output PATH] [--stdout] [TARGET ...]";
    examples =
      [
        "wadi lock";
        "wadi lock demo";
        "wadi lock --stdout";
        "wadi lock --output wadi.lock.json demo";
      ];
    options = [ workspace_option; output_option; stdout_option; help_option ];
    completion_words = [];
    watch_root_files = no_watch_root_files;
  }

let vendor_doc =
  {
    name = "vendor";
    summary =
      "Copy or fetch a source dependency into vendor/ and register it as a workspace member.";
    signature =
      "wadi vendor [--workspace DIR] (--source DIR | --git URL | --url URL) [--ref REV] [--checksum VALUE] [--name NAME] [--force]";
    examples =
      [
        "wadi vendor --source ../dep";
        "wadi vendor --git https://example.com/dep.git --checksum 0123abcd --name dep";
        "wadi vendor --url https://example.com/dep.tar.gz --checksum sha256:0123abcd --name dep";
        "wadi vendor --workspace examples/app --source ../core --force";
      ];
    options =
      [
        workspace_option;
        source_option;
        git_option;
        url_option;
        ref_option;
        checksum_option;
        name_option;
        force_option;
        help_option;
      ];
    completion_words = [];
    watch_root_files = no_watch_root_files;
  }

let env_doc =
  {
    name = "env";
    summary =
      "Print the exact subprocess environment a build, action, run, test, bench, or install step would inherit.";
    signature =
      "wadi env [--workspace DIR] [--profile NAME] [--json] [--changed-only] SUBTOOL [TARGET ...]";
    examples =
      [
        "wadi env build";
        "wadi env action core";
        "wadi env --profile release build demo";
        "wadi env --json run demo";
        "wadi env --changed-only build demo";
        "wadi env run demo";
        "wadi env test unit";
        "wadi env bench demo";
      ];
    options =
      [
        workspace_option;
        profile_option;
        json_option;
        changed_only_option;
        help_option;
      ];
    completion_words = [ "build"; "action"; "run"; "test"; "bench"; "install" ];
    watch_root_files = no_watch_root_files;
  }

let repl_doc =
  {
    name = "repl";
    summary =
      "Build a bytecode toplevel with workspace libraries and packages already wired in.";
    signature =
      "wadi repl [--workspace DIR] [--profile NAME] [--verbose] [--plan] [--json] [--script PATH] [TARGET] [-- OCAML_ARG ...]";
    examples =
      [
        "wadi repl core";
        "wadi repl demo";
        "wadi repl --plan --json core";
        "wadi repl core --script scripts/session.ml -- -noinit -noprompt";
        "wadi repl --profile release core -- -noinit -noprompt";
      ];
    options =
      [
        workspace_option;
        profile_option;
        verbose_option;
        plan_option;
        json_option;
        script_option;
        help_option;
      ];
    completion_words = [];
    watch_root_files = no_watch_root_files;
  }

let install_doc =
  {
    name = "install";
    summary = "Stage installable libraries, executables, and metadata under a prefix.";
    signature =
      "wadi install [--workspace DIR] [--profile NAME] [--backend auto|native|bytecode] [--prefix DIR] [--destdir DIR] [--locked | --warn-locked] [--verbose] [TARGET ...]";
    examples =
      [
        "wadi install";
        "wadi install hello";
        "wadi install --warn-locked --prefix _stage hello";
        "wadi install --prefix _stage hello greeting";
        "wadi install --prefix /usr/local --destdir _pkg hello";
      ];
    options =
      [
        workspace_option;
        profile_option;
        backend_option;
        prefix_option;
        destdir_option;
        locked_option;
        warn_locked_option;
        verbose_option;
        help_option;
      ];
    completion_words = [];
    watch_root_files = lock_flag_watch_root_files;
  }

let release_artifacts_doc =
  {
    name = "release-artifacts";
    summary =
      "Render CLI docs, shell completions, and packaged install-tree payloads from the live binary.";
    signature = "wadi release-artifacts [--output-dir DIR]";
    examples =
      [
        "wadi release-artifacts";
        "wadi release-artifacts --output-dir dist";
      ];
    options = [ output_dir_option; help_option ];
    completion_words = [];
    watch_root_files = no_watch_root_files;
  }

let package_doc =
  {
    name = "package";
    summary =
      "Render opam, Homebrew, checksum, and release-asset metadata from canonical release facts.";
    signature =
      "wadi package [--output-dir DIR] [--opam-output PATH] [--formula-output PATH] [--checksums-output PATH] [--asset-index-output PATH] [--source-archive PATH | --source-archive-dir DIR | --reuse-source-archive-dir DIR] [--source-archive-mode tracked|worktree]";
    examples =
      [
        "wadi package";
        "wadi package --output-dir dist";
        "wadi package --source-archive-dir dist --asset-index-output dist/release-assets.json";
        "wadi package --source-archive dist/wadi-source.tar.gz --checksums-output dist/SHA256SUMS";
        "wadi package --source-archive-dir dist --source-archive-mode worktree";
      ];
    options =
      [
        output_dir_option;
        opam_output_option;
        formula_output_option;
        checksums_output_option;
        asset_index_output_option;
        source_archive_option;
        source_archive_dir_option;
        reuse_source_archive_dir_option;
        source_archive_mode_option;
        help_option;
      ];
    completion_words = [];
    watch_root_files = no_watch_root_files;
  }

let sync_generated_doc =
  {
    name = "sync-generated";
    summary =
      "Refresh bootstrap seed metadata, CLI docs, shell completions, and packaging manifests together.";
    signature = "wadi sync-generated";
    examples = [ "wadi sync-generated" ];
    options = [ help_option ];
    completion_words = [];
    watch_root_files = no_watch_root_files;
  }

let release_cut_doc =
  {
    name = "release-cut";
    summary =
      "Bump the canonical release version, refresh packaging metadata, validate it, and optionally tag the repo.";
    signature = "wadi release-cut --version X.Y.Z [--tag]";
    examples =
      [
        "wadi release-cut --version 0.2.0";
        "wadi release-cut --version 0.2.0 --tag";
      ];
    options = [ version_option; tag_option; help_option ];
    completion_words = [];
    watch_root_files = no_watch_root_files;
  }

let update_homebrew_tap_doc =
  {
    name = "update-homebrew-tap";
    summary =
      "Clone or update the canonical Homebrew tap with the rendered wadi formula.";
    signature =
      "wadi update-homebrew-tap --tap-dir DIR [--formula PATH | --source-archive PATH] [--commit] [--push]";
    examples =
      [
        "wadi update-homebrew-tap --tap-dir ../homebrew-wadi --formula Formula/wadi.rb --commit";
        "wadi update-homebrew-tap --tap-dir ../homebrew-wadi --source-archive dist/wadi-0.1.0-source.tar.gz --commit --push";
      ];
    options =
      [
        tap_dir_option;
        formula_input_option;
        source_archive_option;
        commit_option;
        push_option;
        help_option;
      ];
    completion_words = [];
    watch_root_files = no_watch_root_files;
  }

let docs_doc =
  {
    name = "docs";
    summary = "Render markdown CLI reference directly from the live command table.";
    signature = "wadi docs";
    examples = [ "wadi docs" ];
    options = [ help_option ];
    completion_words = [];
    watch_root_files = no_watch_root_files;
  }

let completion_doc =
  {
    name = "completion";
    summary = "Generate shell completion scripts from the live command table.";
    signature = "wadi completion [--workspace DIR] SHELL";
    examples = [ "wadi completion bash"; "wadi completion zsh"; "wadi completion fish" ];
    options = [ workspace_option; help_option ];
    completion_words = [ "bash"; "zsh"; "fish" ];
    watch_root_files = no_watch_root_files;
  }

let toolchain_doc =
  {
    name = "toolchain";
    summary = "Print the resolved OCaml toolchain, backend, and package search roots.";
    signature = "wadi toolchain";
    examples = [ "wadi toolchain" ];
    options = [ help_option ];
    completion_words = [];
    watch_root_files = no_watch_root_files;
  }

let explain_doc =
  {
    name = "explain";
    summary = "Show why a target rebuilt or reused artifacts and which commands were planned.";
    signature =
      "wadi explain [--workspace DIR] [--profile NAME] [--backend auto|native|bytecode] [--current] [--json] [TARGET ...]";
    examples =
      [
        "wadi explain";
        "wadi explain hello";
        "wadi explain --current hello";
        "wadi explain --current --backend bytecode hello";
        "wadi explain --json hello";
        "wadi explain --profile release greeting hello";
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
    watch_root_files = no_watch_root_files;
  }

let migrate_doc =
  {
    name = "migrate";
    summary =
      "Scan dune files and emit a first-pass wadi.toml manifest with review comments.";
    signature =
      "wadi migrate [--workspace DIR] [--output PATH] [--stdout] [--force]";
    examples =
      [
        "wadi migrate --stdout";
        "wadi migrate --workspace ../old-project";
        "wadi migrate --output converted.wadi.toml --force";
      ];
    options =
      [ workspace_option; output_option; stdout_option; force_option; help_option ];
    completion_words = [];
    watch_root_files = no_watch_root_files;
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
    init_doc;
    build_doc;
    status_doc;
    doctor_doc;
    watch_doc;
    action_doc;
    ppx_doc;
    graph_doc;
    run_doc;
    test_doc;
    bench_doc;
    clean_doc;
    promote_doc;
    deps_doc;
    lock_doc;
    vendor_doc;
    env_doc;
    repl_doc;
    install_doc;
    release_artifacts_doc;
    package_doc;
    sync_generated_doc;
    release_cut_doc;
    update_homebrew_tap_doc;
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
       "# Wadi CLI";
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
  "wadi completion"
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
      "_wadi_query() {";
      "  " ^ query ^ " --current \"$1\" -- \"${@:2}\" 2>/dev/null";
      "}";
      "_wadi_show_descriptions() {";
      "  local line";
      "  while IFS= read -r line; do";
      "    [[ -n \"$line\" ]] || continue";
      "    [[ \"$line\" == *$'\\t'* ]] || continue";
      "    printf '%s\\n' \"$line\" >&2";
      "  done";
      "}";
      "_wadi() {";
      "  local cur response first_line body record protocol version kind value description";
      "  local -a previous values described";
      "  cur=\"${COMP_WORDS[COMP_CWORD]}\"";
      "  previous=(\"${COMP_WORDS[@]:1:$((COMP_CWORD-1))}\")";
      "  response=\"$(_wadi_query \"$cur\" \"${previous[@]}\")\"";
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
      "  if [[ \"$kind\" == files ]]; then";
      "    compopt -o filenames 2>/dev/null";
      "    compgen -V COMPREPLY -f -- \"$cur\"";
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
      "    _wadi_show_descriptions <<< \"$(printf '%s\\n' \"${described[@]}\")\"";
      "  fi";
      "}";
      "complete -F _wadi wadi";
      "";
    ]

let render_zsh_completion ?workspace_dir () =
  let query = completion_query_command ?workspace_dir ~describe:true () in
  String.concat "\n"
    [
      "#compdef wadi";
      "";
      "_wadi_query() {";
      "  " ^ query ^ " --current \"$1\" -- \"${@:2}\" 2>/dev/null";
      "}";
      "_wadi() {";
      "  local current response first_line body";
      "  local record protocol version kind value description";
      "  local -a previous suggestions";
      "  current=\"${words[CURRENT]}\"";
      "  previous=(\"${(@)words[2,CURRENT-1]}\")";
      "  response=\"$(_wadi_query \"$current\" \"${previous[@]}\")\"";
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
      "  if [[ \"$kind\" == files ]]; then";
      "    _files";
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
      "compdef _wadi wadi";
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
      ([ "complete"; "-c"; "wadi"; "-n"; "__fish_seen_subcommand_from " ^ command_name ]
      @ flag_parts
      @ [ "-d"; String_util.shell_quote option_doc.description ])

let render_fish_completion ?workspace_dir () =
  let query = completion_query_command ?workspace_dir ~describe:true () in
  String.concat "\n"
    [
      "function __wadi_complete";
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
      "  if test \"$header[3]\" = files";
      "    __fish_complete_path \"$current\"";
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
      "complete -c wadi -f -a '(__wadi_complete)'";
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
  prerr_endline ("wadi: " ^ message);
  Exit_code 1

let default_backend_request () = Toolchain.env_backend_request ()

let choose_lock_policy current requested =
  match (current, requested) with
  | Ignore_lock, requested -> Ok requested
  | Warn_locked, Ignore_lock | Require_locked, Ignore_lock -> Ok current
  | Warn_locked, Warn_locked | Require_locked, Require_locked -> Ok current
  | Warn_locked, Require_locked | Require_locked, Warn_locked ->
      Error "--locked cannot be combined with --warn-locked"

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
    | "--locked" :: rest ->
        let* lock_policy = choose_lock_policy options.lock_policy Require_locked in
        loop { options with lock_policy } rest
    | "--warn-locked" :: rest ->
        let* lock_policy = choose_lock_policy options.lock_policy Warn_locked in
        loop { options with lock_policy } rest
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
      lock_policy = Ignore_lock;
    }
    args

let parse_status_args (args : string list) : (status_options, string) result =
  let* default_backend_request = default_backend_request () in
  let rec loop (options : status_options) = function
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
    | "--json" :: rest -> loop { options with json = true } rest
    | "--help" :: _ -> Error (command_usage status_doc)
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
      json = false;
    }
    args

let parse_doctor_args (args : string list) : (doctor_options, string) result =
  let* default_backend_request = default_backend_request () in
  let rec loop (options : doctor_options) = function
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
    | "--json" :: rest -> loop { options with json = true } rest
    | "--locked" :: rest ->
        let* lock_policy = choose_lock_policy options.lock_policy Require_locked in
        loop { options with lock_policy } rest
    | "--warn-locked" :: rest ->
        let* lock_policy = choose_lock_policy options.lock_policy Warn_locked in
        loop { options with lock_policy } rest
    | "--help" :: _ -> Error (command_usage doctor_doc)
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
      json = false;
      lock_policy = Ignore_lock;
    }
    args

let parse_init_args (args : string list) : (init_options, string) result =
  let rec loop (options : init_options) = function
    | [] -> Ok options
    | "--dir" :: dir :: rest -> loop { options with dir } rest
    | "--dir" :: [] -> Error "--dir requires a directory"
    | "--member" :: member_path :: rest ->
        loop { options with member_path = Some member_path } rest
    | "--member" :: [] -> Error "--member requires a path"
    | "--name" :: name :: rest -> loop { options with name = Some name } rest
    | "--name" :: [] -> Error "--name requires a value"
    | "--library" :: name :: rest ->
        loop { options with library = Some name } rest
    | "--library" :: [] -> Error "--library requires a value"
    | "--executable" :: name :: rest ->
        loop { options with executable = Some name } rest
    | "--executable" :: [] -> Error "--executable requires a value"
    | "--bare" :: rest -> loop { options with bare = true } rest
    | "--force" :: rest -> loop { options with force = true } rest
    | "--help" :: _ -> Error (command_usage init_doc)
    | option :: _ when String_util.starts_with ~prefix:"-" option ->
        Error (Printf.sprintf "unknown option '%s'" option)
    | _ :: _ -> Error "init does not accept positional arguments"
  in
  loop
    {
      dir = ".";
      member_path = None;
      name = None;
      library = None;
      executable = None;
      bare = false;
      force = false;
    }
    args

let parse_action_args (args : string list) : (action_options, string) result =
  let rec loop (options : action_options) = function
    | [] -> Ok { options with targets = List.rev options.targets }
    | "--workspace" :: dir :: rest ->
        loop { options with workspace_dir = dir } rest
    | "--workspace" :: [] -> Error "--workspace requires a directory"
    | "--profile" :: profile :: rest ->
        loop { options with profile = Some profile } rest
    | "--profile" :: [] -> Error "--profile requires a name"
    | ("--verbose" | "-v") :: rest ->
        loop { options with verbose = true } rest
    | "--help" :: _ -> Error (command_usage action_doc)
    | option :: _ when String_util.starts_with ~prefix:"-" option ->
        Error (Printf.sprintf "unknown option '%s'" option)
    | target :: rest -> loop { options with targets = target :: options.targets } rest
  in
  loop { workspace_dir = "."; verbose = false; targets = []; profile = None } args

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

let parse_count flag value =
  try
    let parsed = int_of_string value in
    if parsed < 0 then
      Error (Printf.sprintf "%s requires a non-negative integer" flag)
    else Ok parsed
  with
  | Failure _ -> Error (Printf.sprintf "%s requires an integer" flag)

let parse_positive_count flag value =
  let* parsed = parse_count flag value in
  if parsed = 0 then Error (Printf.sprintf "%s requires a positive integer" flag)
  else Ok parsed

let parse_iterations value =
  parse_positive_count "--iterations" value

let parse_bench_args (args : string list) : (bench_options, string) result =
  let* default_backend_request = default_backend_request () in
  let rec loop (options : bench_options) = function
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
    | "--json" :: rest -> loop { options with json = true } rest
    | "--warmup" :: value :: rest ->
        let* warmup = parse_count "--warmup" value in
        loop { options with warmup = Some warmup } rest
    | "--warmup" :: [] -> Error "--warmup requires an integer"
    | "--iterations" :: value :: rest ->
        let* iterations = parse_iterations value in
        loop { options with iterations = Some iterations } rest
    | "--iterations" :: [] -> Error "--iterations requires an integer"
    | "--help" :: _ -> Error (command_usage bench_doc)
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
      json = false;
      warmup = None;
      iterations = None;
    }
    args

let parse_watch_args (args : string list) : (watch_options, string) result =
  let rec loop (options : watch_options) = function
    | [] -> Ok options
    | "--workspace" :: dir :: rest ->
        loop { options with workspace_dir = dir } rest
    | "--workspace" :: [] -> Error "--workspace requires a directory"
    | "--poll-ms" :: value :: rest ->
        let* poll_ms = parse_positive_count "--poll-ms" value in
        loop { options with poll_ms } rest
    | "--poll-ms" :: [] -> Error "--poll-ms requires an integer"
    | "--debounce-ms" :: value :: rest ->
        let* debounce_ms = parse_count "--debounce-ms" value in
        loop { options with debounce_ms } rest
    | "--debounce-ms" :: [] -> Error "--debounce-ms requires an integer"
    | "--max-runs" :: value :: rest ->
        let* max_runs = parse_positive_count "--max-runs" value in
        loop { options with max_runs = Some max_runs } rest
    | "--max-runs" :: [] -> Error "--max-runs requires an integer"
    | "--keep-going" :: rest ->
        loop { options with keep_going = true } rest
    | "--include" :: glob :: rest ->
        loop { options with include_globs = glob :: options.include_globs } rest
    | "--include" :: [] -> Error "--include requires a glob"
    | "--ignore" :: glob :: rest ->
        loop { options with ignore_globs = glob :: options.ignore_globs } rest
    | "--ignore" :: [] -> Error "--ignore requires a glob"
    | "--help" :: _ -> Error (command_usage watch_doc)
    | option :: _ when String_util.starts_with ~prefix:"-" option ->
        Error (Printf.sprintf "unknown option '%s'" option)
    | command_name :: rest ->
        Ok
          {
            options with
            command_name = Some command_name;
            command_args = rest;
            include_globs = List.rev options.include_globs;
            ignore_globs = List.rev options.ignore_globs;
          }
  in
  let* options =
    loop
      {
        workspace_dir = ".";
        poll_ms = 100;
        debounce_ms = 100;
        max_runs = None;
        keep_going = false;
        include_globs = [];
        ignore_globs = [];
        command_name = None;
        command_args = [];
      }
      args
  in
  match options.command_name with
  | Some _ -> Ok options
  | None -> Error "watch requires a subtool name"

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

let parse_promote_args (args : string list) : (promote_options, string) result =
  let rec loop (options : promote_options) = function
    | [] -> Ok { options with targets = List.rev options.targets }
    | "--workspace" :: dir :: rest ->
        loop { options with workspace_dir = dir } rest
    | "--workspace" :: [] -> Error "--workspace requires a directory"
    | "--profile" :: profile :: rest ->
        loop { options with profile = Some profile } rest
    | "--profile" :: [] -> Error "--profile requires a name"
    | ("--verbose" | "-v") :: rest ->
        loop { options with verbose = true } rest
    | "--help" :: _ -> Error (command_usage promote_doc)
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

let parse_lock_args (args : string list) : (lock_options, string) result =
  let rec loop (options : lock_options) = function
    | [] ->
        if options.stdout && Option.is_some options.output_path then
          Error "--stdout cannot be combined with --output"
        else Ok { options with targets = List.rev options.targets }
    | "--workspace" :: dir :: rest ->
        loop { options with workspace_dir = dir } rest
    | "--workspace" :: [] -> Error "--workspace requires a directory"
    | "--output" :: path :: rest ->
        loop { options with output_path = Some path } rest
    | "--output" :: [] -> Error "--output requires a path"
    | "--stdout" :: rest -> loop { options with stdout = true } rest
    | "--help" :: _ -> Error (command_usage lock_doc)
    | option :: _ when String_util.starts_with ~prefix:"-" option ->
        Error (Printf.sprintf "unknown option '%s'" option)
    | target :: rest -> loop { options with targets = target :: options.targets } rest
  in
  loop { workspace_dir = "."; targets = []; output_path = None; stdout = false } args

let parse_ppx_args (args : string list) : (ppx_options, string) result =
  let rec loop (options : ppx_options) = function
    | [] -> Ok options
    | "--workspace" :: dir :: rest ->
        loop { options with workspace_dir = dir } rest
    | "--workspace" :: [] -> Error "--workspace requires a directory"
    | "--profile" :: value :: rest ->
        loop { options with profile = Some value } rest
    | "--profile" :: [] -> Error "--profile requires a name"
    | ("--verbose" | "-v") :: rest ->
        loop { options with verbose = true } rest
    | "--interface" :: rest ->
        loop { options with interface = true } rest
    | "--plan" :: rest -> loop { options with plan = true } rest
    | "--output" :: path :: rest ->
        loop { options with output_path = Some path } rest
    | "--output" :: [] -> Error "--output requires a path"
    | "--help" :: _ -> Error (command_usage ppx_doc)
    | option :: _ when String_util.starts_with ~prefix:"-" option ->
        Error (Printf.sprintf "unknown option '%s'" option)
    | value :: rest -> (
        match (options.target, options.module_name) with
        | None, _ -> loop { options with target = Some value } rest
        | Some _, None ->
            loop { options with module_name = Some value } rest
        | Some _, Some _ -> Error "ppx accepts at most TARGET and MODULE")
  in
  let* options =
    loop
      {
        workspace_dir = ".";
        verbose = false;
        target = None;
        module_name = None;
        profile = None;
        interface = false;
        output_path = None;
        plan = false;
      }
      args
  in
  match (options.target, options.module_name, options.plan, options.output_path) with
  | None, _, _, _ -> Error "ppx requires a target name"
  | Some _, None, false, Some _ ->
      Error "ppx --output requires MODULE unless --plan is set"
  | Some _, None, _, _ when options.interface ->
      Error "ppx --interface requires MODULE"
  | Some _, _, true, Some _ ->
      Error "ppx --plan cannot be combined with --output"
  | Some _, _, _, _ -> Ok options

let parse_vendor_args (args : string list) : (vendor_options, string) result =
  let rec loop (options : vendor_options) = function
    | [] -> Ok options
    | "--workspace" :: dir :: rest ->
        loop { options with workspace_dir = dir } rest
    | "--workspace" :: [] -> Error "--workspace requires a directory"
    | "--source" :: dir :: rest ->
        loop { options with source_dir = Some dir } rest
    | "--source" :: [] -> Error "--source requires a directory"
    | "--git" :: url :: rest ->
        loop { options with git_url = Some url } rest
    | "--git" :: [] -> Error "--git requires a URL"
    | "--url" :: url :: rest ->
        loop { options with archive_url = Some url } rest
    | "--url" :: [] -> Error "--url requires a URL"
    | "--ref" :: value :: rest ->
        loop { options with ref_name = Some value } rest
    | "--ref" :: [] -> Error "--ref requires a value"
    | "--checksum" :: value :: rest ->
        loop { options with checksum = Some value } rest
    | "--checksum" :: [] -> Error "--checksum requires a value"
    | "--name" :: name :: rest -> loop { options with name = Some name } rest
    | "--name" :: [] -> Error "--name requires a value"
    | "--force" :: rest -> loop { options with force = true } rest
    | "--help" :: _ -> Error (command_usage vendor_doc)
    | option :: _ when String_util.starts_with ~prefix:"-" option ->
        Error (Printf.sprintf "unknown option '%s'" option)
    | _ :: _ ->
        Error
          "vendor does not accept positional arguments; use --source DIR, --git URL, or --url URL"
  in
  let* options =
    loop
      {
        workspace_dir = ".";
        source_dir = None;
        git_url = None;
        archive_url = None;
        ref_name = None;
        checksum = None;
        name = None;
        force = false;
      }
      args
  in
  let selected_source_count =
    List.length
      (List.filter Option.is_some
         [ options.source_dir; options.git_url; options.archive_url ])
  in
  if selected_source_count = 0 then
    Error "vendor requires one of --source DIR, --git URL, or --url URL"
  else if selected_source_count > 1 then
    Error "vendor accepts exactly one of --source DIR, --git URL, or --url URL"
  else if options.ref_name <> None && options.git_url = None then
    Error "vendor --ref requires --git URL"
  else if options.checksum <> None && options.source_dir <> None then
    Error "vendor --checksum is only valid with --git URL or --url URL"
  else if
    (options.git_url <> None || options.archive_url <> None)
    && options.checksum = None
  then
    Error "vendor remote sources require --checksum VALUE"
  else Ok options

let parse_env_args (args : string list) : (env_options, string) result =
  let rec loop workspace_dir profile json changed_only subtool targets = function
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
                changed_only;
              } )
    | "--workspace" :: dir :: rest ->
        loop dir profile json changed_only subtool targets rest
    | "--workspace" :: [] -> Error "--workspace requires a directory"
    | "--profile" :: value :: rest ->
        loop workspace_dir (Some value) json changed_only subtool targets rest
    | "--profile" :: [] -> Error "--profile requires a name"
    | "--json" :: rest ->
        loop workspace_dir profile true changed_only subtool targets rest
    | "--changed-only" :: rest ->
        loop workspace_dir profile json true subtool targets rest
    | "--help" :: _ -> Error (command_usage env_doc)
    | option :: _ when String_util.starts_with ~prefix:"-" option ->
        Error (Printf.sprintf "unknown option '%s'" option)
    | value :: rest -> (
        match subtool with
        | None ->
            let* subtool = Env_report.parse_subtool value in
            loop workspace_dir profile json changed_only (Some subtool) targets
              rest
        | Some Env_report.Run when targets <> [] ->
            Error "env run accepts at most one target"
        | Some _ ->
            loop workspace_dir profile json changed_only subtool
              (value :: targets) rest)
  in
  loop "." None false false None [] args

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
    | "--plan" :: rest -> loop { options with plan = true } rest
    | "--json" :: rest -> loop { options with json = true } rest
    | "--script" :: path :: rest ->
        loop { options with script_path = Some path } rest
    | "--script" :: [] -> Error "--script requires a path"
    | "--help" :: _ -> Error (command_usage repl_doc)
    | option :: _ when String_util.starts_with ~prefix:"-" option ->
        Error (Printf.sprintf "unknown option '%s'" option)
    | value :: rest -> (
        match options.target with
        | None -> loop { options with target = Some value } rest
        | Some _ -> Error "repl accepts at most one target before --")
  in
  let* options =
    loop
      {
        workspace_dir = ".";
        verbose = false;
        target = None;
        args = [];
        profile = None;
        script_path = None;
        plan = false;
        json = false;
      }
      args
  in
  if options.json && not options.plan then
    Error "repl --json requires --plan"
  else Ok options

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
    | "--locked" :: rest ->
        let* lock_policy = choose_lock_policy options.lock_policy Require_locked in
        loop { options with lock_policy } rest
    | "--warn-locked" :: rest ->
        let* lock_policy = choose_lock_policy options.lock_policy Warn_locked in
        loop { options with lock_policy } rest
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
      lock_policy = Ignore_lock;
    }
    args

let parse_release_artifacts_args args =
  let rec loop output_dir = function
    | [] -> Ok { output_dir }
    | "--output-dir" :: dir :: rest -> loop dir rest
    | "--output-dir" :: [] -> Error "--output-dir requires a directory"
    | "--help" :: _ -> Error (command_usage release_artifacts_doc)
    | option :: _ when String_util.starts_with ~prefix:"-" option ->
        Error (Printf.sprintf "unknown option '%s'" option)
    | _ :: _ -> Error "release-artifacts does not accept positional arguments"
  in
  loop "." args

let parse_package_args args =
  let choose_archive_input current next =
    match current with
    | None -> Ok (Some next)
    | Some _ ->
        Error
          "pass only one of --source-archive, --source-archive-dir, or --reuse-source-archive-dir"
  in
  let rec loop options = function
    | [] -> Ok options
    | "--output-dir" :: dir :: rest -> loop { options with output_dir = dir } rest
    | "--output-dir" :: [] -> Error "--output-dir requires a directory"
    | "--opam-output" :: path :: rest ->
        loop { options with opam_output = Some path } rest
    | "--opam-output" :: [] -> Error "--opam-output requires a path"
    | "--formula-output" :: path :: rest ->
        loop { options with formula_output = Some path } rest
    | "--formula-output" :: [] -> Error "--formula-output requires a path"
    | "--checksums-output" :: path :: rest ->
        loop { options with checksums_output = Some path } rest
    | "--checksums-output" :: [] -> Error "--checksums-output requires a path"
    | "--asset-index-output" :: path :: rest ->
        loop { options with asset_index_output = Some path } rest
    | "--asset-index-output" :: [] -> Error "--asset-index-output requires a path"
    | "--source-archive" :: path :: rest ->
        let* archive_input =
          choose_archive_input options.archive_input (Packager.Source_archive path)
        in
        loop { options with archive_input } rest
    | "--source-archive" :: [] -> Error "--source-archive requires a path"
    | "--source-archive-dir" :: dir :: rest ->
        let* archive_input =
          choose_archive_input options.archive_input
            (Packager.Source_archive_dir dir)
        in
        loop { options with archive_input } rest
    | "--source-archive-dir" :: [] ->
        Error "--source-archive-dir requires a directory"
    | "--reuse-source-archive-dir" :: dir :: rest ->
        let* archive_input =
          choose_archive_input options.archive_input
            (Packager.Reuse_source_archive_dir dir)
        in
        loop { options with archive_input } rest
    | "--reuse-source-archive-dir" :: [] ->
        Error "--reuse-source-archive-dir requires a directory"
    | "--source-archive-mode" :: mode :: rest ->
        let* source_archive_mode = Packager.parse_source_archive_mode mode in
        loop { options with source_archive_mode } rest
    | "--source-archive-mode" :: [] ->
        Error "--source-archive-mode requires tracked or worktree"
    | "--help" :: _ -> Error (command_usage package_doc)
    | option :: _ when String_util.starts_with ~prefix:"-" option ->
        Error (Printf.sprintf "unknown option '%s'" option)
    | _ :: _ -> Error "package does not accept positional arguments"
  in
  let* options =
    loop
      {
        output_dir = ".";
        opam_output = None;
        formula_output = None;
        checksums_output = None;
        asset_index_output = None;
        archive_input = None;
        source_archive_mode = Packager.Tracked;
      }
      args
  in
  Ok options

let parse_sync_generated_args args =
  match args with
  | [] -> Ok ()
  | "--help" :: _ -> Error (command_usage sync_generated_doc)
  | option :: _ when String_util.starts_with ~prefix:"-" option ->
      Error (Printf.sprintf "unknown option '%s'" option)
  | _ :: _ -> Error "sync-generated does not accept positional arguments"

let parse_release_cut_args args =
  let rec loop options = function
    | [] -> Ok options
    | "--version" :: version :: rest ->
        loop { options with version = Some version } rest
    | "--version" :: [] -> Error "--version requires a value"
    | "--tag" :: rest -> loop { options with tag = true } rest
    | "--help" :: _ -> Error (command_usage release_cut_doc)
    | option :: _ when String_util.starts_with ~prefix:"-" option ->
        Error (Printf.sprintf "unknown option '%s'" option)
    | _ :: _ -> Error "release-cut does not accept positional arguments"
  in
  loop { version = None; tag = false } args

let parse_update_homebrew_tap_args args =
  let rec loop options = function
    | [] -> Ok options
    | "--tap-dir" :: dir :: rest -> loop { options with tap_dir = Some dir } rest
    | "--tap-dir" :: [] -> Error "--tap-dir requires a directory"
    | "--formula" :: path :: rest ->
        loop { options with formula_path = Some path } rest
    | "--formula" :: [] -> Error "--formula requires a path"
    | "--source-archive" :: path :: rest ->
        loop { options with source_archive = Some path } rest
    | "--source-archive" :: [] -> Error "--source-archive requires a path"
    | "--commit" :: rest -> loop { options with commit = true } rest
    | "--push" :: rest -> loop { options with push = true } rest
    | "--help" :: _ -> Error (command_usage update_homebrew_tap_doc)
    | option :: _ when String_util.starts_with ~prefix:"-" option ->
        Error (Printf.sprintf "unknown option '%s'" option)
    | _ :: _ ->
        Error "update-homebrew-tap does not accept positional arguments"
  in
  loop
    {
      tap_dir = None;
      formula_path = None;
      source_archive = None;
      commit = false;
      push = false;
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

let bench_target_candidates workspace =
  List.map
    (fun (bench : Manifest.bench_target) ->
      candidate ?hint:bench.package_path bench.name)
    workspace.Manifest.benches
  @ executable_target_candidates workspace

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
  | "--output" | "--output-dir" | "--opam-output" | "--formula-output"
  | "--checksums-output" | "--asset-index-output" | "--source-archive"
  | "--source-archive-dir" | "--reuse-source-archive-dir"
  | "--source-archive-mode" | "--script"
  | "--warmup" | "--iterations" | "--dir" | "--name" | "--member"
  | "--library" | "--executable" | "--source" | "--git" | "--url"
  | "--ref" | "--checksum" | "--poll-ms" | "--debounce-ms" | "--max-runs"
  | "--include" | "--ignore" | "--version" | "--tap-dir" | "--formula" ->
      true
  | _ -> false

let watch_option_expects_value = function
  | "--workspace" | "--poll-ms" | "--debounce-ms" | "--max-runs"
  | "--include" | "--ignore" ->
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
      | "watch" when positional_argument_count rest = 0 ->
          List.filter_map
            (fun (doc : command_doc) ->
              if doc.name = "watch" then None else Some (candidate doc.name))
            command_docs
      | "completion" when positional_argument_count rest = 0 ->
          List.map (fun word -> candidate word) completion_doc.completion_words
      | "env" when positional_argument_count rest = 0 ->
          List.map (fun word -> candidate word) env_doc.completion_words
      | _ -> [] )
  | Some workspace -> (
      match command_name with
      | "build" | "status" | "doctor" | "action" | "clean" | "promote"
      | "graph" | "deps" | "lock" | "explain" ->
          List.map target_candidate workspace.Manifest.targets
      | "watch" when positional_argument_count rest = 0 ->
          List.filter_map
            (fun (doc : command_doc) ->
              if doc.name = "watch" then None else Some (candidate doc.name))
            command_docs
      | "ppx" ->
          if positional_argument_count rest = 0 then
            List.map target_candidate workspace.Manifest.targets
          else []
      | "run" ->
          if positional_argument_count rest = 0 then
            executable_target_candidates workspace
          else []
      | "test" -> test_target_candidates workspace
      | "bench" -> bench_target_candidates workspace
      | "repl" ->
          if positional_argument_count rest = 0 then
            List.map target_candidate workspace.Manifest.targets
          else []
      | "env" -> (
          match positional_arguments [] rest with
          | [] -> List.map (fun word -> candidate word) env_doc.completion_words
          | [ "build" ] -> List.map target_candidate workspace.Manifest.targets
          | [ "action" ] -> List.map target_candidate workspace.Manifest.targets
          | [ "run" ] -> executable_target_candidates workspace
          | [ "test" ] -> test_target_candidates workspace
          | [ "bench" ] -> bench_target_candidates workspace
          | [ "install" ] -> installable_target_candidates workspace
          | _ -> [] )
      | "install" -> installable_target_candidates workspace
      | "completion" when positional_argument_count rest = 0 ->
          List.map (fun word -> candidate word) completion_doc.completion_words
      | "docs" | "init" | "toolchain" | "migrate" | "vendor" -> []
      | _ -> [])

let value_completion_candidates ?workspace = function
  | "--profile" -> (
      match workspace with
      | Some workspace ->
          List.map (fun word -> candidate word) (profile_names workspace)
      | None -> [])
  | "--backend" -> List.map (fun word -> candidate word) backend_completion_words
  | "--workspace" | "--prefix" | "--destdir" | "--output" | "--output-dir"
  | "--opam-output" | "--formula-output" | "--checksums-output"
  | "--asset-index-output" | "--source-archive" | "--source-archive-dir"
  | "--reuse-source-archive-dir" | "--script" | "--dir" | "--name"
  | "--member" | "--library" | "--executable" | "--source" | "--git"
  | "--url" | "--ref" | "--checksum" | "--version" | "--tap-dir"
  | "--formula" ->
      []
  | "--source-archive-mode" ->
      List.map (fun word -> candidate word) [ "tracked"; "worktree" ]
  | _ -> []

let value_completion_response ?workspace = function
  | "--workspace" | "--prefix" | "--destdir" | "--dir" | "--source"
  | "--output-dir" | "--source-archive-dir" | "--reuse-source-archive-dir"
  | "--tap-dir" ->
      Complete_directories
  | "--member" -> Complete_directories
  | "--output" | "--opam-output" | "--formula-output"
  | "--checksums-output" | "--asset-index-output" | "--source-archive"
  | "--script" | "--formula" ->
      Complete_files
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

let completion_candidates_response ~current candidates =
  Completion_candidates (filter_completion_candidates ~current candidates)

let root_command_candidates () = List.map (fun doc -> candidate doc.name) command_docs

let rec watch_subtool_tokens = function
  | [] -> None
  | "--workspace" :: _ :: rest
  | "--poll-ms" :: _ :: rest
  | "--debounce-ms" :: _ :: rest
  | "--max-runs" :: _ :: rest
  | "--include" :: _ :: rest
  | "--ignore" :: _ :: rest ->
      watch_subtool_tokens rest
  | "--keep-going" :: rest | "--help" :: rest -> watch_subtool_tokens rest
  | option :: [] when watch_option_expects_value option -> None
  | option :: _ when String_util.starts_with ~prefix:"-" option -> None
  | command_name :: rest -> Some (command_name, rest)

let render_value_completion ?workspace ~current option_name =
  match value_completion_response ?workspace option_name with
  | Complete_directories -> Complete_directories
  | Complete_files -> Complete_files
  | Completion_candidates candidates ->
      completion_candidates_response ~current candidates

let watch_command_candidates () =
  List.filter_map
    (fun (doc : command_doc) ->
      if doc.name = "watch" then None else Some (candidate doc.name))
    command_docs

let resolve_path_from cwd path =
  let path =
    if Filename.is_relative path then Filename.concat cwd path else path
  in
  Fs.realpath path

let watch_inner_workspace_dir args =
  let rec loop current = function
    | [] | "--" :: _ -> current
    | "--workspace" :: dir :: rest -> loop (Some dir) rest
    | "--workspace" :: [] -> current
    | option :: _ :: rest when option_expects_value option -> loop current rest
    | _ :: rest -> loop current rest
  in
  loop None args

let rec completion_response workspace ~previous ~current =
  match previous with
  | [] -> completion_candidates_response ~current (root_command_candidates ())
  | "watch" :: rest -> watch_completion_response workspace ~rest ~current
  | command_name :: rest ->
      default_completion_response workspace command_name rest ~current

and watch_completion_response workspace ~rest ~current =
  match watch_subtool_tokens rest with
  | Some ("watch", _) -> Completion_candidates []
  | Some (command_name, inner_rest) -> (
      match find_command_doc command_name with
      | None -> Completion_candidates []
      | Some _ ->
          completion_response workspace ~previous:(command_name :: inner_rest)
            ~current)
  | None -> (
      match List.rev rest with
      | option_name :: _ when watch_option_expects_value option_name ->
          render_value_completion ?workspace ~current option_name
      | _ ->
          let flags = command_flag_words watch_doc in
          let candidates =
            if String_util.starts_with ~prefix:"-" current then
              List.map (fun flag -> candidate flag) flags
            else watch_command_candidates () @ List.map (fun flag -> candidate flag) flags
          in
          completion_candidates_response ~current candidates)

and default_completion_response workspace command_name rest ~current =
  match find_command_doc command_name with
  | None -> completion_candidates_response ~current (root_command_candidates ())
  | Some doc when List.mem "--" rest -> Completion_candidates []
  | Some doc -> (
      match List.rev rest with
      | option_name :: _ when option_expects_value option_name ->
          render_value_completion ?workspace ~current option_name
      | _ ->
          let flags = command_flag_words doc in
          let candidates =
            if String_util.starts_with ~prefix:"-" current then
              List.map (fun flag -> candidate flag) flags
            else
              positional_completion_candidates ?workspace command_name rest
              @ List.map (fun flag -> candidate flag) flags
          in
          completion_candidates_response ~current candidates)

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
               "target '%s' is a library; wadi run only supports executables"
               name)
      | Some (Manifest.Test _) ->
          Error
            (Printf.sprintf
               "target '%s' is a test; wadi run only supports executables"
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

let validate_lock_policy lock_policy ~workspace_root workspace requested_targets =
  match lock_policy with
  | Ignore_lock -> Ok ()
  | Warn_locked -> (
      match
        Locker.validate_current ~workspace_root workspace requested_targets
      with
      | Ok () -> Ok ()
      | Error message ->
          prerr_endline ("wadi: warning: " ^ message);
          Ok ())
  | Require_locked ->
      Locker.validate_current ~workspace_root workspace requested_targets

let run_build (options : build_options) =
  match load_workspace options.workspace_dir with
  | Error message -> report_error message
  | Ok workspace -> (
      match
        validate_lock_policy options.lock_policy
          ~workspace_root:options.workspace_dir workspace options.targets
      with
      | Ok () -> (
          match
            Builder.build ~workspace_root:options.workspace_dir
              ~verbose:options.verbose ~requested_targets:options.targets
              ~backend_request:options.backend_request ?profile:options.profile
              workspace
          with
          | Ok _ -> Exit_code 0
          | Error message -> report_error message)
      | Error message -> report_error message)

let run_status_command (options : status_options) =
  match load_workspace options.workspace_dir with
  | Error message -> report_error message
  | Ok workspace -> (
      match
        Status.report ~workspace_root:options.workspace_dir
          ~requested_targets:options.targets
          ~backend_request:options.backend_request ?profile:options.profile
          workspace
      with
      | Ok report ->
          print_string
            (if options.json then Status.render_json_report report
             else Status.render_report report);
          Exit_code 0
      | Error message -> report_error message)

let doctor_lock_policy = function
  | Ignore_lock -> Doctor.Warn_locked
  | Warn_locked -> Doctor.Warn_locked
  | Require_locked -> Doctor.Require_locked

let run_doctor (options : doctor_options) =
  match load_workspace options.workspace_dir with
  | Error message -> report_error message
  | Ok workspace -> (
      match
        Doctor.report ~workspace_root:options.workspace_dir
          ~requested_targets:options.targets
          ~backend_request:options.backend_request ?profile:options.profile
          ~lock_policy:(doctor_lock_policy options.lock_policy)
          workspace
      with
      | Ok report ->
          print_string
            (if options.json then Doctor.render_json_report report
             else Doctor.render_report report);
          Exit_code (if Doctor.has_failures report then 1 else 0)
      | Error message -> report_error message)

let run_watch (options : watch_options) =
  let workspace_root = Fs.realpath options.workspace_dir in
  if not (Fs.is_directory workspace_root) then
    report_error
      (Printf.sprintf "workspace directory does not exist: %s" options.workspace_dir)
  else
    let manifest_path = Filename.concat workspace_root Manifest.default_filename in
    if not (Fs.exists manifest_path) then
      report_error (Printf.sprintf "manifest not found: %s" manifest_path)
    else (
      let start_watch command_name command_root_files =
        match
          Watch.run
            {
              Watch.workspace_root = workspace_root;
              poll_ms = options.poll_ms;
              debounce_ms = options.debounce_ms;
              max_runs = options.max_runs;
              keep_going = options.keep_going;
              cli_include_globs = options.include_globs;
              cli_ignore_globs = options.ignore_globs;
              command_name;
              command_args = options.command_args;
              command_root_files;
            }
        with
        | Ok status -> Forward_status status
        | Error message -> report_error message
      in
      match options.command_name with
      | None -> report_error "watch requires a subtool name"
      | Some "watch" ->
          report_error "watch cannot watch itself; choose another subtool"
      | Some command_name -> (
          match find_command_doc command_name with
          | None ->
              report_error
                (Printf.sprintf "unknown subtool '%s' for watch" command_name)
          | Some doc -> (
              match watch_inner_workspace_dir options.command_args with
              | Some inner_workspace_dir ->
                  let inner_workspace_root =
                    resolve_path_from workspace_root inner_workspace_dir
                  in
                  if inner_workspace_root <> workspace_root then
                    report_error
                      (Printf.sprintf
                         "watch subtool workspace %s conflicts with watched \
                          workspace %s; remove the inner --workspace or point \
                          it at the same tree"
                         inner_workspace_root workspace_root)
                  else
                    start_watch command_name
                      (doc.watch_root_files options.command_args)
              | None ->
                  start_watch command_name
                    (doc.watch_root_files options.command_args))))

let run_init (options : init_options) =
  match
    Init.init ~root_dir:options.dir ?name:options.name ?library:options.library
      ?executable:options.executable ?member:options.member_path
      ~bare:options.bare ~force:options.force ()
  with
  | Ok report ->
      print_string (Init.render_report report);
      Exit_code 0
  | Error message -> report_error message

let run_action_command (options : action_options) =
  match load_workspace options.workspace_dir with
  | Error message -> report_error message
  | Ok workspace -> (
      match
        Actioner.run ~workspace_root:options.workspace_dir
          ~verbose:options.verbose ?profile:options.profile
          ~requested_targets:options.targets workspace
      with
      | Ok reports ->
          print_string (Actioner.render_report reports);
          Exit_code 0
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

let run_bench (options : bench_options) =
  match load_workspace options.workspace_dir with
  | Error message -> report_error message
  | Ok workspace -> (
      match
        Bench.report ~workspace_root:options.workspace_dir
          ~verbose:options.verbose ~backend_request:options.backend_request
          ?profile:options.profile ?warmup:options.warmup
          ?iterations:options.iterations ~requested_targets:options.targets
          workspace
      with
      | Ok summaries ->
          print_string
            (if options.json then Bench.render_json_report summaries
             else Bench.render_report summaries);
          Exit_code 0
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

let run_promote (options : promote_options) =
  match load_workspace options.workspace_dir with
  | Error message -> report_error message
  | Ok workspace -> (
      match
        Promoter.promote ~workspace_root:options.workspace_dir
          ~verbose:options.verbose ?profile:options.profile
          ~requested_targets:options.targets workspace
      with
      | Ok promoted ->
          print_string (Promoter.render_report promoted);
          Exit_code 0
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

let run_lock (options : lock_options) =
  match load_workspace options.workspace_dir with
  | Error message -> report_error message
  | Ok workspace -> (
      match
        Locker.create ~workspace_root:options.workspace_dir workspace options.targets
      with
      | Error message -> report_error message
      | Ok report ->
          let json = Locker.render_json report in
          if options.stdout then (
            print_string json;
            Exit_code 0)
          else
            let output_path =
              match options.output_path with
              | Some path -> path
              | None ->
                  Filename.concat options.workspace_dir Locker.default_lock_filename
            in
            if Fs.is_directory output_path then
              report_error (Printf.sprintf "output path is a directory: %s" output_path)
            else (
              Fs.write_file output_path json;
              print_endline ("Wrote lock file " ^ output_path);
              Exit_code 0))

let run_ppx (options : ppx_options) =
  match load_workspace options.workspace_dir with
  | Error message -> report_error message
  | Ok workspace -> (
      let profile = resolve_profile workspace options.profile in
      match options.target with
      | None -> report_error "ppx requires a target name"
      | Some target_name ->
          if options.plan || options.module_name = None then
            match
              Ppx_tool.plan ~workspace_root:options.workspace_dir
                ~verbose:options.verbose ?module_name:options.module_name
                ~interface:options.interface ~profile workspace target_name
            with
            | Ok plan ->
                print_string
                  (Ppx_tool.render_plan ~workspace_root:options.workspace_dir
                     plan);
                Exit_code 0
            | Error message -> report_error message
          else
            match options.module_name with
            | None -> report_error "ppx requires MODULE unless --plan is used"
            | Some module_name -> (
                match
                  Ppx_tool.apply ~workspace_root:options.workspace_dir
                    ~verbose:options.verbose ~interface:options.interface
                    ?output_path:options.output_path ~profile workspace
                    target_name module_name
                with
                | Ok applied ->
                    print_string
                      (Ppx_tool.render_applied_report options.output_path
                         applied);
                    Exit_code 0
                | Error message -> report_error message))

let run_vendor (options : vendor_options) =
  let source =
    match (options.source_dir, options.git_url, options.archive_url) with
    | Some source_dir, None, None -> Ok (Vendor.Local_dir source_dir)
    | None, Some git_url, None -> (
        match options.checksum with
        | Some checksum ->
            Ok
              (Vendor.Git_repo
                 { url = git_url; ref_name = options.ref_name; checksum })
        | None -> Error "vendor remote sources require --checksum VALUE")
    | None, None, Some archive_url -> (
        match options.checksum with
        | Some checksum -> Ok (Vendor.Url_archive { url = archive_url; checksum })
        | None -> Error "vendor remote sources require --checksum VALUE")
    | _ ->
        Error "vendor requires exactly one of --source DIR, --git URL, or --url URL"
  in
  match source with
  | Error message -> report_error message
  | Ok source -> (
      match
        Vendor.vendor ~workspace_root:options.workspace_dir source
          ?name:options.name ~force:options.force ()
      with
      | Ok report ->
          print_string (Vendor.render_report report);
          Exit_code 0
      | Error message -> report_error message)

let run_env (options : env_options) =
  match load_workspace options.workspace_dir with
  | Error message -> report_error message
  | Ok workspace -> (
      match
        Env_report.report ~workspace_root:options.workspace_dir
          ?profile:options.profile ~changed_only:options.changed_only workspace
          options.subtool options.targets
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
      if options.plan then
        match
          Repl.report ~workspace_root:options.workspace_dir
            ~verbose:options.verbose ?profile:options.profile
            ?target:options.target ?script_path:options.script_path
            ~args:options.args workspace
        with
        | Ok plan ->
            print_string
              (if options.json then Repl.render_json_plan plan
               else Repl.render_plan plan);
            Exit_code 0
        | Error message -> report_error message
      else
        match
          Repl.run ~workspace_root:options.workspace_dir ~verbose:options.verbose
            ?profile:options.profile ?target:options.target
            ?script_path:options.script_path ~args:options.args workspace
        with
        | Ok status -> Forward_status status
        | Error message -> report_error message)

let run_install (options : install_options) =
  match load_workspace options.workspace_dir with
  | Error message -> report_error message
  | Ok workspace -> (
      match
        validate_lock_policy options.lock_policy
          ~workspace_root:options.workspace_dir workspace options.targets
      with
      | Ok () -> (
          match
            Installer.install ~workspace_root:options.workspace_dir
              ~verbose:options.verbose ~backend_request:options.backend_request
              ?profile:options.profile ?prefix:options.prefix
              ?destdir:options.destdir ~requested_targets:options.targets
              workspace
          with
          | Ok status -> Exit_code status
          | Error message -> report_error message)
      | Error message -> report_error message)

let generate_release_artifacts ~root_dir ~output_dir =
  match Release_metadata.load_for_root ~root_dir () with
  | Error message -> report_error message
  | Ok metadata -> (
      match
        completion_script "bash",
        completion_script "zsh",
        completion_script "fish"
      with
      | Ok bash, Ok zsh, Ok fish ->
          Release_artifacts.write ~output_dir
            ~package_name:metadata.package_name
            ~docs:(render_markdown command_docs) ~bash ~zsh ~fish;
          Exit_code 0
      | Error message, _, _ | _, Error message, _ | _, _, Error message ->
          report_error message)

let run_release_artifacts (options : release_artifacts_options) =
  generate_release_artifacts ~root_dir:(Sys.getcwd ()) ~output_dir:options.output_dir

let generate_package ~root_dir (options : package_options) =
  match
    Packager.run
      {
        root_dir;
        output_dir = options.output_dir;
        opam_output = options.opam_output;
        formula_output = options.formula_output;
        checksums_output = options.checksums_output;
        asset_index_output = options.asset_index_output;
        archive_input = options.archive_input;
        source_archive_mode = options.source_archive_mode;
      }
  with
  | Ok () -> Exit_code 0
  | Error message -> report_error message

let run_package (options : package_options) =
  generate_package ~root_dir:(Sys.getcwd ()) options

let run_sync_generated (_options : sync_generated_options) =
  let root_dir = Sys.getcwd () in
  match Maintenance.refresh_bootstrap_seed_metadata ~root_dir with
  | Error message -> report_error message
  | Ok _ -> (
      match generate_release_artifacts ~root_dir ~output_dir:root_dir with
      | Exit_code 0 -> (
          match
            generate_package ~root_dir
              {
                output_dir = root_dir;
                opam_output = None;
                formula_output = None;
                checksums_output = None;
                asset_index_output =
                  Some
                    (Filename.concat (Filename.concat root_dir "dist")
                       "release-assets.json");
                archive_input =
                  Some
                    (Packager.Source_archive_dir
                       (Filename.concat root_dir "dist"));
                source_archive_mode = Packager.Tracked;
              }
          with
          | Exit_code 0 -> Exit_code 0
          | other -> other)
      | other -> other)

let run_release_cut (options : release_cut_options) =
  match options.version with
  | None -> report_error "--version is required"
  | Some version -> (
      match
        Maintenance.cut_release ~root_dir:(Sys.getcwd ()) ~version
          ~create_tag:options.tag
      with
      | Ok message ->
          print_endline message;
          Exit_code 0
      | Error message -> report_error message)

let run_update_homebrew_tap (options : update_homebrew_tap_options) =
  match options.tap_dir with
  | None -> report_error "--tap-dir is required"
  | Some tap_dir ->
      let maintenance_options : Maintenance.update_homebrew_tap_options =
        {
          root_dir = Sys.getcwd ();
          tap_dir;
          formula_path = options.formula_path;
          source_archive = options.source_archive;
          do_commit = options.commit;
          do_push = options.push;
        }
      in
      (match Maintenance.update_homebrew_tap maintenance_options with
      | Ok message ->
          print_endline message;
          Exit_code 0
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
          | Complete_files ->
              print_endline (completion_protocol_header "files");
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
    Command { doc = init_doc; parse = parse_init_args; run = run_init };
    Command { doc = build_doc; parse = parse_build_args; run = run_build };
    Command
      { doc = status_doc; parse = parse_status_args; run = run_status_command };
    Command { doc = doctor_doc; parse = parse_doctor_args; run = run_doctor };
    Command { doc = watch_doc; parse = parse_watch_args; run = run_watch };
    Command { doc = action_doc; parse = parse_action_args; run = run_action_command };
    Command { doc = ppx_doc; parse = parse_ppx_args; run = run_ppx };
    Command { doc = graph_doc; parse = parse_graph_args; run = run_graph };
    Command { doc = run_doc; parse = parse_run_args; run = run_executable };
    Command { doc = test_doc; parse = parse_test_args; run = run_tests };
    Command { doc = bench_doc; parse = parse_bench_args; run = run_bench };
    Command { doc = clean_doc; parse = parse_clean_args; run = run_clean };
    Command { doc = promote_doc; parse = parse_promote_args; run = run_promote };
    Command { doc = deps_doc; parse = parse_deps_args; run = run_deps };
    Command { doc = lock_doc; parse = parse_lock_args; run = run_lock };
    Command { doc = vendor_doc; parse = parse_vendor_args; run = run_vendor };
    Command { doc = env_doc; parse = parse_env_args; run = run_env };
    Command { doc = repl_doc; parse = parse_repl_args; run = run_repl };
    Command { doc = install_doc; parse = parse_install_args; run = run_install };
    Command
      {
        doc = release_artifacts_doc;
        parse = parse_release_artifacts_args;
        run = run_release_artifacts;
      };
    Command { doc = package_doc; parse = parse_package_args; run = run_package };
    Command
      {
        doc = sync_generated_doc;
        parse = parse_sync_generated_args;
        run = run_sync_generated;
      };
    Command
      {
        doc = release_cut_doc;
        parse = parse_release_cut_args;
        run = run_release_cut;
      };
    Command
      {
        doc = update_homebrew_tap_doc;
        parse = parse_update_homebrew_tap_args;
        run = run_update_homebrew_tap;
      };
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
