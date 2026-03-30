let exists path = Sys.file_exists path
let is_directory path = exists path && Sys.is_directory path

let is_executable_file path =
  exists path
  &&
  match Unix.stat path with
  | { Unix.st_kind = Unix.S_REG; st_perm; _ } -> st_perm land 0o111 <> 0
  | _ -> false
  | exception Unix.Unix_error _ -> false

type materialize_strategy = Clone_copy | Reflink_copy | Plain_copy

let materialize_strategy : materialize_strategy option ref = ref None
let realpath path = try Unix.realpath path with Unix.Unix_error _ -> path

let resolve_executable path =
  let absolute_path path =
    if Filename.is_relative path then Filename.concat (Sys.getcwd ()) path else path
  in
  if String.contains path '/' then realpath (absolute_path path)
  else
    match Sys.getenv_opt "PATH" with
    | None -> path
    | Some search_path -> (
        match
          search_path |> String.split_on_char ':'
          |> List.filter_map (fun dir ->
              let candidate = Filename.concat dir path in
              if is_executable_file candidate then Some (realpath candidate) else None)
        with
        | resolved :: _ -> resolved
        | [] -> path)

let read_lines path =
  let channel = open_in path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr channel)
    (fun () ->
      let rec loop acc =
        match input_line channel with
        | line -> loop (line :: acc)
        | exception End_of_file -> List.rev acc
      in
      loop [])

let read_file path =
  let channel = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr channel)
    (fun () ->
      let length = in_channel_length channel in
      really_input_string channel length)

let rec ensure_dir path =
  if path = "" || path = "." || path = "/" then ()
  else if exists path then (
    if not (Sys.is_directory path) then
      invalid_arg (Printf.sprintf "%s exists and is not a directory" path))
  else
    let parent = Filename.dirname path in
    if parent <> path then ensure_dir parent;
    Unix.mkdir path 0o755

let write_file path contents =
  ensure_dir (Filename.dirname path);
  let channel = open_out_bin path in
  Fun.protect
    ~finally:(fun () -> close_out_noerr channel)
    (fun () -> output_string channel contents)

let copy_file ~src ~dst =
  ensure_dir (Filename.dirname dst);
  let permissions = (Unix.stat src).Unix.st_perm in
  let input_channel = open_in_bin src in
  let output_channel = open_out_bin dst in
  Fun.protect
    ~finally:(fun () ->
      close_in_noerr input_channel;
      close_out_noerr output_channel)
    (fun () ->
      let buffer = Bytes.create 65536 in
      let rec loop () =
        match input input_channel buffer 0 (Bytes.length buffer) with
        | 0 -> ()
        | bytes_read ->
            output output_channel buffer 0 bytes_read;
            loop ()
      in
      loop ();
      Unix.chmod dst permissions)

let close_noerr fd = try Unix.close fd with Unix.Unix_error _ -> ()

let waitpid_nointr pid =
  let rec loop () =
    try snd (Unix.waitpid [] pid) with Unix.Unix_error (Unix.EINTR, _, _) -> loop ()
  in
  loop ()

let run_quiet_status prog args =
  let null_fd = Unix.openfile "/dev/null" [ Unix.O_RDWR ] 0 in
  Fun.protect
    ~finally:(fun () -> close_noerr null_fd)
    (fun () ->
      try
        let pid =
          Unix.create_process prog (Array.of_list (prog :: args)) null_fd null_fd null_fd
        in
        waitpid_nointr pid
      with Unix.Unix_error _ -> Unix.WEXITED 127)

let try_clone_copy ~src ~dst =
  match run_quiet_status "cp" [ "-c"; "-p"; src; dst ] with
  | Unix.WEXITED 0 -> true
  | Unix.WEXITED _ | Unix.WSIGNALED _ | Unix.WSTOPPED _ -> false

let try_reflink_copy ~src ~dst =
  match
    run_quiet_status "cp" [ "--reflink=auto"; "--preserve=mode,timestamps"; src; dst ]
  with
  | Unix.WEXITED 0 -> true
  | Unix.WEXITED _ | Unix.WSIGNALED _ | Unix.WSTOPPED _ -> false

let rec materialize_file ~src ~dst =
  ensure_dir (Filename.dirname dst);
  let rec with_strategy = function
    | Clone_copy ->
        if try_clone_copy ~src ~dst then materialize_strategy := Some Clone_copy
        else with_strategy Reflink_copy
    | Reflink_copy ->
        if try_reflink_copy ~src ~dst then materialize_strategy := Some Reflink_copy
        else with_strategy Plain_copy
    | Plain_copy ->
        materialize_strategy := Some Plain_copy;
        copy_file ~src ~dst
  in
  match !materialize_strategy with
  | Some strategy -> with_strategy strategy
  | None -> with_strategy Clone_copy

let rec remove_tree path =
  if exists path then
    if Sys.is_directory path then (
      Sys.readdir path
      |> Array.iter (fun entry -> remove_tree (Filename.concat path entry));
      Unix.rmdir path)
    else Unix.unlink path

let rec copy_tree ~src ~dst =
  ensure_dir dst;
  Sys.readdir src
  |> Array.iter (fun entry ->
      let src_path = Filename.concat src entry in
      let dst_path = Filename.concat dst entry in
      if Sys.is_directory src_path then copy_tree ~src:src_path ~dst:dst_path
      else copy_file ~src:src_path ~dst:dst_path)

let rec materialize_tree ~src ~dst =
  ensure_dir dst;
  Sys.readdir src
  |> Array.iter (fun entry ->
      let src_path = Filename.concat src entry in
      let dst_path = Filename.concat dst entry in
      if Sys.is_directory src_path then materialize_tree ~src:src_path ~dst:dst_path
      else materialize_file ~src:src_path ~dst:dst_path)

let materialize_path ~src ~dst =
  if Sys.is_directory src then materialize_tree ~src ~dst else materialize_file ~src ~dst
