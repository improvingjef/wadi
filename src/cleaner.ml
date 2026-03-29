let ( let* ) = Result.bind

let report_detail ~verbose message =
  if verbose then prerr_endline message

let oasis_root = Layout.artifact_root

let describe_target target =
  Printf.sprintf "%s %s" (Manifest.target_kind_name target)
    (Manifest.target_display_name target)

let resolve_targets workspace requested_targets =
  let index = Hashtbl.create (List.length workspace.Manifest.targets) in
  List.iter
    (fun target -> Hashtbl.replace index (Manifest.target_name target) target)
    workspace.Manifest.targets;
  let requested_targets = String_util.dedup_preserve requested_targets in
  let rec loop acc = function
    | [] -> Ok (List.rev acc)
    | name :: rest -> (
        match Hashtbl.find_opt index name with
        | Some target -> loop (target :: acc) rest
        | None -> Error (Printf.sprintf "unknown target '%s'" name))
  in
  loop [] requested_targets

let rec prune_empty_directories ~stop_at path =
  if path = stop_at || path = "." || path = "/" then ()
  else if Fs.exists path && Sys.is_directory path && Array.length (Sys.readdir path) = 0 then (
    Unix.rmdir path;
    prune_empty_directories ~stop_at (Filename.dirname path))

let clean_target ~workspace_root ~profile ~verbose target =
  let artifact_dir = Layout.target_out_dir ?profile workspace_root target in
  if Fs.exists artifact_dir then (
    report_detail ~verbose ("Cleaning " ^ artifact_dir);
    Fs.remove_tree artifact_dir;
    prune_empty_directories ~stop_at:workspace_root
      (Filename.dirname artifact_dir);
    print_endline
      (Printf.sprintf "Removed %s -> %s" (describe_target target) artifact_dir);
    true)
  else (
    print_endline (Printf.sprintf "No artifacts for %s" (describe_target target));
    false)

let clean_workspace ~workspace_root ~profile ~verbose =
  let workspace_root = Fs.realpath workspace_root in
  let path =
    match profile with
    | Some profile -> Layout.build_root_for_profile workspace_root profile
    | None -> oasis_root workspace_root
  in
  if Fs.exists path then (
    report_detail ~verbose ("Cleaning " ^ path);
    Fs.remove_tree path;
    print_endline
      (match profile with
      | Some profile ->
          Printf.sprintf "Removed profile %s artifacts -> %s" profile path
      | None -> Printf.sprintf "Removed workspace artifacts -> %s" path))
  else
    print_endline
      (match profile with
      | Some profile -> Printf.sprintf "Nothing to clean in profile %s (%s)" profile path
      | None -> Printf.sprintf "Nothing to clean in %s" path);
  Ok ()

let clean_targets ~workspace_root ~profile ~verbose ~requested_targets workspace =
  let workspace_root = Fs.realpath workspace_root in
  let* targets = resolve_targets workspace requested_targets in
  let removed_count =
    List.fold_left
      (fun count target ->
        if clean_target ~workspace_root ~profile ~verbose target then count + 1
        else count)
      0 targets
  in
  if removed_count = 0 then
    print_endline "Nothing to clean for the requested targets";
  Ok ()
