type options = {
  workspace_root : string;
  poll_ms : int;
  debounce_ms : int;
  max_runs : int option;
  keep_going : bool;
  command_name : string;
  command_args : string list;
  cli_include_globs : string list;
  cli_ignore_globs : string list;
}

type root_file = {
  relative_path : string;
  reload_policy : bool;
  select_for_rerun : bool;
}

type compiled_options = {
  workspace_root : string;
  poll_ms : int;
  debounce_ms : int;
  max_runs : int option;
  keep_going : bool;
  command_name : string;
  command_args : string list;
  executable_path : string;
  cli_include_globs : string list;
  cli_ignore_globs : string list;
  root_files : root_file list;
}

let default_ignore_globs = [ ".git/**"; "_oasis/**"; "_bootstrap/**" ]

let ignore_file_name = ".oasiswatchignore"

let manifest_relative_path = Manifest.default_filename

let lock_relative_path workspace_root =
  Locker.default_lock_path workspace_root |> Filename.basename

type policy = {
  include_globs_text : string list;
  ignore_globs_text : string list;
  include_globs : string list list;
  ignore_globs : string list list;
}

type state = {
  policy : policy;
  selected_snapshot : string list;
  control_snapshot : string list;
}

let ( let* ) = Result.bind

let command_line command_name command_args =
  String.concat " " (command_name :: command_args)

let sleep_ms milliseconds =
  ignore (Unix.select [] [] [] (float_of_int milliseconds /. 1000.0))

let normalize_relative_path value =
  let rec drop_dot_prefix value =
    if String_util.starts_with ~prefix:"./" value then
      drop_dot_prefix (String.sub value 2 (String.length value - 2))
    else value
  in
  let normalized = value |> String.trim |> drop_dot_prefix in
  if normalized = "." then "" else normalized

let split_glob_segments value =
  normalize_relative_path value |> String.split_on_char '/'
  |> List.filter (fun segment -> segment <> "")

let rec segment_matches pattern segment =
  let pattern_length = String.length pattern in
  let segment_length = String.length segment in
  let rec loop pattern_index segment_index =
    if pattern_index >= pattern_length then segment_index >= segment_length
    else
      match pattern.[pattern_index] with
      | '*' ->
          loop (pattern_index + 1) segment_index
          || (segment_index < segment_length
             && loop pattern_index (segment_index + 1))
      | '?' ->
          segment_index < segment_length
          && loop (pattern_index + 1) (segment_index + 1)
      | ch ->
          segment_index < segment_length
          && Char.equal ch segment.[segment_index]
          && loop (pattern_index + 1) (segment_index + 1)
  in
  loop 0 0

let rec glob_matches pattern path =
  match (pattern, path) with
  | [], [] -> true
  | [], _ -> false
  | "**" :: rest, _ ->
      glob_matches rest path
      ||
      (match path with
      | _ :: path_rest -> glob_matches pattern path_rest
      | [] -> false)
  | pattern_segment :: pattern_rest, path_segment :: path_rest ->
      segment_matches pattern_segment path_segment
      && glob_matches pattern_rest path_rest
  | _ -> false

let rec glob_covers_prefix pattern path =
  match path with
  | [] -> true
  | path_segment :: path_rest -> (
      match pattern with
      | [] -> false
      | "**" :: rest ->
          glob_covers_prefix rest path || glob_covers_prefix pattern path_rest
      | pattern_segment :: pattern_rest ->
          segment_matches pattern_segment path_segment
          && glob_covers_prefix pattern_rest path_rest)

let matches_any_glob globs relative_path =
  let path = split_glob_segments relative_path in
  List.exists (fun glob -> glob_matches glob path) globs

let matches_any_prefix globs relative_path =
  let path = split_glob_segments relative_path in
  List.exists (fun glob -> glob_covers_prefix glob path) globs

let compile_globs globs =
  globs |> List.map split_glob_segments
  |> List.filter (fun segments -> segments <> [])

let manifest_root_file =
  {
    relative_path = manifest_relative_path;
    reload_policy = true;
    select_for_rerun = true;
  }

let ignore_root_file =
  {
    relative_path = ignore_file_name;
    reload_policy = true;
    select_for_rerun = false;
  }

let command_uses_lock_file command_name command_args =
  let has_lock_flag =
    List.exists
      (fun arg -> arg = "--locked" || arg = "--warn-locked")
      command_args
  in
  match command_name with
  | "doctor" -> true
  | "build" | "install" -> has_lock_flag
  | _ -> false

let root_files workspace_root command_name command_args =
  let base = [ manifest_root_file; ignore_root_file ] in
  let extra =
    if command_uses_lock_file command_name command_args then
      [
        {
          relative_path = lock_relative_path workspace_root;
          reload_policy = false;
          select_for_rerun = true;
        };
      ]
    else []
  in
  let all = base @ extra in
  let seen = Hashtbl.create (List.length all) in
  List.filter
    (fun root_file ->
      if Hashtbl.mem seen root_file.relative_path then false
      else (
        Hashtbl.add seen root_file.relative_path ();
        true))
    all

let compile_options (options : options) =
  {
    workspace_root = options.workspace_root;
    poll_ms = options.poll_ms;
    debounce_ms = options.debounce_ms;
    max_runs = options.max_runs;
    keep_going = options.keep_going;
    command_name = options.command_name;
    command_args = options.command_args;
    executable_path = Fs.resolve_executable Sys.executable_name;
    cli_include_globs = options.cli_include_globs;
    cli_ignore_globs = options.cli_ignore_globs;
    root_files =
      root_files options.workspace_root options.command_name options.command_args;
  }

let parse_ignore_file_line line =
  let trimmed = line |> String_util.strip_comment |> String.trim in
  if trimmed = "" then None else Some trimmed

let load_ignore_file_globs workspace_root =
  let path = Filename.concat workspace_root ignore_file_name in
  if not (Fs.exists path) then Ok []
  else if Fs.is_directory path then
    Error (Printf.sprintf "watch ignore file is a directory: %s" path)
  else Ok (Fs.read_lines path |> List.filter_map parse_ignore_file_line)

let protect_load path f =
  try f () with
  | Sys_error message -> Error message
  | Unix.Unix_error (error, _, _) ->
      Error
        (Printf.sprintf "%s: %s" path (Unix.error_message error))
  | exn -> Error (Printf.sprintf "%s: %s" path (Printexc.to_string exn))

let load_policy options =
  let manifest_path =
    Filename.concat options.workspace_root Manifest.default_filename
  in
  let* watch_config =
    protect_load manifest_path (fun () -> Manifest.load_watch_config manifest_path)
  in
  let* ignore_file_globs =
    protect_load
      (Filename.concat options.workspace_root ignore_file_name)
      (fun () -> load_ignore_file_globs options.workspace_root)
  in
  let include_globs_text =
    String_util.dedup_preserve
      (watch_config.Manifest.include_globs @ options.cli_include_globs)
  in
  let ignore_globs_text =
    String_util.dedup_preserve
      (default_ignore_globs @ watch_config.Manifest.ignore_globs @ ignore_file_globs
     @ options.cli_ignore_globs)
  in
  Ok
    {
      include_globs_text;
      ignore_globs_text;
      include_globs = compile_globs include_globs_text;
      ignore_globs = compile_globs ignore_globs_text;
    }

let stat_signature path =
  let stats = Unix.lstat path in
  match stats.Unix.st_kind with
  | Unix.S_REG ->
      Printf.sprintf "file\t%d\t%.6f" stats.Unix.st_size stats.Unix.st_mtime
  | Unix.S_DIR -> "dir"
  | Unix.S_LNK ->
      let target =
        try Unix.readlink path with
        | Unix.Unix_error _ -> "<unreadable>"
      in
      "symlink\t" ^ target
  | Unix.S_CHR -> "char"
  | Unix.S_BLK -> "block"
  | Unix.S_FIFO -> "fifo"
  | Unix.S_SOCK -> "socket"

let stat_signature_or_missing path =
  if Fs.exists path then stat_signature path else "missing"

let root_file options predicate relative_path =
  List.exists
    (fun root_file ->
      String.equal relative_path root_file.relative_path && predicate root_file)
    options.root_files

let path_is_manifest options relative_path =
  root_file options
    (fun root_file ->
      root_file.reload_policy && root_file.select_for_rerun
      && String.equal root_file.relative_path manifest_relative_path)
    relative_path

let path_is_ignore_file options relative_path =
  root_file options
    (fun root_file ->
      root_file.reload_policy && not root_file.select_for_rerun
      && String.equal root_file.relative_path ignore_file_name)
    relative_path

let path_is_root_file options relative_path =
  root_file options (fun _ -> true) relative_path

let path_is_selected_root_file options relative_path =
  root_file options (fun root_file -> root_file.select_for_rerun) relative_path

let path_is_ignored options policy relative_path =
  relative_path <> "" && not (path_is_root_file options relative_path)
  && matches_any_glob policy.ignore_globs relative_path

let path_is_relevant options policy relative_path =
  path_is_root_file options relative_path || policy.include_globs = []
  || matches_any_prefix policy.include_globs relative_path

let path_is_selected options policy relative_path =
  if path_is_selected_root_file options relative_path then true
  else if path_is_root_file options relative_path then false
  else policy.include_globs = [] || matches_any_glob policy.include_globs relative_path

let render_globs empty_label globs =
  match globs with
  | [] -> empty_label
  | globs -> String.concat ", " globs

let render_policy policy =
  Printf.sprintf "include=%s ignore=%s"
    (render_globs "<all>" policy.include_globs_text)
    (render_globs "<none>" policy.ignore_globs_text)

let render_root_files options =
  options.root_files
  |> List.map (fun root_file -> root_file.relative_path)
  |> render_globs "<none>"

let policy_changed previous next =
  previous.include_globs_text <> next.include_globs_text
  || previous.ignore_globs_text <> next.ignore_globs_text

let selected_snapshot options policy =
  let rec collect relative_path path acc =
    if path_is_ignore_file options relative_path then acc
    else if
      path_is_ignored options policy relative_path
      || not (path_is_relevant options policy relative_path)
    then acc
    else
      let signature = stat_signature path in
      let include_entry =
        relative_path = "" || path_is_selected options policy relative_path
        || (signature = "dir" && path_is_relevant options policy relative_path)
      in
      let label = if relative_path = "" then "." else relative_path in
      let acc =
        if include_entry then (label ^ "\t" ^ signature) :: acc else acc
      in
      if signature <> "dir" then acc
      else
        let entries =
          Sys.readdir path |> Array.to_list |> List.sort String.compare
        in
        List.fold_left
          (fun acc entry ->
            let child_relative =
              if relative_path = "" then entry
              else Filename.concat relative_path entry
            in
            collect child_relative (Filename.concat path entry) acc)
          acc entries
  in
  collect "" options.workspace_root [] |> List.rev

let control_snapshot options =
  options.root_files
  |> List.filter (fun root_file -> root_file.reload_policy)
  |> List.map (fun root_file ->
         root_file.relative_path
         ^ "\t"
         ^ stat_signature_or_missing
             (Filename.concat options.workspace_root root_file.relative_path))

let initial_state options =
  let* policy = load_policy options in
  Ok
    {
      policy;
      selected_snapshot = selected_snapshot options policy;
      control_snapshot = control_snapshot options;
    }

let render_status status = Process.status_to_text status

let execute_run options run_index =
  print_endline
    (Printf.sprintf "Watch-run %d: %s" run_index
       (command_line options.command_name options.command_args));
  let status =
    Process.run_status ~cwd:options.workspace_root options.executable_path
      (options.command_name :: options.command_args)
    |> fun outcome -> outcome.Process.unix_status
  in
  print_endline
    (Printf.sprintf "Watch-result %d: %s" run_index (render_status status));
  status

let rec wait_for_change options (state : state) =
  sleep_ms options.poll_ms;
  let next_control_snapshot = control_snapshot options in
  let selected_snapshot_before_reload =
    selected_snapshot options state.policy
  in
  if
    next_control_snapshot = state.control_snapshot
    && selected_snapshot_before_reload = state.selected_snapshot
  then wait_for_change options state
  else (
    if options.debounce_ms > 0 then sleep_ms options.debounce_ms;
    let next_control_snapshot = control_snapshot options in
    let selected_snapshot_before_reload =
      selected_snapshot options state.policy
    in
    let control_changed = next_control_snapshot <> state.control_snapshot in
    if not control_changed then
      if selected_snapshot_before_reload = state.selected_snapshot then
        wait_for_change options state
      else { state with selected_snapshot = selected_snapshot_before_reload }
    else
      match load_policy options with
      | Ok policy ->
          if policy_changed state.policy policy then
            print_endline
              (Printf.sprintf "Watch-config: reloaded %s" (render_policy policy));
          let next_state =
            {
              policy;
              selected_snapshot = selected_snapshot options policy;
              control_snapshot = next_control_snapshot;
            }
          in
          if selected_snapshot_before_reload = state.selected_snapshot then
            wait_for_change options next_state
          else next_state
      | Error message ->
          print_endline
            (Printf.sprintf
               "Watch-config: keeping previous policy after reload error: %s"
               message);
          let next_state =
            {
              state with
              selected_snapshot = selected_snapshot_before_reload;
              control_snapshot = next_control_snapshot;
            }
          in
          if selected_snapshot_before_reload = state.selected_snapshot then
            wait_for_change options next_state
          else next_state)

let run options =
  let options = compile_options options in
  let* state = initial_state options in
  print_endline
    (Printf.sprintf
       "Watching %s (poll=%dms debounce=%dms) for `oasis %s`"
       options.workspace_root options.poll_ms options.debounce_ms
       (command_line options.command_name options.command_args));
  print_endline
    (Printf.sprintf "Watch-config: %s" (render_policy state.policy));
  print_endline
    (Printf.sprintf "Watch-root-files: %s" (render_root_files options));
  let rec loop run_index state =
    let status = execute_run options run_index in
    let state =
      { state with selected_snapshot = selected_snapshot options state.policy }
    in
    if not (Process.is_success status) && not options.keep_going then Ok status
    else
      match options.max_runs with
      | Some limit when run_index >= limit -> Ok status
      | _ ->
          print_endline "Watch-waiting: watching for workspace changes";
          let next_state = wait_for_change options state in
          print_endline "Watch-change: rerunning";
          loop (run_index + 1) next_state
  in
  loop 1 state
