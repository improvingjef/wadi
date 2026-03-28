type outcome = {
  command : string;
  status : int;
  output : string;
}

type exit_status = {
  command : string;
  status : int;
}

let render ?cwd prog args =
  let base =
    String.concat " " (List.map String_util.shell_quote (prog :: args))
  in
  match cwd with
  | None -> base
  | Some dir -> "cd " ^ String_util.shell_quote dir ^ " && " ^ base

let run_capture ?cwd ?(verbose = false) prog args =
  let command = render ?cwd prog args in
  if verbose then prerr_endline command;
  let output_path = Filename.temp_file "oasis-process" ".log" in
  let shell_command =
    command ^ " >" ^ String_util.shell_quote output_path ^ " 2>&1"
  in
  let status = Sys.command shell_command in
  let output = Fs.read_file output_path in
  Unix.unlink output_path;
  { command; status; output }

let run_status ?cwd ?(verbose = false) prog args =
  let command = render ?cwd prog args in
  if verbose then prerr_endline command;
  let status = Sys.command command in
  { command; status }

let ensure_success ?cwd ?verbose prog args =
  let outcome = run_capture ?cwd ?verbose prog args in
  if outcome.status = 0 then Ok outcome
  else
    Error
      (Printf.sprintf "command failed (%d): %s\n%s" outcome.status
         outcome.command outcome.output)
