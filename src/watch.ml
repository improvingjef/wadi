type options = {
  workspace_root : string;
  poll_ms : int;
  debounce_ms : int;
  max_runs : int option;
  keep_going : bool;
  command_name : string;
  command_args : string list;
}

let ignored_entries = [ ".git"; "_oasis"; "_bootstrap" ]

let absolute_executable_path () =
  let executable = Sys.executable_name in
  let path =
    if Filename.is_relative executable then
      Filename.concat (Sys.getcwd ()) executable
    else executable
  in
  Fs.realpath path

let command_line command_name command_args =
  String.concat " " (command_name :: command_args)

let sleep_ms milliseconds =
  ignore (Unix.select [] [] [] (float_of_int milliseconds /. 1000.0))

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

let snapshot workspace_root =
  let rec collect relative_path path acc =
    let signature = stat_signature path in
    let label = if relative_path = "" then "." else relative_path in
    let acc = (label ^ "\t" ^ signature) :: acc in
    if signature <> "dir" then acc
    else
      let entries =
        Sys.readdir path |> Array.to_list |> List.sort String.compare
      in
      List.fold_left
        (fun acc entry ->
          if List.mem entry ignored_entries then acc
          else
            let child_relative =
              if relative_path = "" then entry
              else Filename.concat relative_path entry
            in
            collect child_relative (Filename.concat path entry) acc)
        acc entries
  in
  collect "" workspace_root [] |> List.rev

let render_status status = Process.status_to_text status

let execute_run options run_index =
  let executable = absolute_executable_path () in
  print_endline
    (Printf.sprintf "Watch-run %d: %s" run_index
       (command_line options.command_name options.command_args));
  let status =
    Process.run_status ~cwd:options.workspace_root executable
      (options.command_name :: options.command_args)
    |> fun outcome -> outcome.Process.unix_status
  in
  print_endline
    (Printf.sprintf "Watch-result %d: %s" run_index (render_status status));
  status

let rec wait_for_change options previous_snapshot =
  sleep_ms options.poll_ms;
  let next_snapshot = snapshot options.workspace_root in
  if next_snapshot = previous_snapshot then
    wait_for_change options previous_snapshot
  else (
    if options.debounce_ms > 0 then sleep_ms options.debounce_ms;
    snapshot options.workspace_root)

let run options =
  print_endline
    (Printf.sprintf
       "Watching %s (poll=%dms debounce=%dms) for `oasis %s`"
       options.workspace_root options.poll_ms options.debounce_ms
       (command_line options.command_name options.command_args));
  let rec loop run_index current_snapshot =
    let status = execute_run options run_index in
    let current_snapshot = snapshot options.workspace_root in
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
  let initial_snapshot = snapshot options.workspace_root in
  loop 1 initial_snapshot
