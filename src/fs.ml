let exists path = Sys.file_exists path

let is_directory path = exists path && Sys.is_directory path

let realpath path =
  try Unix.realpath path with
  | Unix.Unix_error _ -> path

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
