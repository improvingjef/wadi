type archive_input =
  | Source_archive of string
  | Source_archive_dir of string
  | Reuse_source_archive_dir of string

type source_archive_mode =
  | Tracked
  | Worktree

type options = {
  root_dir : string;
  output_dir : string;
  opam_output : string option;
  formula_output : string option;
  checksums_output : string option;
  asset_index_output : string option;
  archive_input : archive_input option;
  source_archive_mode : source_archive_mode;
}

type asset = {
  name : string;
  kind : string;
  os_name : string option;
  arch_name : string option;
  url : string;
  sha256 : string;
  size_bytes : int;
}

let ( let* ) = Result.bind

let double_quote text =
  "\"" ^ String.escaped text ^ "\""

let sha256_for_file path =
  let command =
    Process.run_capture "sh"
      [
        "-c";
        "if command -v sha256sum >/dev/null 2>&1; then \
         sha256sum \"$1\" | awk '{print $1}'; \
         else \
         shasum -a 256 \"$1\" | awk '{print $1}'; \
         fi";
        "sh";
        path;
      ]
  in
  if command.status = 0 then Ok (String.trim command.output)
  else Error ("failed to compute sha256 for " ^ path ^ "\n" ^ command.output)

let render_opam (metadata : Release_metadata.t) =
  String.concat "\n"
    [
      "opam-version: \"2.0\"";
      "synopsis: " ^ double_quote metadata.synopsis;
      "description: \"\"\"";
      metadata.description;
      "\"\"\"";
      Printf.sprintf "maintainer: [%s]"
        (double_quote
           (Printf.sprintf "%s <%s>" metadata.maintainer_name
              metadata.maintainer_email));
      Printf.sprintf "authors: [%s]" (double_quote metadata.authors);
      Printf.sprintf "homepage: [%s]"
        (double_quote metadata.repository_url);
      Printf.sprintf "bug-reports: %s"
        (double_quote metadata.bug_reports_url);
      Printf.sprintf "dev-repo: %s" (double_quote metadata.dev_repo);
      Printf.sprintf "license: %s" (double_quote metadata.license);
      "depends: [";
      "  \"ocaml\" {>= \"5.4.0\"}";
      "  \"ocamlfind\"";
      "]";
      "build: [";
      "  [make \"release-artifacts\"]";
      "]";
      "install: [";
      "  [";
      "    \"./scripts/install_release_tree.sh\"";
      "    \"--package-root\"";
      "    \"package\"";
      "    \"--binary\"";
      (Printf.sprintf "    %S" ("_bootstrap/bin/" ^ metadata.package_name));
      "    \"--prefix\"";
      "    prefix";
      "  ]";
      "]";
      "";
    ]

let render_formula (metadata : Release_metadata.t) ~source_sha256 =
  String.concat "\n"
    [
      Printf.sprintf "class %s < Formula" metadata.formula_class;
      Printf.sprintf "  desc %S" metadata.synopsis;
      Printf.sprintf "  homepage %S" metadata.repository_url;
      Printf.sprintf "  url %S"
        (Release_metadata.source_archive_url metadata);
      Printf.sprintf "  sha256 %S" source_sha256;
      Printf.sprintf "  license %S" metadata.license;
      "";
      "  depends_on \"ocaml\"";
      "  depends_on \"ocaml-findlib\"";
      "";
      "  def install";
      "    system \"make\", \"release-artifacts\"";
      "    system \"./scripts/install_release_tree.sh\",";
      "      \"--package-root\", \"package\",";
      (Printf.sprintf "      \"--binary\", %S,"
         ("_bootstrap/bin/" ^ metadata.package_name));
      "      \"--prefix\", prefix";
      "  end";
      "";
      "  test do";
      (Printf.sprintf "    output = shell_output(\"#{bin}/%s docs\")"
         metadata.package_name);
      "    assert_match \"Oasis CLI\", output";
      "  end";
      "end";
      "";
    ]

let create_temp_dir prefix =
  let path = Filename.temp_file prefix ".tmp" in
  Unix.unlink path;
  Unix.mkdir path 0o755;
  path

let source_archive_mode_flag = function
  | Tracked -> "tracked"
  | Worktree -> "worktree"

let parse_source_archive_mode = function
  | "tracked" -> Ok Tracked
  | "worktree" -> Ok Worktree
  | value ->
      Error
        (Printf.sprintf
           "unknown source archive mode %S; expected tracked or worktree"
           value)

let build_source_archive ~root_dir ~output_dir ~source_archive_mode
    (metadata : Release_metadata.t) =
  let script_path = Filename.concat root_dir "scripts/build_release_archives.sh" in
  let command =
    Process.run_capture ~cwd:root_dir script_path
      [
        "--source-only";
        "--output-dir";
        output_dir;
        "--source-archive-mode";
        source_archive_mode_flag source_archive_mode;
      ]
  in
  if command.status <> 0 then
    Error
      ("failed to build source archive under " ^ output_dir ^ "\n"
     ^ command.output)
  else
    let archive_path =
      Filename.concat output_dir (Release_metadata.source_archive_name metadata)
    in
    if Fs.exists archive_path then Ok archive_path
    else
      Error
        ("source archive was not produced at expected path: " ^ archive_path)

let resolve_source_archive ~root_dir ~source_archive_mode
    (metadata : Release_metadata.t) = function
  | Some (Source_archive path) ->
      if Fs.exists path then Ok path
      else Error ("source archive not found: " ^ path)
  | Some (Reuse_source_archive_dir dir) ->
      let path =
        Filename.concat dir (Release_metadata.source_archive_name metadata)
      in
      if Fs.exists path then Ok path
      else Error ("reusable source archive not found: " ^ path)
  | Some (Source_archive_dir dir) ->
      Fs.ensure_dir dir;
      build_source_archive ~root_dir ~output_dir:dir ~source_archive_mode
        metadata
  | None ->
      let temp_dir = create_temp_dir "oasis-release-manifests" in
      Fun.protect
        ~finally:(fun () -> Fs.remove_tree temp_dir)
        (fun () ->
          match
            build_source_archive ~root_dir ~output_dir:temp_dir
              ~source_archive_mode metadata
          with
          | Ok archive_path ->
              let retained =
                Filename.concat root_dir
                  (Filename.concat "_oasis"
                     (Filename.concat "tmp"
                        (Release_metadata.source_archive_name metadata)))
              in
              Fs.copy_file ~src:archive_path ~dst:retained;
              Ok retained
          | Error _ as error -> error)

let tar_gz_files dir =
  if not (Fs.is_directory dir) then []
  else
    Sys.readdir dir |> Array.to_list |> List.sort String.compare
    |> List.filter (fun name -> String_util.ends_with ~suffix:".tar.gz" name)
    |> List.map (Filename.concat dir)

let checksum_inputs ~source_archive ~output_dir ~opam_output ~formula_output =
  let archives =
    String_util.dedup_preserve (source_archive :: tar_gz_files output_dir)
  in
  archives
  @ List.filter Fs.exists [ opam_output; formula_output ]

let render_checksums paths =
  let rec loop acc = function
    | [] -> Ok (String.concat "\n" (List.rev acc) ^ "\n")
    | path :: rest ->
        let* sha256 = sha256_for_file path in
        loop ((sha256 ^ "  " ^ path) :: acc) rest
  in
  loop [] paths

let classify_archive_name (metadata : Release_metadata.t) archive_name =
  if archive_name = Release_metadata.source_archive_name metadata then
    ("source_archive", None, None)
  else
    let prefix = Release_metadata.source_dir_name metadata ^ "-" in
    let suffix = ".tar.gz" in
    if
      String_util.starts_with ~prefix archive_name
      && String_util.ends_with ~suffix archive_name
    then
      let remainder =
        String.sub archive_name (String.length prefix)
          (String.length archive_name - String.length prefix - String.length suffix)
      in
      match String_util.split_once ~on:'-' remainder with
      | Some (arch_name, os_name) when arch_name <> "" && os_name <> "" ->
          ("binary_archive", Some os_name, Some arch_name)
      | _ -> ("archive", None, None)
    else ("archive", None, None)

let asset_of_path (metadata : Release_metadata.t) ~kind ~os_name ~arch_name
    path =
  let* sha256 = sha256_for_file path in
  let name = Filename.basename path in
  let size_bytes = (Unix.stat path).Unix.st_size in
  Ok
    {
      name;
      kind;
      os_name;
      arch_name;
      url = Release_metadata.asset_url metadata name;
      sha256;
      size_bytes;
    }

let collect_assets (metadata : Release_metadata.t) ~source_archive ~output_dir ~opam_output
    ~formula_output ~checksums_output =
  let seen = Hashtbl.create 16 in
  let append_unique path acc =
    let name = Filename.basename path in
    if not (Fs.exists path) || Hashtbl.mem seen name then Ok acc
    else (
      Hashtbl.add seen name ();
      let kind, os_name, arch_name =
        if String_util.ends_with ~suffix:".tar.gz" name then
          classify_archive_name metadata name
        else if name = Filename.basename opam_output then
          ("opam_metadata", None, None)
        else if name = Filename.basename formula_output then
          ("homebrew_formula", None, None)
        else ("checksums", None, None)
      in
      let* asset = asset_of_path metadata ~kind ~os_name ~arch_name path in
      Ok (acc @ [ asset ]))
  in
  let rec append_many acc = function
    | [] -> Ok acc
    | path :: rest ->
        let* acc = append_unique path acc in
        append_many acc rest
  in
  append_many []
    (source_archive :: tar_gz_files output_dir
   @ [ opam_output; formula_output ]
   @
   match checksums_output with
   | Some path -> [ path ]
   | None -> [])

let render_asset_index (metadata : Release_metadata.t) assets =
  let render_asset asset =
    let os_lines =
      match asset.os_name with
      | Some value ->
          [ Printf.sprintf "      \"os\": %s," (double_quote value) ]
      | None -> []
    in
    let arch_lines =
      match asset.arch_name with
      | Some value ->
          [ Printf.sprintf "      \"arch\": %s," (double_quote value) ]
      | None -> []
    in
    String.concat "\n"
      ([
         "    {";
         Printf.sprintf "      \"name\": %s,"
           (double_quote asset.name);
         Printf.sprintf "      \"kind\": %s,"
           (double_quote asset.kind);
       ]
      @ os_lines
      @ arch_lines
      @ [
          Printf.sprintf "      \"url\": %s,"
            (double_quote asset.url);
          Printf.sprintf "      \"sha256\": %s,"
            (double_quote asset.sha256);
          Printf.sprintf "      \"size_bytes\": %d" asset.size_bytes;
          "    }";
        ])
  in
  let rendered_assets =
    assets |> List.map render_asset
    |> List.mapi (fun index rendered ->
           if index = List.length assets - 1 then rendered else rendered ^ ",")
  in
  String.concat "\n"
    [
      "{";
      "  \"schema_version\": 1,";
      Printf.sprintf "  \"package\": %s,"
        (double_quote metadata.package_name);
      Printf.sprintf "  \"version\": %s,"
        (double_quote metadata.release_version);
      Printf.sprintf "  \"tag\": %s,"
        (double_quote (Release_metadata.release_tag metadata));
      Printf.sprintf "  \"base_url\": %s,"
        (double_quote (Release_metadata.download_base_url metadata));
      "  \"assets\": [";
      String.concat "\n" rendered_assets;
      "  ]";
      "}";
      "";
    ]

let default_formula_output output_dir (metadata : Release_metadata.t) =
  Filename.concat output_dir
    (Filename.concat "Formula" (metadata.package_name ^ ".rb"))

let default_opam_output output_dir (metadata : Release_metadata.t) =
  Filename.concat output_dir (metadata.package_name ^ ".opam")

let run (options : options) =
  let* metadata = Release_metadata.load_for_root ~root_dir:options.root_dir () in
  let opam_output =
    match options.opam_output with
    | Some path -> path
    | None -> default_opam_output options.output_dir metadata
  in
  let formula_output =
    match options.formula_output with
    | Some path -> path
    | None -> default_formula_output options.output_dir metadata
  in
  let* source_archive =
    resolve_source_archive ~root_dir:options.root_dir
      ~source_archive_mode:options.source_archive_mode metadata
      options.archive_input
  in
  Fs.ensure_dir options.output_dir;
  Fs.write_file opam_output (render_opam metadata);
  let* source_sha256 = sha256_for_file source_archive in
  Fs.write_file formula_output (render_formula metadata ~source_sha256);
  let* () =
    match options.checksums_output with
    | None -> Ok ()
    | Some path ->
        let checksum_paths =
          checksum_inputs ~source_archive ~output_dir:options.output_dir
            ~opam_output ~formula_output
        in
        let archive_count =
          List.length
            (String_util.dedup_preserve
               (source_archive :: tar_gz_files options.output_dir))
        in
        if archive_count = 0 then
          Error
            ("no release archives found under " ^ options.output_dir
           ^ " for --checksums-output")
        else
          let* contents = render_checksums checksum_paths in
          Fs.write_file path contents;
          Ok ()
  in
  match options.asset_index_output with
  | None -> Ok ()
  | Some path ->
      let* assets =
        collect_assets metadata ~source_archive ~output_dir:options.output_dir
          ~opam_output ~formula_output
          ~checksums_output:options.checksums_output
      in
      Fs.write_file path (render_asset_index metadata assets);
      Ok ()
