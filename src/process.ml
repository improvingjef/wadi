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

let render ?cwd prog args =
  let base =
    String.concat " " (List.map String_util.shell_quote (prog :: args))
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

let spawn ?cwd ?stdout_fd ?stderr_fd ?(extra_closes = []) prog args =
  match Unix.fork () with
  | 0 -> (
      try
        (match cwd with
        | None -> ()
        | Some dir -> Unix.chdir dir);
        setup_child_fd Unix.stdout stdout_fd;
        setup_child_fd Unix.stderr stderr_fd;
        close_child_fds (extra_closes @ List.filter_map Fun.id [ stdout_fd; stderr_fd ]);
        Unix.execvp prog (Array.of_list (prog :: args))
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

let run_capture ?cwd ?(verbose = false) prog args =
  let command = render ?cwd prog args in
  if verbose then prerr_endline command;
  let read_fd, write_fd = Unix.pipe () in
  let pid =
    spawn ?cwd ~stdout_fd:write_fd ~stderr_fd:write_fd ~extra_closes:[ read_fd ]
      prog args
  in
  close_noerr write_fd;
  let output = read_all read_fd in
  let unix_status = waitpid pid in
  { command; status = status_to_code unix_status; unix_status; output }

let run_status ?cwd ?(verbose = false) prog args =
  let command = render ?cwd prog args in
  if verbose then prerr_endline command;
  let unix_status = waitpid (spawn ?cwd prog args) in
  { command; status = status_to_code unix_status; unix_status }

let ensure_success ?cwd ?verbose prog args =
  let outcome = run_capture ?cwd ?verbose prog args in
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
