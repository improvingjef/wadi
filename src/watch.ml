type options = {
  workspace_root : string;
  poll_ms : int;
  debounce_ms : int;
  max_runs : int option;
  keep_going : bool;
  command_name : string;
  command_args : string list;
  include_globs : string list;
  ignore_globs : string list;
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
  include_globs : string list list;
  ignore_globs : string list list;
}

let default_ignore_globs = [ ".git/**"; "_oasis/**"; "_bootstrap/**" ]

let ignore_file_name = ".oasiswatchignore"

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
    include_globs =
      options.include_globs |> String_util.dedup_preserve |> compile_globs;
    ignore_globs =
      (default_ignore_globs @ options.ignore_globs)
      |> String_util.dedup_preserve |> compile_globs;
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

let path_is_ignored options relative_path =
  relative_path <> "" && matches_any_glob options.ignore_globs relative_path

let path_is_relevant options relative_path =
  options.include_globs = [] || matches_any_prefix options.include_globs relative_path

let path_is_selected options relative_path =
  options.include_globs = [] || matches_any_glob options.include_globs relative_path

let snapshot options =
  let rec collect relative_path path acc =
    if path_is_ignored options relative_path || not (path_is_relevant options relative_path)
    then acc
    else
      let signature = stat_signature path in
      let include_entry =
        relative_path = "" || path_is_selected options relative_path
        || (signature = "dir" && path_is_relevant options relative_path)
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

let rec wait_for_change options previous_snapshot =
  sleep_ms options.poll_ms;
  let next_snapshot = snapshot options in
  if next_snapshot = previous_snapshot then
    wait_for_change options previous_snapshot
  else (
    if options.debounce_ms > 0 then sleep_ms options.debounce_ms;
    snapshot options)

let run options =
  let options = compile_options options in
  print_endline
    (Printf.sprintf
       "Watching %s (poll=%dms debounce=%dms) for `oasis %s`"
       options.workspace_root options.poll_ms options.debounce_ms
       (command_line options.command_name options.command_args));
  let rec loop run_index current_snapshot =
    let status = execute_run options run_index in
    let current_snapshot = snapshot options in
    if not (Process.is_success status) && not options.keep_going then status
    else
      match options.max_runs with
      | Some limit when run_index >= limit -> status
      | _ ->
          print_endline "Watch-waiting: watching for workspace changes";
          let next_snapshot = wait_for_change options current_snapshot in
          print_endline "Watch-change: rerunning";
          loop (run_index + 1) next_snapshot
  in
  let initial_snapshot = snapshot options in
  loop 1 initial_snapshot
