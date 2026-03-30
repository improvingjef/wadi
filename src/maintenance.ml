type update_homebrew_tap_options = {
  root_dir : string;
  tap_dir : string;
  formula_path : string option;
  source_archive : string option;
  do_commit : bool;
  do_push : bool;
}

let ( let* ) = Result.bind

let manifest_path root_dir =
  Filename.concat root_dir Manifest.default_filename

let bootstrap_seed_root root_dir =
  Filename.concat root_dir (Filename.concat "_bootstrap" "seed")

let bootstrap_seed_metadata_path root_dir =
  Filename.concat root_dir
    (Filename.concat "_bootstrap" "bootstrap.seed-metadata.mk")

let write_file_if_changed path contents =
  if Fs.exists path && Fs.read_file path = contents then ()
  else (
    let temp_path = path ^ ".tmp" in
    Fs.write_file temp_path contents;
    Unix.rename temp_path path)

let refresh_bootstrap_seed_metadata ~root_dir =
  let manifest_path = manifest_path root_dir in
  let seed_root = bootstrap_seed_root root_dir in
  let output_path = bootstrap_seed_metadata_path root_dir in
  let* contents =
    Bootstrap.render_seed_metadata ~seed_root ~manifest_path ()
  in
  write_file_if_changed output_path contents;
  Ok output_path

let run_command ?cwd ?(env = []) prog args =
  let outcome = Process.run_capture ?cwd ~env prog args in
  if outcome.status = 0 then Ok outcome
  else
    Error
      (Printf.sprintf "command failed (%s)\n%s"
         (Process.render ?cwd ~env prog args)
         outcome.output)

let ensure_git_repo root_dir =
  let outcome =
    Process.run_capture ~cwd:root_dir "git" [ "rev-parse"; "--is-inside-work-tree" ]
  in
  if outcome.status = 0 then Ok ()
  else Error ("not a git repository: " ^ root_dir)

let validate_version version =
  let parts = String_util.split_dot version in
  if List.length parts <> 3 then
    Error "version must look like X.Y.Z"
  else
    let valid_part part =
      let part = String.trim part in
      part <> ""
      &&
      let rec loop index =
        if index = String.length part then true
        else
          match part.[index] with
          | '0' .. '9' -> loop (index + 1)
          | _ -> false
      in
      loop 0
    in
    if List.for_all valid_part parts then Ok ()
    else Error "version must look like X.Y.Z"

let update_release_version ~metadata_path version =
  let contents = Fs.read_file metadata_path in
  let lines = String.split_on_char '\n' contents in
  let updated = ref false in
  let rewritten =
    List.map
      (fun line ->
        if String_util.starts_with ~prefix:"OASIS_RELEASE_VERSION=" line then (
          updated := true;
          Printf.sprintf "OASIS_RELEASE_VERSION='%s'" version)
        else line)
      lines
  in
  if not !updated then
    Error ("failed to update " ^ metadata_path)
  else (
    write_file_if_changed metadata_path (String.concat "\n" rewritten);
    Ok ())

let render_formula_from_archive metadata source_archive =
  if not (Fs.exists source_archive) then
    Error ("source archive not found: " ^ source_archive)
  else
    let* source_sha256 = Packager.sha256_for_file source_archive in
    Ok (Packager.render_formula metadata ~source_sha256)

let homebrew_formula_contents metadata = function
  | Some formula_path, None ->
      if Fs.exists formula_path then Ok (Fs.read_file formula_path)
      else Error ("formula not found: " ^ formula_path)
  | None, Some source_archive ->
      render_formula_from_archive metadata source_archive
  | Some _, Some _ ->
      Error "pass --formula or --source-archive, not both"
  | None, None -> Error "provide --formula or --source-archive"

let tap_needs_clone tap_dir =
  let git_dir = Filename.concat tap_dir ".git" in
  if Fs.is_directory git_dir then Ok false
  else if not (Fs.exists tap_dir) then Ok true
  else if not (Fs.is_directory tap_dir) then
    Error ("tap dir is not a directory: " ^ tap_dir)
  else if Array.length (Sys.readdir tap_dir) = 0 then Ok true
  else Error ("tap dir is not a git checkout: " ^ tap_dir)

let update_homebrew_tap (options : update_homebrew_tap_options) =
  if options.do_push && not options.do_commit then
    Error "--push requires --commit"
  else
    let* metadata = Release_metadata.load_for_root ~root_dir:options.root_dir () in
    let* formula_contents =
      homebrew_formula_contents metadata
        (options.formula_path, options.source_archive)
    in
    let* should_clone = tap_needs_clone options.tap_dir in
    let* () =
      if should_clone then
        let clone_url = Release_metadata.homebrew_tap_clone_url metadata in
        run_command "git" [ "clone"; clone_url; options.tap_dir ] |> Result.map ignore
      else Ok ()
    in
    let formula_output = Filename.concat options.tap_dir "Formula/oasis.rb" in
    write_file_if_changed formula_output formula_contents;
    let status =
      Process.run_capture ~cwd:options.tap_dir "git"
        [ "status"; "--short"; "--"; "Formula/oasis.rb" ]
    in
    if status.status <> 0 then
      Error
        (Printf.sprintf "failed to inspect tap status\n%s" status.output)
    else if String.trim status.output = "" then
      Ok (Printf.sprintf "Homebrew tap already up to date: %s" formula_output)
    else
      let* () =
        if options.do_commit then
          let* _ =
            run_command ~cwd:options.tap_dir "git"
              [ "add"; "Formula/oasis.rb" ]
          in
          let* _ =
            run_command ~cwd:options.tap_dir
              ~env:
                [
                  ("GIT_AUTHOR_NAME", metadata.maintainer_name);
                  ("GIT_AUTHOR_EMAIL", metadata.maintainer_email);
                  ("GIT_COMMITTER_NAME", metadata.maintainer_name);
                  ("GIT_COMMITTER_EMAIL", metadata.maintainer_email);
                ]
              "git"
              [
                "commit";
                "-m";
                metadata.package_name ^ " " ^ Release_metadata.release_tag metadata;
              ]
          in
          Ok ()
        else Ok ()
      in
      let* () =
        if options.do_push then
          run_command ~cwd:options.tap_dir "git" [ "push"; "origin"; "HEAD" ]
          |> Result.map ignore
        else Ok ()
      in
      Ok
        (Printf.sprintf "Updated %s for brew tap %s && brew install %s"
           formula_output metadata.homebrew_tap metadata.package_name)

let cut_release ~root_dir ~version ~create_tag =
  let* () = validate_version version in
  let* () = ensure_git_repo root_dir in
  let metadata_path = Release_metadata.metadata_path ~root_dir () in
  let* () = update_release_version ~metadata_path version in
  let* metadata = Release_metadata.load_for_root ~root_dir () in
  let dist_dir = Filename.concat root_dir "dist" in
  let asset_index_path =
    Filename.concat dist_dir (Release_metadata.asset_index_name metadata)
  in
  let* () =
    let packaging_options : Packager.options =
      {
        root_dir;
        output_dir = root_dir;
        opam_output = None;
        formula_output = None;
        checksums_output = None;
        asset_index_output = Some asset_index_path;
        archive_input = Some (Packager.Source_archive_dir dist_dir);
      }
    in
    Packager.run packaging_options
  in
  let* _ =
    run_command ~cwd:root_dir "ruby" [ "-c"; Filename.concat "Formula" "oasis.rb" ]
  in
  let* _ = run_command ~cwd:root_dir "opam" [ "lint"; "oasis.opam" ] in
  let expected_tag = Release_metadata.release_tag metadata in
  let* () =
    if create_tag then
      let existing =
        Process.run_capture ~cwd:root_dir "git"
          [ "rev-parse"; "-q"; "--verify"; "refs/tags/" ^ expected_tag ]
      in
      if existing.status = 0 then
        Error ("git tag already exists: " ^ expected_tag)
      else
        run_command ~cwd:root_dir
          ~env:
            [
              ("GIT_AUTHOR_NAME", metadata.maintainer_name);
              ("GIT_AUTHOR_EMAIL", metadata.maintainer_email);
              ("GIT_COMMITTER_NAME", metadata.maintainer_name);
              ("GIT_COMMITTER_EMAIL", metadata.maintainer_email);
            ]
          "git"
          [
            "tag";
            "-a";
            expected_tag;
            "-m";
            metadata.package_name ^ " " ^ version;
          ]
        |> Result.map ignore
    else Ok ()
  in
  Ok
    (Printf.sprintf
       "Release cut for %s refreshed release/metadata.sh, oasis.opam, \
        Formula/oasis.rb, dist/%s, and %s"
       expected_tag (Release_metadata.source_archive_name metadata) asset_index_path)
