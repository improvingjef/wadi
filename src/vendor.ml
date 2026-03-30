type report = {
  source_label : string;
  destination_dir : string;
  member_path : string;
  manifest_path : string;
  replaced : bool;
  registered : bool;
}

type source =
  | Local_dir of string
  | Git_repo of {
      url : string;
      ref_name : string option;
      checksum : string;
    }
  | Url_archive of {
      url : string;
      checksum : string;
    }

type archive_checksum = {
  algorithm : string;
  value : string;
}

type prepared_source = {
  source_dir : string;
  source_label : string;
  suggested_name : string;
}

let ( let* ) = Result.bind

let excluded_entries =
  [ ".git"; ".DS_Store"; "__MACOSX"; "_build"; "_bootstrap"; "_wadi"; "dist" ]

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

let with_temp_dir prefix f =
  let path = Filename.temp_file prefix ".tmp" in
  Unix.unlink path;
  Unix.mkdir path 0o755;
  Fun.protect ~finally:(fun () -> Fs.remove_tree path) (fun () -> f path)

let is_hex_string value =
  let rec loop index =
    if index >= String.length value then true
    else
      match value.[index] with
      | '0' .. '9' | 'a' .. 'f' | 'A' .. 'F' -> loop (index + 1)
      | _ -> false
  in
  value <> "" && loop 0

let normalize_hex value =
  String.lowercase_ascii (String.trim value)

let parse_archive_checksum value =
  let trimmed = String.trim value in
  let algorithm, raw_value =
    match String_util.split_once ~on:':' trimmed with
    | Some (raw_algorithm, raw_value) ->
        (String.lowercase_ascii (String.trim raw_algorithm), raw_value)
    | None -> ("sha256", trimmed)
  in
  let value = normalize_hex raw_value in
  if value = "" then Error "checksum cannot be empty"
  else if not (is_hex_string value) then
    Error
      (Printf.sprintf
         "checksum must be hexadecimal (optionally prefixed with sha256: or \
          sha512:): %s"
         trimmed)
  else if algorithm = "sha256" || algorithm = "sha512" then
    Ok { algorithm; value }
  else
    Error
      (Printf.sprintf
         "unsupported checksum algorithm '%s'; expected sha256 or sha512"
         algorithm)

let parse_git_checksum value =
  let trimmed = String.trim value in
  let raw_value =
    match String_util.split_once ~on:':' trimmed with
    | Some (raw_algorithm, raw_value) ->
        let algorithm = String.lowercase_ascii (String.trim raw_algorithm) in
        if algorithm = "sha1" || algorithm = "sha256" || algorithm = "git" then
          raw_value
        else trimmed
    | None -> trimmed
  in
  let value = normalize_hex raw_value in
  if value = "" then Error "checksum cannot be empty"
  else if not (is_hex_string value) then
    Error
      (Printf.sprintf
         "git checksum pins must be hexadecimal commit ids: %s" trimmed)
  else Ok value

let current_git_revision checkout_dir =
  let* outcome =
    Process.ensure_success ~cwd:checkout_dir "git" [ "rev-parse"; "HEAD" ]
    |> Result.map_error (fun message ->
           "failed to resolve the vendored git revision\n" ^ message)
  in
  Ok (normalize_hex outcome.output)

let checksum_program algorithm =
  match Toolchain.resolve_executable_path "shasum" with
  | Some prog ->
      let digits =
        if algorithm = "sha256" then "256"
        else if algorithm = "sha512" then "512"
        else algorithm
      in
      Ok (prog, [ "-a"; digits ])
  | None -> (
      match algorithm with
      | "sha256" -> (
          match Toolchain.resolve_executable_path "sha256sum" with
          | Some prog -> Ok (prog, [])
          | None ->
              Error
                "unable to verify sha256 checksums; install `shasum` or \
                 `sha256sum`" )
      | "sha512" -> (
          match Toolchain.resolve_executable_path "sha512sum" with
          | Some prog -> Ok (prog, [])
          | None ->
              Error
                "unable to verify sha512 checksums; install `shasum` or \
                 `sha512sum`" )
      | algorithm ->
          Error
            (Printf.sprintf "unsupported checksum algorithm '%s'" algorithm))

let file_checksum path checksum =
  let* prog, prefix_args = checksum_program checksum.algorithm in
  let* outcome =
    Process.ensure_success ~env:[ ("LC_ALL", "C"); ("LANG", "C") ] prog
      (prefix_args @ [ path ])
    |> Result.map_error (fun message ->
           Printf.sprintf "failed to compute %s for %s\n%s" checksum.algorithm
             path message)
  in
  match String_util.split_whitespace outcome.output with
  | digest :: _ -> Ok (normalize_hex digest)
  | [] ->
      Error
        (Printf.sprintf "failed to parse %s output for %s" checksum.algorithm path)

let detect_extracted_root directory =
  let entries =
    Sys.readdir directory |> Array.to_list
    |> List.filter (fun entry -> not (List.mem entry [ ".DS_Store"; "__MACOSX" ]))
  in
  match entries with
  | [ entry ] ->
      let candidate = Filename.concat directory entry in
      if Fs.is_directory candidate then candidate else directory
  | _ -> directory

let prepare_local_source source_dir f =
  f
    {
      source_dir;
      source_label = Fs.realpath source_dir;
      suggested_name = Filename.basename source_dir;
    }

let strip_suffix_if_present ~suffix value =
  if String_util.ends_with ~suffix value then
    String.sub value 0 (String.length value - String.length suffix)
  else value

let suggested_name_from_url url =
  let trimmed =
    String.trim url |> strip_suffix_if_present ~suffix:"/"
    |> strip_suffix_if_present ~suffix:".git"
    |> strip_suffix_if_present ~suffix:".tar.gz"
    |> strip_suffix_if_present ~suffix:".tgz"
    |> strip_suffix_if_present ~suffix:".tar"
    |> strip_suffix_if_present ~suffix:".zip"
  in
  let name = Filename.basename trimmed in
  if name = "" || name = "." || name = "/" then "vendor" else name

let prepare_git_source url ref_name checksum f =
  with_temp_dir "wadi-vendor-git" (fun temp_dir ->
      let checkout_dir = Filename.concat temp_dir "checkout" in
      let* _ =
        Process.ensure_success "git" [ "clone"; "--quiet"; url; checkout_dir ]
        |> Result.map_error (fun message ->
               "failed to clone the vendored git source\n" ^ message)
      in
      let* () =
        match ref_name with
        | None -> Ok ()
        | Some ref_name ->
            Process.ensure_success ~cwd:checkout_dir "git"
              [ "checkout"; "--quiet"; ref_name ]
            |> Result.map_error (fun message ->
                   Printf.sprintf
                     "failed to checkout vendored git ref %s\n%s"
                     ref_name message)
            |> Result.map (fun _ -> ())
      in
      let* expected_revision = parse_git_checksum checksum in
      let* actual_revision = current_git_revision checkout_dir in
      if actual_revision <> expected_revision then
        Error
          (Printf.sprintf
             "git source checksum mismatch for %s: expected commit %s, got %s"
             url expected_revision actual_revision)
      else
        f
          {
            source_dir = checkout_dir;
            source_label = url ^ "@" ^ actual_revision;
            suggested_name = suggested_name_from_url url;
          })

let prepare_url_source url checksum f =
  with_temp_dir "wadi-vendor-url" (fun temp_dir ->
      let archive_path = Filename.concat temp_dir "downloaded-source" in
      let extract_dir = Filename.concat temp_dir "extract" in
      Fs.ensure_dir extract_dir;
      let* _ =
        Process.ensure_success "curl"
          [ "-fsSL"; "--location"; "-o"; archive_path; url ]
        |> Result.map_error (fun message ->
               "failed to download the vendored source archive\n" ^ message)
      in
      let* checksum = parse_archive_checksum checksum in
      let* actual_checksum = file_checksum archive_path checksum in
      if actual_checksum <> checksum.value then
        Error
          (Printf.sprintf
             "archive checksum mismatch for %s: expected %s:%s, got %s:%s"
             url checksum.algorithm checksum.value checksum.algorithm
             actual_checksum)
      else
        let* _ =
          Process.ensure_success "tar"
            [ "-xf"; archive_path; "-C"; extract_dir ]
          |> Result.map_error (fun message ->
                 "failed to extract the vendored source archive\n" ^ message)
        in
        let source_dir = detect_extracted_root extract_dir in
        f
          {
            source_dir;
            source_label =
              Printf.sprintf "%s#%s:%s" url checksum.algorithm checksum.value;
            suggested_name =
              if source_dir <> extract_dir then Filename.basename source_dir
              else suggested_name_from_url url;
          })

let with_prepared_source source f =
  match source with
  | Local_dir source_dir -> prepare_local_source source_dir f
  | Git_repo { url; ref_name; checksum } ->
      prepare_git_source url ref_name checksum f
  | Url_archive { url; checksum } -> prepare_url_source url checksum f

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

let vendor ~workspace_root source ?name ~force () =
  if not (Fs.is_directory workspace_root) then
    Error (Printf.sprintf "workspace directory does not exist: %s" workspace_root)
  else
    let manifest_path = Filename.concat workspace_root Manifest.default_filename in
    if not (Fs.exists manifest_path) then
      Error (Printf.sprintf "manifest not found: %s" manifest_path)
    else
      with_prepared_source source (fun prepared ->
          if not (Fs.is_directory prepared.source_dir) then
            Error
              (Printf.sprintf "vendor source directory does not exist: %s"
                 prepared.source_dir)
          else
            let source_manifest_path =
              Filename.concat prepared.source_dir Manifest.default_filename
            in
            if not (Fs.exists source_manifest_path) then
              Error
                (Printf.sprintf "vendor source manifest not found: %s"
                   source_manifest_path)
            else
              let* root_loaded = Manifest.load_local manifest_path in
              let* () = validate_member_manifest source_manifest_path in
              let vendor_name =
                match name with
                | Some name -> name
                | None -> prepared.suggested_name
              in
              let* vendor_name = validate_name "vendor name" vendor_name in
              let member_path = Filename.concat "vendor" vendor_name in
              let workspace_root = Fs.realpath workspace_root in
              let source_dir = Fs.realpath prepared.source_dir in
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
                let already_registered =
                  List.mem member_path root_loaded.members
                in
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
                      source_label = prepared.source_label;
                      destination_dir;
                      member_path;
                      manifest_path;
                      replaced;
                      registered = not already_registered;
                    }))

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
      Printf.sprintf "%s %s -> %s" action report.source_label
        report.destination_dir;
      member_line;
    ]
  ^ "\n"
