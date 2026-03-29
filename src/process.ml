type env_binding = string * string

type outcome = {
  command : string;
  status : int;
  unix_status : Unix.process_status;
  output : string;
}

type exit_status = {
  command : string;
  status : int;
  unix_status : Unix.process_status;
}

let render ?cwd ?(env = []) prog args =
  let env_prefix =
    match env with
    | [] -> ""
    | env ->
        String.concat " "
          (List.map
             (fun (name, value) ->
               String_util.shell_quote (name ^ "=" ^ value))
             env)
        ^ " "
  in
  let base =
    env_prefix
    ^ String.concat " " (List.map String_util.shell_quote (prog :: args))
  in
  match cwd with
  | None -> base
  | Some dir -> "cd " ^ String_util.shell_quote dir ^ " && " ^ base

let status_to_code = function
  | Unix.WEXITED code -> code
  | Unix.WSIGNALED signal
  | Unix.WSTOPPED signal -> 128 + signal

let status_to_text = function
  | Unix.WEXITED code -> Printf.sprintf "exit %d" code
  | Unix.WSIGNALED signal -> Printf.sprintf "signal %d" signal
  | Unix.WSTOPPED signal -> Printf.sprintf "stopped by signal %d" signal

let is_success = function
  | Unix.WEXITED 0 -> true
  | Unix.WEXITED _ | Unix.WSIGNALED _ | Unix.WSTOPPED _ -> false

let close_noerr fd =
  try Unix.close fd with
  | Unix.Unix_error _ -> ()

let write_stderr message =
  let bytes = Bytes.of_string message in
  let rec loop offset =
    if offset < Bytes.length bytes then
      try
        let written =
          Unix.write Unix.stderr bytes offset (Bytes.length bytes - offset)
        in
        loop (offset + written)
      with
      | Unix.Unix_error (Unix.EINTR, _, _) -> loop offset
  in
  loop 0

let write_all fd text =
  let bytes = Bytes.of_string text in
  let rec loop offset =
    if offset < Bytes.length bytes then
      try
        let written = Unix.write fd bytes offset (Bytes.length bytes - offset) in
        loop (offset + written)
      with
      | Unix.Unix_error (Unix.EINTR, _, _) -> loop offset
      | Unix.Unix_error (Unix.EPIPE, _, _) -> ()
  in
  loop 0

let rec waitpid pid =
  try
    let _, status = Unix.waitpid [] pid in
    status
  with
  | Unix.Unix_error (Unix.EINTR, _, _) -> waitpid pid

let read_all fd =
  let buffer = Bytes.create 65536 in
  let contents = Buffer.create 4096 in
  Fun.protect
    ~finally:(fun () -> close_noerr fd)
    (fun () ->
      let rec loop () =
        try
          match Unix.read fd buffer 0 (Bytes.length buffer) with
          | 0 -> Buffer.contents contents
          | bytes_read ->
              Buffer.add_subbytes contents buffer 0 bytes_read;
              loop ()
        with
        | Unix.Unix_error (Unix.EINTR, _, _) -> loop ()
      in
      loop ())

let setup_child_fd target = function
  | None -> ()
  | Some fd when fd = target -> ()
  | Some fd -> Unix.dup2 fd target

let close_child_fds fds =
  fds
  |> List.sort_uniq compare
  |> List.iter (fun fd ->
         if fd <> Unix.stdin && fd <> Unix.stdout && fd <> Unix.stderr then
           close_noerr fd)

let environment_table () =
  let table = Hashtbl.create 64 in
  Unix.environment ()
  |> Array.iter (fun binding ->
         match String_util.split_once ~on:'=' binding with
         | Some (name, value) -> Hashtbl.replace table name value
         | None -> ());
  table

let merged_environment env =
  let current = Unix.environment () in
  let table = environment_table () in
  let names =
    Array.to_list current
    |> List.filter_map (fun binding ->
           match String_util.split_once ~on:'=' binding with
           | Some (name, _) -> Some name
           | None -> None)
  in
  let ordered_names =
    String_util.dedup_preserve (names @ List.map fst env)
  in
  List.iter (fun (name, value) -> Hashtbl.replace table name value) env;
  ordered_names
  |> List.filter_map (fun name ->
         match Hashtbl.find_opt table name with
         | Some value -> Some (name ^ "=" ^ value)
         | None -> None)
  |> Array.of_list

let merged_environment_bindings env =
  merged_environment env
  |> Array.to_list
  |> List.filter_map (fun binding ->
         match String_util.split_once ~on:'=' binding with
         | Some (name, value) -> Some (name, value)
         | None -> None)

let spawn ?cwd ?(env = []) ?stdin_fd ?stdout_fd ?stderr_fd ?(extra_closes = [])
    prog args =
  match Unix.fork () with
  | 0 -> (
      try
        (match cwd with
        | None -> ()
        | Some dir -> Unix.chdir dir);
        setup_child_fd Unix.stdin stdin_fd;
        setup_child_fd Unix.stdout stdout_fd;
        setup_child_fd Unix.stderr stderr_fd;
        close_child_fds
          (extra_closes
          @ List.filter_map Fun.id [ stdin_fd; stdout_fd; stderr_fd ]);
        if env = [] then Unix.execvp prog (Array.of_list (prog :: args))
        else Unix.execvpe prog (Array.of_list (prog :: args)) (merged_environment env)
      with
      | Unix.Unix_error (error, _, _) ->
          write_stderr
            (Printf.sprintf "oasis: failed to execute %s: %s\n" prog
               (Unix.error_message error));
          Unix._exit 127
      | exn ->
          write_stderr
            (Printf.sprintf "oasis: failed to execute %s: %s\n" prog
               (Printexc.to_string exn));
          Unix._exit 127)
  | pid -> pid

let render_with_redirects ?cwd ?(env = []) ?stdout_path prog args =
  render ?cwd ~env prog args
  ^
  match stdout_path with
  | Some path -> " > " ^ String_util.shell_quote path
  | None -> ""

let run_capture ?cwd ?(verbose = false) ?(env = []) ?stdin ?stdout_path prog args =
  let command = render_with_redirects ?cwd ~env ?stdout_path prog args in
  if verbose then prerr_endline command;
  let read_fd, write_fd = Unix.pipe () in
  let stdin_read_fd, stdin_write_fd =
    match stdin with
    | Some _ ->
        let read_fd, write_fd = Unix.pipe () in
        (Some read_fd, Some write_fd)
    | None -> (None, None)
  in
  let stdout_fd, extra_closes, close_parent_stdout =
    match stdout_path with
    | None -> (write_fd, [], fun () -> ())
    | Some path ->
        let output_fd =
          Unix.openfile path
            [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC ]
            0o644
        in
        (output_fd, [ output_fd ], fun () -> close_noerr output_fd)
  in
  let pid =
    spawn ?cwd ~env ?stdin_fd:stdin_read_fd ~stdout_fd
      ~stderr_fd:write_fd
      ~extra_closes:
        (read_fd :: extra_closes @ List.filter_map Fun.id [ stdin_write_fd ])
      prog args
  in
  close_noerr write_fd;
  close_parent_stdout ();
  (match stdin_read_fd with
  | Some fd -> close_noerr fd
  | None -> ());
  (match stdin_write_fd, stdin with
  | Some write_fd, Some text ->
      Fun.protect ~finally:(fun () -> close_noerr write_fd) (fun () ->
          write_all write_fd text)
  | Some write_fd, None -> close_noerr write_fd
  | None, _ -> ());
  let output = read_all read_fd in
  let unix_status = waitpid pid in
  { command; status = status_to_code unix_status; unix_status; output }

let run_status ?cwd ?(verbose = false) ?(env = []) ?stdin prog args =
  let command = render ?cwd ~env prog args in
  if verbose then prerr_endline command;
  let stdin_read_fd, stdin_write_fd =
    match stdin with
    | Some _ ->
        let read_fd, write_fd = Unix.pipe () in
        (Some read_fd, Some write_fd)
    | None -> (None, None)
  in
  let pid =
    spawn ?cwd ~env ?stdin_fd:stdin_read_fd
      ~extra_closes:(List.filter_map Fun.id [ stdin_write_fd ]) prog args
  in
  (match stdin_read_fd with
  | Some fd -> close_noerr fd
  | None -> ());
  (match stdin_write_fd, stdin with
  | Some write_fd, Some text ->
      Fun.protect ~finally:(fun () -> close_noerr write_fd) (fun () ->
          write_all write_fd text)
  | Some write_fd, None -> close_noerr write_fd
  | None, _ -> ());
  let unix_status = waitpid pid in
  { command; status = status_to_code unix_status; unix_status }

let ensure_success ?cwd ?verbose ?(env = []) ?stdin ?stdout_path prog args =
  let outcome = run_capture ?cwd ?verbose ~env ?stdin ?stdout_path prog args in
  if is_success outcome.unix_status then Ok outcome
  else
    Error
      (Printf.sprintf "command failed (%s): %s\n%s"
         (status_to_text outcome.unix_status)
         outcome.command outcome.output)

let exit_with_status status =
  match status with
  | Unix.WEXITED code -> exit code
  | Unix.WSIGNALED signal ->
      flush_all ();
      Sys.set_signal signal Sys.Signal_default;
      ignore (Unix.sigprocmask Unix.SIG_UNBLOCK [ signal ]);
      Unix.kill (Unix.getpid ()) signal;
      exit (status_to_code status)
  | Unix.WSTOPPED signal -> exit (status_to_code status)
