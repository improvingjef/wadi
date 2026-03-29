type report = {
  source_dir : string;
  destination_dir : string;
  member_path : string;
  manifest_path : string;
  replaced : bool;
  registered : bool;
}

let ( let* ) = Result.bind

let excluded_entries =
  [ ".git"; ".DS_Store"; "_build"; "_bootstrap"; "_oasis"; "dist" ]

let validate_name label value =
  let value = String.trim value in
  if value = "" then Error (Printf.sprintf "%s cannot be empty" label)
  else if String.contains value '/' then
    Error (Printf.sprintf "%s must not contain '/': %s" label value)
  else if value = "." || value = ".." then
    Error (Printf.sprintf "%s must not be %s" label value)
  else Ok value

let normalize_path_for_prefix path =
  let path = Fs.realpath path in
  if path = "/" then path
  else if String_util.ends_with ~suffix:"/" path then
    String.sub path 0 (String.length path - 1)
  else path

let path_is_within ~parent child =
  let parent = normalize_path_for_prefix parent in
  let child = normalize_path_for_prefix child in
  child = parent
  || String_util.starts_with ~prefix:(parent ^ "/") child

let copy_tree_filtered ~src ~dst =
  let rec copy src dst =
    Fs.ensure_dir dst;
    Sys.readdir src
    |> Array.iter (fun entry ->
           if not (List.mem entry excluded_entries) then
             let src_path = Filename.concat src entry in
             let dst_path = Filename.concat dst entry in
             if Sys.is_directory src_path then copy src_path dst_path
             else Fs.copy_file ~src:src_path ~dst:dst_path)
  in
  copy src dst

let validate_member_manifest manifest_path =
  let* loaded = Manifest.load_local manifest_path in
  if loaded.workspace.name <> None then
    Error
      (Printf.sprintf
         "%s defines a top-level workspace name; vendored members must stay \
          package-local"
         manifest_path)
  else if loaded.workspace.defaults <> Manifest.default_defaults then
    Error
      (Printf.sprintf
         "%s defines [defaults]; vendored members must keep workspace-wide \
          defaults in the root manifest"
         manifest_path)
  else if loaded.workspace.profiles <> [] then
    Error
      (Printf.sprintf
         "%s defines [profile.*]; vendored members must keep profiles in the \
          root manifest"
         manifest_path)
  else Ok ()

let members_line members =
  "members = ["
  ^ String.concat ", " (List.map (Printf.sprintf "%S") members)
  ^ "]"

let list_insert index value items =
  let rec loop acc i = function
    | [] -> List.rev_append acc [ value ]
    | rest when i = 0 -> List.rev_append acc (value :: rest)
    | item :: rest -> loop (item :: acc) (i - 1) rest
  in
  loop [] index items

let list_replace index value items =
  let rec loop acc i = function
    | [] -> List.rev acc
    | _item :: rest when i = 0 -> List.rev_append acc (value :: rest)
    | item :: rest -> loop (item :: acc) (i - 1) rest
  in
  loop [] index items

let rewrite_members manifest_path members =
  let lines = Fs.read_lines manifest_path in
  let rendered = members_line members in
  let rec scan index first_section members_index = function
    | [] -> (first_section, members_index)
    | line :: rest ->
        let trimmed = String.trim (String_util.strip_comment line) in
        if String_util.starts_with ~prefix:"[" trimmed then
          scan (index + 1)
            (match first_section with
            | Some _ -> first_section
            | None -> Some index)
            members_index rest
        else
          let members_index =
            match (members_index, String_util.split_once ~on:'=' trimmed) with
            | Some _ as members_index, _ -> members_index
            | None, Some (raw_key, _) when String.trim raw_key = "members" ->
                Some index
            | None, _ -> None
          in
          scan (index + 1) first_section members_index rest
  in
  let first_section, members_index = scan 0 None None lines in
  let updated_lines =
    match members_index with
    | Some index -> list_replace index rendered lines
    | None -> (
        match first_section with
        | Some index -> list_insert index rendered lines
        | None -> lines @ [ rendered ])
  in
  let temp_path = manifest_path ^ ".vendor.tmp" in
  Fs.write_file temp_path (String.concat "\n" updated_lines ^ "\n");
  match Manifest.load temp_path with
  | Ok _ ->
      Sys.rename temp_path manifest_path;
      Ok ()
  | Error message ->
      (try Unix.unlink temp_path with
      | Unix.Unix_error _ -> ());
      Error message

let vendor ~workspace_root ~source_dir ?name ~force () =
  if not (Fs.is_directory workspace_root) then
    Error (Printf.sprintf "workspace directory does not exist: %s" workspace_root)
  else
    let manifest_path = Filename.concat workspace_root Manifest.default_filename in
    if not (Fs.exists manifest_path) then
      Error (Printf.sprintf "manifest not found: %s" manifest_path)
    else if not (Fs.is_directory source_dir) then
      Error (Printf.sprintf "vendor source directory does not exist: %s" source_dir)
    else
      let source_manifest_path =
        Filename.concat source_dir Manifest.default_filename
      in
      if not (Fs.exists source_manifest_path) then
        Error (Printf.sprintf "vendor source manifest not found: %s" source_manifest_path)
      else
        let* root_loaded = Manifest.load_local manifest_path in
        let* () = validate_member_manifest source_manifest_path in
        let vendor_name =
          match name with
          | Some name -> name
          | None -> Filename.basename source_dir
        in
        let* vendor_name = validate_name "vendor name" vendor_name in
        let member_path = Filename.concat "vendor" vendor_name in
        let workspace_root = Fs.realpath workspace_root in
        let source_dir = Fs.realpath source_dir in
        let destination_dir = Filename.concat workspace_root member_path in
        if path_is_within ~parent:source_dir destination_dir then
          Error
            (Printf.sprintf
               "refusing to vendor %s into %s because the destination lives \
                inside the source tree"
               source_dir destination_dir)
        else if path_is_within ~parent:destination_dir source_dir then
          Error
            (Printf.sprintf
               "refusing to vendor %s into %s because the source already lives \
                under the destination path"
               source_dir destination_dir)
        else
          let already_registered = List.mem member_path root_loaded.members in
          if already_registered && not force then
            Error
              (Printf.sprintf
                 "member %s is already registered; rerun with --force to replace \
                  the vendored checkout"
                 member_path)
          else if Fs.exists destination_dir && not force then
            Error
              (Printf.sprintf
                 "vendor destination already exists: %s; rerun with --force to \
                  replace it"
                 destination_dir)
          else (
            let replaced = Fs.exists destination_dir in
            if replaced then Fs.remove_tree destination_dir;
            copy_tree_filtered ~src:source_dir ~dst:destination_dir;
            let members =
              if already_registered then root_loaded.members
              else root_loaded.members @ [ member_path ]
            in
            let* () = rewrite_members manifest_path members in
            Ok
              {
                source_dir;
                destination_dir;
                member_path;
                manifest_path;
                replaced;
                registered = not already_registered;
              })

let render_report report =
  let action = if report.replaced then "Updated" else "Vendored" in
  let member_line =
    if report.registered then
      Printf.sprintf "Registered workspace member %s in %s" report.member_path
        report.manifest_path
    else
      Printf.sprintf "Kept existing workspace member %s in %s" report.member_path
        report.manifest_path
  in
  String.concat "\n"
    [
      Printf.sprintf "%s %s -> %s" action report.source_dir
        report.destination_dir;
      member_line;
    ]
  ^ "\n"
