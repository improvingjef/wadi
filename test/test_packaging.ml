open Test_support

let nonempty_lines text =
  text |> String.split_on_char '\n' |> List.filter (fun line -> line <> "")

let copy_tracked_repo ~src_root ~dst_root ?(extra_paths = []) () =
  let listed = Process.run_capture ~cwd:src_root "git" [ "ls-files" ] in
  assert_int_equal 0 listed.status
    ("git ls-files should succeed before copying a tracked repo\n" ^ listed.output);
  let untracked_worktree_sources =
    Process.run_capture ~cwd:src_root "git"
      [
        "ls-files";
        "--others";
        "--exclude-standard";
        "--";
        "src";
        "test";
        "scripts";
      ]
  in
  assert_int_equal 0 untracked_worktree_sources.status
    ( "git ls-files --others should succeed before copying a tracked repo\n"
    ^ untracked_worktree_sources.output );
  let paths =
    nonempty_lines listed.output @ nonempty_lines untracked_worktree_sources.output
    @ extra_paths |> String_util.dedup_preserve
  in
  List.iter
    (fun relative_path ->
      let src = Filename.concat src_root relative_path in
      let dst = Filename.concat dst_root relative_path in
        if Fs.exists src then Fs.copy_file ~src ~dst)
    paths

let set_shell_binding path ~name ~value =
  let prefix = name ^ "=" in
  let replaced = ref false in
  let contents =
    Fs.read_file path
    |> String.split_on_char '\n'
    |> List.map (fun line ->
           if String_util.starts_with ~prefix line then (
             replaced := true;
             Printf.sprintf "%s='%s'" name value)
           else line)
  in
  Fs.write_file path
    (String.concat "\n"
       (if !replaced then contents
        else contents @ [ Printf.sprintf "%s='%s'" name value ]))

let chmod_plus_x path =
  let chmod = Process.run_capture "chmod" [ "+x"; path ] in
  assert_int_equal 0 chmod.status
    ("chmod +x should succeed for " ^ path ^ "\n" ^ chmod.output)

let run_make ?(use_wadi_bin = true) ~cwd goals =
  let env =
    [
      ("MAKEFLAGS", "");
      ("MFLAGS", "");
      ("MAKELEVEL", "0");
      ("OCAMLOPT", "ocamlopt");
      ("OCAMLFIND", "ocamlfind");
      ("OCAMLFLAGS", "-g");
    ]
    @ if use_wadi_bin then [ ("WADI_BIN", wadi_bin ()) ] else []
  in
  if use_wadi_bin then Process.run_capture ~cwd ~env "make" goals
  else Process.run_capture ~cwd ~env "env" ([ "-u"; "WADI_BIN"; "make" ] @ goals)

let release_metadata_eval ~cwd expr =
  let command =
    Process.run_capture ~cwd "sh" [ "-c"; ". release/metadata.sh; " ^ expr ]
  in
  assert_int_equal 0 command.status
    ("release metadata evaluation should succeed\n" ^ command.output);
  String.trim command.output

let release_download_base_url ~cwd =
  release_metadata_eval ~cwd "wadi_release_download_base_url"

let release_asset_index_name ~cwd =
  release_metadata_eval ~cwd "wadi_release_asset_index_name"

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
  assert_int_equal 0 command.status
    ("sha256 helper should succeed for " ^ path ^ "\n" ^ command.output);
  String.trim command.output

let render_asset_index_entry ~base_url ~name ~kind ?os ?arch ~sha256
    ~size_bytes () =
  let lines =
    [
      "    {";
      Printf.sprintf "      \"name\": %S," name;
      Printf.sprintf "      \"kind\": %S," kind;
    ]
  in
  let lines =
    match os with
    | Some value -> lines @ [ Printf.sprintf "      \"os\": %S," value ]
    | None -> lines
  in
  let lines =
    match arch with
    | Some value -> lines @ [ Printf.sprintf "      \"arch\": %S," value ]
    | None -> lines
  in
  String.concat "\n"
    (lines
    @ [
        Printf.sprintf "      \"url\": %S," (base_url ^ "/" ^ name);
        Printf.sprintf "      \"sha256\": %S," sha256;
        Printf.sprintf "      \"size_bytes\": %d" size_bytes;
        "    }";
      ])

let cases =
  [
    ( "installs the staged release tree under a prefix",
      (fun () ->
        let repo_root = Sys.getcwd () in
        let release_script =
          Filename.concat repo_root "scripts/generate_release_artifacts.sh"
        in
        let install_script =
          Filename.concat repo_root "scripts/install_release_tree.sh"
        in
        with_temp_dir "wadi-packaging-release" (fun output_dir ->
            with_temp_dir "wadi-packaging-prefix" (fun prefix ->
                let generated =
                  Process.run_capture ~cwd:repo_root
                    ~env:[ ("WADI_BIN", wadi_bin ()) ]
                    release_script [ "--output-dir"; output_dir ]
                in
                assert_int_equal 0 generated.status
                  "release artifact generation should succeed before install";
                assert_string_not_contains ~needle:"setlocale" generated.output
                  "release artifact generation should not leak shell locale warnings";
                let installed =
                  Process.run_capture ~cwd:repo_root install_script
                    [
                      "--package-root";
                      Filename.concat output_dir "package";
                      "--binary";
                      wadi_bin ();
                      "--prefix";
                      prefix;
                    ]
                in
                assert_int_equal 0 installed.status
                  "install_release_tree.sh should stage the release tree";
                assert_file_exists (Filename.concat prefix "bin/wadi");
                assert_file_exists
                  (Filename.concat prefix "share/doc/wadi/cli.md");
                assert_file_exists
                  (Filename.concat prefix
                     "share/bash-completion/completions/wadi");
                assert_file_exists
                  (Filename.concat prefix "share/zsh/site-functions/_wadi");
                assert_file_exists
                  (Filename.concat prefix
                     "share/fish/vendor_completions.d/wadi.fish");
                let installed_docs =
                  run_binary (Filename.concat prefix "bin/wadi") [ "docs" ]
                in
                assert_int_equal 0 installed_docs.status
                  "the installed wadi binary should remain runnable";
                assert_string_equal installed_docs.output
                  (Fs.read_file
                     (Filename.concat prefix "share/doc/wadi/cli.md"))
                  "the installed doc copy should come from the installed binary"))) );
    ( "release-artifacts renders docs and packaged completions from the live binary",
      (fun () ->
        let repo_root = Sys.getcwd () in
        with_temp_dir "wadi-packaging-release-command" (fun output_dir ->
            let generated =
              run_wadi ~cwd:repo_root
                [ "release-artifacts"; "--output-dir"; output_dir ]
            in
            assert_int_equal 0 generated.status
              "release-artifacts should render successfully";
            let docs = run_wadi ~cwd:repo_root [ "docs" ] in
            let bash_completion =
              run_wadi ~cwd:repo_root [ "completion"; "bash" ]
            in
            let zsh_completion =
              run_wadi ~cwd:repo_root [ "completion"; "zsh" ]
            in
            let fish_completion =
              run_wadi ~cwd:repo_root [ "completion"; "fish" ]
            in
            assert_int_equal 0 docs.status
              "docs should render successfully before comparing release artifacts";
            assert_int_equal 0 bash_completion.status
              "bash completion should render successfully before comparing release artifacts";
            assert_int_equal 0 zsh_completion.status
              "zsh completion should render successfully before comparing release artifacts";
            assert_int_equal 0 fish_completion.status
              "fish completion should render successfully before comparing release artifacts";
            assert_string_equal docs.output
              (Fs.read_file (Filename.concat output_dir "docs/cli.md"))
              "release-artifacts should write the live CLI docs";
            assert_string_equal bash_completion.output
              (Fs.read_file (Filename.concat output_dir "completions/wadi.bash"))
              "release-artifacts should write the live bash completion";
            assert_string_equal zsh_completion.output
              (Fs.read_file (Filename.concat output_dir "completions/_wadi"))
              "release-artifacts should write the live zsh completion";
            assert_string_equal fish_completion.output
              (Fs.read_file (Filename.concat output_dir "completions/wadi.fish"))
              "release-artifacts should write the live fish completion";
            assert_string_equal docs.output
              (Fs.read_file
                 (Filename.concat output_dir "package/share/doc/wadi/cli.md"))
              "release-artifacts should package the rendered docs";
            assert_string_equal bash_completion.output
              (Fs.read_file
                 (Filename.concat output_dir
                    "package/share/bash-completion/completions/wadi"))
              "release-artifacts should package the bash completion";
            assert_string_equal zsh_completion.output
              (Fs.read_file
                 (Filename.concat output_dir
                    "package/share/zsh/site-functions/_wadi"))
              "release-artifacts should package the zsh completion";
            assert_string_equal fish_completion.output
              (Fs.read_file
                 (Filename.concat output_dir
                    "package/share/fish/vendor_completions.d/wadi.fish"))
              "release-artifacts should package the fish completion")) );
    ( "package renders packaging manifests, checksums, and an asset index",
      (fun () ->
        let repo_root = Sys.getcwd () in
        with_temp_dir "wadi-packaging-command" (fun workspace ->
            let output_dir = Filename.concat workspace "out" in
            let archive_dir = Filename.concat workspace "dist" in
            let checksums_output = Filename.concat output_dir "SHA256SUMS" in
            let asset_index_output =
              Filename.concat output_dir (release_asset_index_name ~cwd:repo_root)
            in
            let generated =
              run_wadi ~cwd:repo_root
                [
                  "package";
                  "--output-dir";
                  output_dir;
                  "--source-archive-dir";
                  archive_dir;
                  "--checksums-output";
                  checksums_output;
                  "--asset-index-output";
                  asset_index_output;
                ]
            in
            assert_int_equal 0 generated.status
              "package should render packaging metadata successfully";
            let source_archive =
              Filename.concat archive_dir "wadi-0.1.0-source.tar.gz"
            in
            let opam_output = Filename.concat output_dir "wadi.opam" in
            let formula_output = Filename.concat output_dir "Formula/wadi.rb" in
            assert_file_exists source_archive;
            assert_string_equal
              (Fs.read_file opam_output)
              (Fs.read_file (Filename.concat repo_root "wadi.opam"))
              "package should render the committed opam metadata";
            assert_string_equal
              (Fs.read_file formula_output)
              (Fs.read_file (Filename.concat repo_root "Formula/wadi.rb"))
              "package should render the committed Homebrew formula";
            let checksums = Fs.read_file checksums_output in
            assert_string_contains
              ~needle:
                (sha256_for_file source_archive ^ "  " ^ source_archive)
              checksums
              "package should include the source archive in SHA256SUMS";
            assert_string_contains
              ~needle:(sha256_for_file opam_output ^ "  " ^ opam_output)
              checksums
              "package should include the rendered opam metadata in SHA256SUMS";
            assert_string_contains
              ~needle:(sha256_for_file formula_output ^ "  " ^ formula_output)
              checksums
              "package should include the rendered formula in SHA256SUMS";
            let base_url = release_download_base_url ~cwd:repo_root in
            let source_archive_entry =
              render_asset_index_entry ~base_url
                ~name:(Filename.basename source_archive)
                ~kind:"source_archive"
                ~sha256:(sha256_for_file source_archive)
                ~size_bytes:(Unix.stat source_archive).Unix.st_size ()
            in
            let checksums_entry =
              render_asset_index_entry ~base_url
                ~name:(Filename.basename checksums_output)
                ~kind:"checksums"
                ~sha256:(sha256_for_file checksums_output)
                ~size_bytes:(Unix.stat checksums_output).Unix.st_size ()
            in
            let asset_index = Fs.read_file asset_index_output in
            assert_string_contains ~needle:"\"schema_version\": 1" asset_index
              "package should write a machine-readable asset index";
            assert_string_contains ~needle:source_archive_entry asset_index
              "package should index the source archive";
            assert_string_contains ~needle:checksums_entry asset_index
              "package should index the generated checksum manifest")) );
    ( "sync-generated refreshes bootstrap metadata and release artifacts from the live binary",
      fun () ->
        let repo_root = Sys.getcwd () in
        with_temp_dir "wadi-sync-generated-command" (fun workspace ->
            copy_tracked_repo ~src_root:repo_root ~dst_root:workspace ();
            let init = Process.run_capture ~cwd:workspace "git" [ "init"; "-q" ] in
            assert_int_equal 0 init.status
              ("git init should succeed before sync-generated\n" ^ init.output);
            let add = Process.run_capture ~cwd:workspace "git" [ "add"; "." ] in
            assert_int_equal 0 add.status
              ("git add should succeed before sync-generated\n" ^ add.output);
            List.iter
              (fun relative_path ->
                let path = Filename.concat workspace relative_path in
                if Fs.exists path then Sys.remove path)
              [
                "docs/cli.md";
                "completions/wadi.bash";
                "completions/_wadi";
                "completions/wadi.fish";
                "wadi.opam";
                "Formula/wadi.rb";
              ];
            List.iter
              (fun relative_path ->
                let path = Filename.concat workspace relative_path in
                if Fs.exists path then Fs.remove_tree path)
              [ "package"; "_bootstrap"; "dist" ];
            let synced = run_wadi ~cwd:workspace [ "sync-generated" ] in
            assert_int_equal 0 synced.status
              ("wadi sync-generated should succeed\n" ^ synced.output);
            assert_file_exists
              (Filename.concat workspace "_bootstrap/bootstrap.seed-metadata.mk");
            assert_file_exists (Filename.concat workspace "docs/cli.md");
            assert_file_exists (Filename.concat workspace "completions/wadi.bash");
            assert_file_exists (Filename.concat workspace "completions/_wadi");
            assert_file_exists (Filename.concat workspace "completions/wadi.fish");
            assert_file_exists (Filename.concat workspace "wadi.opam");
            assert_file_exists (Filename.concat workspace "Formula/wadi.rb");
            assert_file_exists (Filename.concat workspace "dist/release-assets.json");
            assert_file_exists
              (Filename.concat workspace "dist/wadi-0.1.0-source.tar.gz");
            assert_string_equal
              (Fs.read_file (Filename.concat workspace "docs/cli.md"))
              (Fs.read_file
                 (Filename.concat workspace "package/share/doc/wadi/cli.md"))
              "sync-generated should keep the packaged doc copy aligned with wadi docs"));
    ( "package rejects conflicting source-archive inputs",
      (fun () ->
        let repo_root = Sys.getcwd () in
        let generated =
          run_wadi ~cwd:repo_root
            [
              "package";
              "--source-archive";
              "dist/wadi-0.1.0-source.tar.gz";
              "--source-archive-dir";
              "dist";
            ]
        in
        assert_true (generated.status <> 0)
          "package should reject conflicting source-archive selectors";
        assert_string_contains
          ~needle:
            "pass only one of --source-archive, --source-archive-dir, or --reuse-source-archive-dir"
          generated.output
          "package should explain the mutually exclusive archive selectors") );
    ( "generates packaging manifests from the canonical release metadata",
      fun () ->
        let repo_root = Sys.getcwd () in
        let manifest_script =
          Filename.concat repo_root "scripts/generate_packaging_manifests.sh"
        in
        with_temp_dir "wadi-packaging-manifests" (fun output_dir ->
            let generated =
              Process.run_capture ~cwd:repo_root manifest_script
                [ "--output-dir"; output_dir ]
            in
            assert_int_equal 0 generated.status
              "packaging manifest generation should succeed";
            assert_string_not_contains ~needle:"setlocale" generated.output
              "packaging manifest generation should not leak shell locale warnings";
            assert_string_equal
              (Fs.read_file (Filename.concat output_dir "wadi.opam"))
              (Fs.read_file (Filename.concat repo_root "wadi.opam"))
              "wadi.opam should be generated from the shared release metadata";
            assert_string_equal
              (Fs.read_file (Filename.concat output_dir "Formula/wadi.rb"))
              (Fs.read_file (Filename.concat repo_root "Formula/wadi.rb"))
              "the committed Homebrew formula should be generated from the shared release metadata"));
    ( "can write the generated opam file to an explicit output path",
      fun () ->
        let repo_root = Sys.getcwd () in
        let manifest_script =
          Filename.concat repo_root "scripts/generate_packaging_manifests.sh"
        in
        with_temp_dir "wadi-packaging-opam-output" (fun workspace ->
            let output_dir = Filename.concat workspace "out" in
            let custom_opam = Filename.concat workspace "release/wadi-package.opam" in
            let generated =
              Process.run_capture ~cwd:repo_root manifest_script
                [
                  "--output-dir";
                  output_dir;
                  "--opam-output";
                  custom_opam;
                ]
            in
            assert_int_equal 0 generated.status
              "packaging manifest generation should allow an explicit opam output path";
            assert_true
              (not (Fs.exists (Filename.concat output_dir "wadi.opam")))
              "a custom opam output path should replace the default output location";
            assert_string_equal (Fs.read_file custom_opam)
              (Fs.read_file (Filename.concat repo_root "wadi.opam"))
              "custom opam output should still render from the shared release metadata"));
    ( "can refresh a retained source archive while generating packaging manifests",
      fun () ->
        let repo_root = Sys.getcwd () in
        let manifest_script =
          Filename.concat repo_root "scripts/generate_packaging_manifests.sh"
        in
        with_temp_dir "wadi-packaging-manifests-retained" (fun workspace ->
            let output_dir = Filename.concat workspace "out" in
            let archive_dir = Filename.concat workspace "dist" in
            let generated =
              Process.run_capture ~cwd:repo_root manifest_script
                [
                  "--output-dir";
                  output_dir;
                  "--source-archive-dir";
                  archive_dir;
                ]
            in
            assert_int_equal 0 generated.status
              "packaging manifest generation should support retained source archives";
            assert_file_exists
              (Filename.concat archive_dir "wadi-0.1.0-source.tar.gz");
            assert_string_equal
              (Fs.read_file (Filename.concat output_dir "Formula/wadi.rb"))
              (Fs.read_file (Filename.concat repo_root "Formula/wadi.rb"))
              "retained-archive manifest generation should match the committed Homebrew formula"));
    ( "supports explicit tracked versus worktree source archive modes",
      fun () ->
        let repo_root = Sys.getcwd () in
        with_temp_dir "wadi-packaging-source-archive-mode" (fun workspace ->
            copy_tracked_repo ~src_root:repo_root ~dst_root:workspace ();
            let init = Process.run_capture ~cwd:workspace "git" [ "init"; "-q" ] in
            assert_int_equal 0 init.status
              ("git init should succeed before archive-mode checks\n"
             ^ init.output);
            let add = Process.run_capture ~cwd:workspace "git" [ "add"; "." ] in
            assert_int_equal 0 add.status
              ("git add should succeed before archive-mode checks\n"
             ^ add.output);
            write_workspace_file workspace "scripts/worktree_only.txt"
              "worktree-only file\n";
            let archive_script =
              Filename.concat workspace "scripts/build_release_archives.sh"
            in
            let tracked_dir = Filename.concat workspace "tracked-dist" in
            let tracked =
              Process.run_capture ~cwd:workspace archive_script
                [ "--source-only"; "--output-dir"; tracked_dir ]
            in
            assert_int_equal 0 tracked.status
              ("tracked-mode source archive generation should succeed\n"
             ^ tracked.output);
            let tracked_listing =
              Process.run_capture ~cwd:tracked_dir "tar"
                [ "-tzf"; "wadi-0.1.0-source.tar.gz" ]
            in
            assert_int_equal 0 tracked_listing.status
              "tracked-mode source archive should be readable";
            assert_string_not_contains
              ~needle:"wadi-0.1.0/scripts/worktree_only.txt\n"
              tracked_listing.output
              "tracked source archives should ignore unstaged worktree-only files";
            let worktree_dir = Filename.concat workspace "worktree-dist" in
            let worktree =
              Process.run_capture ~cwd:workspace archive_script
                [
                  "--source-only";
                  "--output-dir";
                  worktree_dir;
                  "--source-archive-mode";
                  "worktree";
                ]
            in
            assert_int_equal 0 worktree.status
              ("worktree-mode source archive generation should succeed\n"
             ^ worktree.output);
            let worktree_listing =
              Process.run_capture ~cwd:worktree_dir "tar"
                [ "-tzf"; "wadi-0.1.0-source.tar.gz" ]
            in
            assert_int_equal 0 worktree_listing.status
              "worktree-mode source archive should be readable";
            assert_string_contains
              ~needle:"wadi-0.1.0/scripts/worktree_only.txt\n"
              worktree_listing.output
              "worktree source archives should include unstaged files from tracked directories"));
    ( "reuses an existing source archive directory without rebuilding it",
      fun () ->
        let repo_root = Sys.getcwd () in
        with_temp_dir "wadi-packaging-manifests-reuse-dir" (fun workspace ->
            copy_tracked_repo ~src_root:repo_root ~dst_root:workspace ();
            let repo_archive_script =
              Filename.concat repo_root "scripts/build_release_archives.sh"
            in
            let archive_script =
              Filename.concat workspace "scripts/build_release_archives.sh"
            in
            let manifest_script =
              Filename.concat workspace "scripts/generate_packaging_manifests.sh"
            in
            let archive_dir = Filename.concat workspace "dist" in
            let output_dir = Filename.concat workspace "out" in
            let archived =
              Process.run_capture ~cwd:repo_root repo_archive_script
                [ "--source-only"; "--output-dir"; archive_dir ]
            in
            assert_int_equal 0 archived.status
              "source archive generation should succeed before reuse";
            Fs.write_file archive_script
              "#!/bin/sh\n\
               echo should-not-run-build-release-archives >&2\n\
               exit 19\n";
            chmod_plus_x archive_script;
            let generated =
              Process.run_capture ~cwd:workspace
                ~env:[ ("WADI_BIN", wadi_bin ()) ]
                manifest_script
                [
                  "--output-dir";
                  output_dir;
                  "--reuse-source-archive-dir";
                  archive_dir;
                ]
            in
            assert_int_equal 0 generated.status
              "packaging manifest generation should reuse an existing retained archive";
            assert_string_not_contains
              ~needle:"should-not-run-build-release-archives"
              generated.output
              "manifest generation should not rebuild the source archive when the retained copy already exists";
            assert_string_equal
              (Fs.read_file (Filename.concat output_dir "Formula/wadi.rb"))
              (Fs.read_file (Filename.concat workspace "Formula/wadi.rb"))
              "reused retained-archive manifest generation should still match the committed Homebrew formula"));
    ( "can reuse an explicit source archive when generating packaging manifests",
      fun () ->
        let repo_root = Sys.getcwd () in
        let manifest_script =
          Filename.concat repo_root "scripts/generate_packaging_manifests.sh"
        in
        let archive_script =
          Filename.concat repo_root "scripts/build_release_archives.sh"
        in
        with_temp_dir "wadi-packaging-manifests-archive" (fun workspace ->
            let archive_dir = Filename.concat workspace "dist" in
            let output_dir = Filename.concat workspace "out" in
            let archived =
              Process.run_capture ~cwd:repo_root archive_script
                [ "--source-only"; "--output-dir"; archive_dir ]
            in
            assert_int_equal 0 archived.status
              "source archive generation should succeed before manifest reuse";
            let generated =
              Process.run_capture ~cwd:repo_root manifest_script
                [
                  "--output-dir";
                  output_dir;
                  "--source-archive";
                  Filename.concat archive_dir "wadi-0.1.0-source.tar.gz";
                  "--checksums-output";
                  Filename.concat output_dir "SHA256SUMS";
                  "--asset-index-output";
                  Filename.concat output_dir
                    (release_asset_index_name ~cwd:repo_root);
                ]
            in
            assert_int_equal 0 generated.status
              "packaging manifest generation should reuse explicit source archives";
            assert_string_equal
              (Fs.read_file (Filename.concat output_dir "wadi.opam"))
              (Fs.read_file (Filename.concat repo_root "wadi.opam"))
              "explicit-archive manifest generation should still render wadi.opam from shared metadata";
            assert_string_equal
              (Fs.read_file (Filename.concat output_dir "Formula/wadi.rb"))
              (Fs.read_file (Filename.concat repo_root "Formula/wadi.rb"))
              "explicit-archive manifest generation should match the committed Homebrew formula";
            let explicit_archive =
              Filename.concat archive_dir "wadi-0.1.0-source.tar.gz"
            in
            let checksums = Fs.read_file (Filename.concat output_dir "SHA256SUMS") in
            assert_string_contains ~needle:explicit_archive checksums
              "explicit source archives should be included in checksum manifests even when they live outside the output dir";
            let asset_index =
              Fs.read_file
                (Filename.concat output_dir
                   (release_asset_index_name ~cwd:repo_root))
            in
            let base_url = release_download_base_url ~cwd:repo_root in
            assert_string_contains
              ~needle:
                (render_asset_index_entry ~base_url
                   ~name:(Filename.basename explicit_archive)
                   ~kind:"source_archive"
                   ~sha256:(sha256_for_file explicit_archive)
                   ~size_bytes:(Unix.stat explicit_archive).Unix.st_size ())
              asset_index
              "explicit source archives should be represented in the asset index"));
    ( "can emit flat release assets and checksums from the packaging generator",
      fun () ->
        let repo_root = Sys.getcwd () in
        let manifest_script =
          Filename.concat repo_root "scripts/generate_packaging_manifests.sh"
        in
        let archive_script =
          Filename.concat repo_root "scripts/build_release_archives.sh"
        in
        with_temp_dir "wadi-packaging-release-assets" (fun output_dir ->
            let source_run =
              Process.run_capture ~cwd:repo_root archive_script
                [ "--source-only"; "--output-dir"; output_dir ]
            in
            assert_int_equal 0 source_run.status
              "source archive generation should succeed before release-asset packaging";
            let binary_run =
              Process.run_capture ~cwd:repo_root
                ~env:[ ("WADI_BIN", wadi_bin ()) ]
                archive_script
                [
                  "--binary-only";
                  "--output-dir";
                  output_dir;
                  "--binary";
                  wadi_bin ();
                  "--os";
                  "linux";
                  "--arch";
                  "x86_64";
                ]
            in
            assert_int_equal 0 binary_run.status
              "binary archive generation should succeed before release-asset packaging";
            let generated =
              Process.run_capture ~cwd:repo_root manifest_script
                [
                  "--output-dir";
                  output_dir;
                  "--reuse-source-archive-dir";
                  output_dir;
                  "--formula-output";
                  Filename.concat output_dir "wadi.rb";
                  "--checksums-output";
                  Filename.concat output_dir "SHA256SUMS";
                  "--asset-index-output";
                  Filename.concat output_dir
                    (release_asset_index_name ~cwd:repo_root);
                ]
            in
            assert_int_equal 0 generated.status
              "packaging manifest generation should emit flat release assets";
            assert_file_exists (Filename.concat output_dir "wadi.opam");
            assert_file_exists (Filename.concat output_dir "wadi.rb");
            assert_file_exists (Filename.concat output_dir "SHA256SUMS");
            let asset_index_path =
              Filename.concat output_dir
                (release_asset_index_name ~cwd:repo_root)
            in
            assert_file_exists asset_index_path;
            assert_string_equal
              (Fs.read_file (Filename.concat output_dir "wadi.rb"))
              (Fs.read_file (Filename.concat repo_root "Formula/wadi.rb"))
              "flat release-asset manifest generation should match the committed Homebrew formula";
            let checksums = Fs.read_file (Filename.concat output_dir "SHA256SUMS") in
            assert_string_contains
              ~needle:(Filename.concat output_dir "wadi-0.1.0-source.tar.gz")
              checksums
              "release checksum output should include the source archive";
            assert_string_contains
              ~needle:(Filename.concat output_dir "wadi-0.1.0-x86_64-linux.tar.gz")
              checksums
              "release checksum output should include downloaded binary archives";
            assert_string_contains
              ~needle:(Filename.concat output_dir "wadi.opam")
              checksums
              "release checksum output should include the published opam metadata";
            assert_string_contains
              ~needle:(Filename.concat output_dir "wadi.rb")
              checksums
              "release checksum output should include the published formula metadata";
            let base_url = release_download_base_url ~cwd:repo_root in
            let asset_index = Fs.read_file asset_index_path in
            assert_string_contains ~needle:"\"schema_version\": 1" asset_index
              "release asset index should declare its schema version";
            assert_string_not_contains ~needle:output_dir asset_index
              "release asset index should not leak local build paths";
            let source_archive =
              Filename.concat output_dir "wadi-0.1.0-source.tar.gz"
            in
            let binary_archive =
              Filename.concat output_dir "wadi-0.1.0-x86_64-linux.tar.gz"
            in
            let opam_asset = Filename.concat output_dir "wadi.opam" in
            let formula_asset = Filename.concat output_dir "wadi.rb" in
            let checksums_asset = Filename.concat output_dir "SHA256SUMS" in
            assert_string_contains
              ~needle:
                (render_asset_index_entry ~base_url
                   ~name:(Filename.basename source_archive)
                   ~kind:"source_archive"
                   ~sha256:(sha256_for_file source_archive)
                   ~size_bytes:(Unix.stat source_archive).Unix.st_size ())
              asset_index
              "release asset index should describe the source archive";
            assert_string_contains
              ~needle:
                (render_asset_index_entry ~base_url
                   ~name:(Filename.basename binary_archive)
                   ~kind:"binary_archive" ~os:"linux" ~arch:"x86_64"
                   ~sha256:(sha256_for_file binary_archive)
                   ~size_bytes:(Unix.stat binary_archive).Unix.st_size ())
              asset_index
              "release asset index should describe binary archives";
            assert_string_contains
              ~needle:
                (render_asset_index_entry ~base_url
                   ~name:(Filename.basename opam_asset)
                   ~kind:"opam_metadata"
                   ~sha256:(sha256_for_file opam_asset)
                   ~size_bytes:(Unix.stat opam_asset).Unix.st_size ())
              asset_index
              "release asset index should describe the opam metadata asset";
            assert_string_contains
              ~needle:
                (render_asset_index_entry ~base_url
                   ~name:(Filename.basename formula_asset)
                   ~kind:"homebrew_formula"
                   ~sha256:(sha256_for_file formula_asset)
                   ~size_bytes:(Unix.stat formula_asset).Unix.st_size ())
              asset_index
              "release asset index should describe the Homebrew formula asset";
            assert_string_contains
              ~needle:
                (render_asset_index_entry ~base_url
                   ~name:(Filename.basename checksums_asset)
                   ~kind:"checksums"
                   ~sha256:(sha256_for_file checksums_asset)
                   ~size_bytes:(Unix.stat checksums_asset).Unix.st_size ())
              asset_index
              "release asset index should describe the checksum manifest"));
    ( "release workflow publishes the generated asset index alongside checksums and metadata",
      fun () ->
        let repo_root = Sys.getcwd () in
        let workflow =
          Fs.read_file (Filename.concat repo_root ".github/workflows/release.yml")
        in
        assert_string_contains ~needle:"--opam-output dist/wadi.opam" workflow
          "release publishing should render the opam metadata into the release asset layout";
        assert_string_contains
          ~needle:"--asset-index-output dist/release-assets.json" workflow
          "release publishing should render the release asset index into the release asset layout";
        assert_string_contains ~needle:"diff -u wadi.opam dist/wadi.opam" workflow
          "release publishing should verify the generated opam asset against the committed package metadata";
        assert_string_contains ~needle:"dist/wadi.opam" workflow
          "release publishing should upload the generated opam asset";
        assert_string_contains ~needle:"dist/release-assets.json" workflow
          "release publishing should upload the generated asset index");
    ( "release-manifests refreshes a local source archive alongside packaging manifests",
      fun () ->
        let repo_root = Sys.getcwd () in
        with_temp_dir "wadi-release-manifests" (fun workspace ->
            copy_tracked_repo ~src_root:repo_root ~dst_root:workspace ();
            let init = Process.run_capture ~cwd:workspace "git" [ "init"; "-q" ] in
            assert_int_equal 0 init.status
              ("git init should succeed before release-manifests\n" ^ init.output);
            let add = Process.run_capture ~cwd:workspace "git" [ "add"; "." ] in
            assert_int_equal 0 add.status
              ("git add should succeed before release-manifests\n" ^ add.output);
            List.iter
              (fun relative_path ->
                let path = Filename.concat workspace relative_path in
                if Fs.exists path then Sys.remove path)
              [ "wadi.opam"; "Formula/wadi.rb" ];
            let dist_dir = Filename.concat workspace "dist" in
            if Fs.exists dist_dir then Fs.remove_tree dist_dir;
            let generated = run_make ~cwd:workspace [ "release-manifests" ] in
            assert_int_equal 0 generated.status
              ("make release-manifests should succeed\n" ^ generated.output);
            assert_true
              (not (Fs.exists (Filename.concat workspace "_bootstrap")))
              "make release-manifests should not detour through bootstrap generation";
            assert_file_exists (Filename.concat workspace "wadi.opam");
            assert_file_exists (Filename.concat workspace "Formula/wadi.rb");
            assert_file_exists (Filename.concat workspace "dist/release-assets.json");
            assert_file_exists
              (Filename.concat workspace "dist/wadi-0.1.0-source.tar.gz")));
    ( "make release-manifests self-hosts from a clean checkout",
      fun () ->
        let repo_root = Sys.getcwd () in
        with_temp_dir "wadi-release-manifests-self-host" (fun workspace ->
            copy_tracked_repo ~src_root:repo_root ~dst_root:workspace ();
            let init = Process.run_capture ~cwd:workspace "git" [ "init"; "-q" ] in
            assert_int_equal 0 init.status
              ("git init should succeed before self-hosted release-manifests\n"
             ^ init.output);
            let add = Process.run_capture ~cwd:workspace "git" [ "add"; "." ] in
            assert_int_equal 0 add.status
              ("git add should succeed before self-hosted release-manifests\n"
             ^ add.output);
            let dist_dir = Filename.concat workspace "dist" in
            if Fs.exists dist_dir then Fs.remove_tree dist_dir;
            let generated =
              run_make ~use_wadi_bin:false ~cwd:workspace [ "release-manifests" ]
            in
            assert_int_equal 0 generated.status
              ("make release-manifests should self-host successfully\n"
             ^ generated.output);
            assert_file_exists (Filename.concat workspace "_bootstrap/bin/wadi");
            assert_file_exists (Filename.concat workspace "wadi.opam");
            assert_file_exists (Filename.concat workspace "Formula/wadi.rb");
            assert_file_exists (Filename.concat workspace "dist/release-assets.json");
            assert_file_exists
              (Filename.concat workspace "dist/wadi-0.1.0-source.tar.gz")));
    ( "sync-generated refreshes bootstrap metadata and release artifacts in one pass",
      fun () ->
        let repo_root = Sys.getcwd () in
        with_temp_dir "wadi-sync-generated" (fun workspace ->
            copy_tracked_repo ~src_root:repo_root ~dst_root:workspace ();
            let init = Process.run_capture ~cwd:workspace "git" [ "init"; "-q" ] in
            assert_int_equal 0 init.status
              ("git init should succeed before sync-generated\n" ^ init.output);
            let add = Process.run_capture ~cwd:workspace "git" [ "add"; "." ] in
            assert_int_equal 0 add.status
              ("git add should succeed before sync-generated\n" ^ add.output);
            List.iter
              (fun relative_path ->
                let path = Filename.concat workspace relative_path in
                if Fs.exists path then Sys.remove path)
              [
                "docs/cli.md";
                "completions/wadi.bash";
                "completions/_wadi";
                "completions/wadi.fish";
                "wadi.opam";
                "Formula/wadi.rb";
              ];
            List.iter
              (fun relative_path ->
                let path = Filename.concat workspace relative_path in
                if Fs.exists path then Fs.remove_tree path)
              [ "package"; "_bootstrap" ];
            let synced = run_make ~cwd:workspace [ "sync-generated" ] in
            assert_int_equal 0 synced.status
              ("make sync-generated should succeed\n" ^ synced.output);
            assert_file_exists
              (Filename.concat workspace "_bootstrap/bootstrap.seed-metadata.mk");
            assert_file_exists (Filename.concat workspace "docs/cli.md");
            assert_file_exists (Filename.concat workspace "completions/wadi.bash");
            assert_file_exists (Filename.concat workspace "completions/_wadi");
            assert_file_exists (Filename.concat workspace "completions/wadi.fish");
            assert_file_exists (Filename.concat workspace "wadi.opam");
            assert_file_exists (Filename.concat workspace "Formula/wadi.rb");
            assert_file_exists (Filename.concat workspace "dist/release-assets.json");
            assert_file_exists
              (Filename.concat workspace "dist/wadi-0.1.0-source.tar.gz");
            assert_file_exists
              (Filename.concat workspace "package/share/doc/wadi/cli.md");
            assert_file_exists
              (Filename.concat workspace
                 "package/share/bash-completion/completions/wadi");
            assert_file_exists
              (Filename.concat workspace
                 "package/share/zsh/site-functions/_wadi");
            assert_file_exists
              (Filename.concat workspace
                 "package/share/fish/vendor_completions.d/wadi.fish");
            assert_string_equal
              (Fs.read_file (Filename.concat workspace "docs/cli.md"))
              (Fs.read_file
                 (Filename.concat workspace "package/share/doc/wadi/cli.md"))
              "sync-generated should keep the packaged doc copy aligned with wadi docs")) ;
    ( "builds deterministic source and binary release archives",
      fun () ->
        let repo_root = Sys.getcwd () in
        let archive_script =
          Filename.concat repo_root "scripts/build_release_archives.sh"
        in
        with_temp_dir "wadi-packaging-archives" (fun output_dir ->
            let source_run =
              Process.run_capture ~cwd:repo_root archive_script
                [ "--source-only"; "--output-dir"; output_dir ]
            in
            assert_int_equal 0 source_run.status
              "source archive generation should succeed";
            assert_string_not_contains ~needle:"setlocale" source_run.output
              "source archive generation should not leak shell locale warnings";
            let binary_run =
              Process.run_capture ~cwd:repo_root
                ~env:[ ("WADI_BIN", wadi_bin ()) ]
                archive_script
                [
                  "--binary-only";
                  "--output-dir";
                  output_dir;
                  "--binary";
                  wadi_bin ();
                  "--os";
                  "macos";
                  "--arch";
                  "arm64";
                ]
            in
            assert_int_equal 0 binary_run.status
              "binary archive generation should succeed";
            assert_string_not_contains ~needle:"setlocale" binary_run.output
              "binary archive generation should not leak shell locale warnings";
            assert_file_exists
              (Filename.concat output_dir "wadi-0.1.0-source.tar.gz");
            assert_file_exists
              (Filename.concat output_dir "wadi-0.1.0-arm64-macos.tar.gz");
            let listing =
              Process.run_capture ~cwd:output_dir "tar"
                [ "-tzf"; "wadi-0.1.0-arm64-macos.tar.gz" ]
            in
            assert_int_equal 0 listing.status
              "binary archives should be valid tarballs";
            let binary_entries = nonempty_lines listing.output in
            assert_int_equal (List.length binary_entries)
              (List.length (String_util.dedup_preserve binary_entries))
              "binary release archives should not contain duplicate tar entries";
            assert_string_contains ~needle:"wadi-0.1.0-arm64-macos/bin/wadi\n"
              listing.output
              "binary release archives should stage the wadi binary";
            assert_string_contains
              ~needle:"wadi-0.1.0-arm64-macos/share/doc/wadi/cli.md\n"
              listing.output
              "binary release archives should stage packaged docs";
            let source_listing =
              Process.run_capture ~cwd:output_dir "tar"
                [ "-tzf"; "wadi-0.1.0-source.tar.gz" ]
            in
            assert_int_equal 0 source_listing.status
              "source archives should be valid tarballs";
            let source_entries = nonempty_lines source_listing.output in
            assert_int_equal (List.length source_entries)
              (List.length (String_util.dedup_preserve source_entries))
              "source release archives should not contain duplicate tar entries";
            assert_string_contains ~needle:"wadi-0.1.0/LICENSE\n"
              source_listing.output
              "source release archives should include the license text";
            assert_string_contains ~needle:"wadi-0.1.0/release/metadata.sh\n"
              source_listing.output
              "source release archives should include the canonical release metadata";
            with_temp_dir "wadi-packaging-source-extract" (fun extract_dir ->
                let unpacked =
                  Process.run_capture ~cwd:extract_dir "tar"
                    [ "-xzf"; Filename.concat output_dir "wadi-0.1.0-source.tar.gz" ]
                in
                assert_int_equal 0 unpacked.status
                  ("source archive extraction should succeed\n" ^ unpacked.output);
                let install_script =
                  Filename.concat extract_dir
                    "wadi-0.1.0/scripts/install_release_tree.sh"
                in
                let release_artifacts_script =
                  Filename.concat extract_dir
                    "wadi-0.1.0/scripts/generate_release_artifacts.sh"
                in
                let release_locale_script =
                  Filename.concat extract_dir
                    "wadi-0.1.0/scripts/release_locale.sh"
                in
                assert_file_exists release_locale_script;
                assert_true
                  (((Unix.stat install_script).Unix.st_perm land 0o111) <> 0)
                  "the source archive should preserve execute bits for install_release_tree.sh";
                assert_true
                  (((Unix.stat release_artifacts_script).Unix.st_perm land 0o111) <> 0)
                  "the source archive should preserve execute bits for generate_release_artifacts.sh")));
    ( "binary archive generation self-hosts from a clean checkout when no binary is supplied",
      fun () ->
        let repo_root = Sys.getcwd () in
        with_temp_dir "wadi-packaging-binary-self-host" (fun workspace ->
            copy_tracked_repo ~src_root:repo_root ~dst_root:workspace ();
            let init = Process.run_capture ~cwd:workspace "git" [ "init"; "-q" ] in
            assert_int_equal 0 init.status
              ("git init should succeed before self-hosted binary archives\n"
             ^ init.output);
            let add = Process.run_capture ~cwd:workspace "git" [ "add"; "." ] in
            assert_int_equal 0 add.status
              ("git add should succeed before self-hosted binary archives\n"
             ^ add.output);
            let archive_script =
              Filename.concat workspace "scripts/build_release_archives.sh"
            in
            let output_dir = Filename.concat workspace "dist" in
            let generated =
              Process.run_capture ~cwd:workspace "env"
                [
                  "-u";
                  "WADI_BIN";
                  archive_script;
                  "--binary-only";
                  "--output-dir";
                  output_dir;
                  "--os";
                  "linux";
                  "--arch";
                  "x86_64";
                ]
            in
            assert_int_equal 0 generated.status
              ("binary archive generation should self-host from a clean checkout\n"
             ^ generated.output);
            assert_file_exists (Filename.concat workspace "_bootstrap/bin/wadi");
            assert_file_exists
              (Filename.concat output_dir "wadi-0.1.0-x86_64-linux.tar.gz")));
    ( "keeps package-manager definitions aligned with the shared release install script",
      (fun () ->
        let repo_root = Sys.getcwd () in
        let opam = Fs.read_file (Filename.concat repo_root "wadi.opam") in
        let flake = Fs.read_file (Filename.concat repo_root "flake.nix") in
        let formula =
          Fs.read_file (Filename.concat repo_root "Formula/wadi.rb")
        in
        let makefile = Fs.read_file (Filename.concat repo_root "Makefile") in
        assert_string_contains ~needle:"[make \"release-artifacts\"]" opam
          "the opam package should build through the canonical release-artifact target";
        assert_string_contains ~needle:"scripts/install_release_tree.sh" opam
          "the opam package should install through the shared release-tree installer";
        assert_string_not_contains
          ~needle:"\"bash\"\n    \"scripts/install_release_tree.sh\""
          opam
          "the opam package should execute the shared installer directly instead of forcing bash";
        assert_string_contains ~needle:"make release-artifacts" flake
          "the Nix flake should build through the canonical release-artifact target";
        assert_string_contains ~needle:"scripts/install_release_tree.sh" flake
          "the Nix flake should install through the shared release-tree installer";
        assert_string_contains ~needle:"system \"make\", \"release-artifacts\""
          formula
          "the Homebrew formula should build through the canonical release-artifact target";
        assert_string_contains ~needle:"scripts/install_release_tree.sh" formula
          "the Homebrew formula should install through the shared release-tree installer";
        assert_string_not_contains
          ~needle:"system \"bash\", \"scripts/install_release_tree.sh\","
          formula
          "the Homebrew formula should execute the shared installer directly instead of forcing bash";
        assert_string_contains
          ~needle:"./scripts/generate_packaging_manifests.sh"
          makefile
          "the Makefile should execute the packaging manifest script directly";
        assert_string_not_contains
          ~needle:"bash scripts/generate_packaging_manifests.sh"
          makefile
          "the Makefile should not force bash for packaging manifests";
        assert_string_contains
          ~needle:"./scripts/update_homebrew_tap.sh"
          makefile
          "the Makefile should execute the Homebrew tap updater directly";
        assert_string_not_contains
          ~needle:"bash scripts/update_homebrew_tap.sh"
          makefile
          "the Makefile should not force bash for Homebrew tap updates")) ;
    ( "falls back to the C archive locale when UTF-8 C locales are unavailable",
      fun () ->
        let repo_root = Sys.getcwd () in
        let archive_script =
          Filename.concat repo_root "scripts/build_release_archives.sh"
        in
        let tar_path =
          let resolved =
            Process.run_capture ~cwd:repo_root "sh" [ "-c"; "command -v tar" ]
          in
          assert_int_equal 0 resolved.status
            ("command -v tar should succeed\n" ^ resolved.output);
          String.trim resolved.output
        in
        let path_env =
          match Sys.getenv_opt "PATH" with
          | Some value -> value
          | None -> "/usr/bin:/bin:/usr/sbin:/sbin"
        in
        with_temp_dir "wadi-packaging-locale" (fun workspace ->
            let bin_dir = Filename.concat workspace "bin" in
            Fs.ensure_dir bin_dir;
            let fake_locale = Filename.concat bin_dir "locale" in
            Fs.write_file fake_locale
              "#!/bin/sh\n\
               if [ \"$1\" = \"-a\" ]; then\n\
               \  printf 'C\\nPOSIX\\n'\n\
               else\n\
               \  exec /usr/bin/locale \"$@\"\n\
               fi\n";
            chmod_plus_x fake_locale;
            let fake_tar = Filename.concat bin_dir "tar" in
            Fs.write_file fake_tar
              (Printf.sprintf
                 "#!/bin/sh\n\
                  if [ \"${LC_ALL:-}\" != \"C\" ]; then\n\
                  \  echo \"unexpected archive locale: ${LC_ALL:-}\" >&2\n\
                  \  exit 19\n\
                  fi\n\
                  exec %s \"$@\"\n"
                 (Filename.quote tar_path));
            chmod_plus_x fake_tar;
            let output_dir = Filename.concat workspace "dist" in
            let run =
              Process.run_capture ~cwd:repo_root
                ~env:[ ("PATH", bin_dir ^ ":" ^ path_env) ]
                archive_script [ "--source-only"; "--output-dir"; output_dir ]
            in
            assert_int_equal 0 run.status
              ("archive generation should succeed with a C fallback locale\n"
             ^ run.output);
            assert_file_exists
              (Filename.concat output_dir "wadi-0.1.0-source.tar.gz");
            assert_string_not_contains ~needle:"unexpected archive locale"
              run.output
              "archive generation should fall back to LC_ALL=C when UTF-8 C locales are unavailable")) ;
    ( "keeps the Homebrew formula syntax-valid",
      fun () ->
        let repo_root = Sys.getcwd () in
        let check =
          Process.run_capture ~cwd:repo_root "ruby"
            [ "-c"; "Formula/wadi.rb" ]
        in
        assert_int_equal 0 check.status
          ("Formula/wadi.rb should stay valid Ruby\n" ^ check.output));
    ( "keeps wadi.opam valid under opam lint",
      fun () ->
        let repo_root = Sys.getcwd () in
        let lint =
          Process.run_capture ~cwd:repo_root "opam" [ "lint"; "wadi.opam" ]
        in
        assert_int_equal 0 lint.status
          ("wadi.opam should stay valid under opam lint\n" ^ lint.output));
    ( "updates a dedicated Homebrew tap checkout from the generated formula",
      fun () ->
        let repo_root = Sys.getcwd () in
        let update_script =
          Filename.concat repo_root "scripts/update_homebrew_tap.sh"
        in
        let formula = Fs.read_file (Filename.concat repo_root "Formula/wadi.rb") in
        with_temp_dir "wadi-packaging-tap" (fun workspace ->
            let tap_dir = Filename.concat workspace "homebrew-wadi" in
            Fs.ensure_dir tap_dir;
            let init = Process.run_capture ~cwd:tap_dir "git" [ "init" ] in
            assert_int_equal 0 init.status
              ("tap git init should succeed\n" ^ init.output);
            let updated =
              Process.run_capture ~cwd:repo_root update_script
                [ "--tap-dir"; tap_dir; "--formula"; Filename.concat repo_root "Formula/wadi.rb"; "--commit" ]
            in
            assert_int_equal 0 updated.status
              ("Homebrew tap update should succeed\n" ^ updated.output);
            assert_string_not_contains ~needle:"setlocale" updated.output
              "the Homebrew tap updater should not leak shell locale warnings";
            assert_string_equal formula
              (Fs.read_file (Filename.concat tap_dir "Formula/wadi.rb"))
              "the tap update flow should copy the generated formula into the tap checkout";
            let log =
              Process.run_capture ~cwd:tap_dir "git"
                [ "log"; "-1"; "--pretty=%s" ]
            in
            assert_int_equal 0 log.status
              ("tap git log should succeed\n" ^ log.output);
            assert_string_contains ~needle:"wadi v0.1.0" log.output
              "the tap update flow should commit the rendered formula with the release tag in the message"));
    ( "update-homebrew-tap updates a dedicated tap checkout from the CLI",
      fun () ->
        let repo_root = Sys.getcwd () in
        let formula = Fs.read_file (Filename.concat repo_root "Formula/wadi.rb") in
        with_temp_dir "wadi-packaging-tap-command" (fun workspace ->
            let tap_dir = Filename.concat workspace "homebrew-wadi" in
            Fs.ensure_dir tap_dir;
            let init = Process.run_capture ~cwd:tap_dir "git" [ "init" ] in
            assert_int_equal 0 init.status
              ("tap git init should succeed\n" ^ init.output);
            let updated =
              run_wadi ~cwd:repo_root
                [
                  "update-homebrew-tap";
                  "--tap-dir";
                  tap_dir;
                  "--formula";
                  Filename.concat repo_root "Formula/wadi.rb";
                  "--commit";
                ]
            in
            assert_int_equal 0 updated.status
              ("wadi update-homebrew-tap should succeed\n" ^ updated.output);
            assert_string_equal formula
              (Fs.read_file (Filename.concat tap_dir "Formula/wadi.rb"))
              "the CLI tap updater should copy the generated formula into the tap checkout";
            let log =
              Process.run_capture ~cwd:tap_dir "git"
                [ "log"; "-1"; "--pretty=%s" ]
            in
            assert_int_equal 0 log.status
              ("tap git log should succeed\n" ^ log.output);
            assert_string_contains ~needle:"wadi v0.1.0" log.output
              "the CLI tap updater should commit the rendered formula with the release tag in the message"));
    ( "clones the Homebrew tap from release metadata when no local checkout exists",
      fun () ->
        let repo_root = Sys.getcwd () in
        with_temp_dir "wadi-packaging-tap-clone" (fun workspace ->
            copy_tracked_repo ~src_root:repo_root ~dst_root:workspace ();
            let remote_dir = Filename.concat workspace "tap-remote.git" in
            let remote_init =
              Process.run_capture ~cwd:workspace "git"
                [ "init"; "--bare"; remote_dir ]
            in
            assert_int_equal 0 remote_init.status
              ("bare git init should succeed for the tap remote\n"
             ^ remote_init.output);
            set_shell_binding (Filename.concat workspace "release/metadata.sh")
              ~name:"WADI_HOMEBREW_TAP_REMOTE_URL" ~value:remote_dir;
            let update_script =
              Filename.concat workspace "scripts/update_homebrew_tap.sh"
            in
            let tap_dir = Filename.concat workspace "homebrew-wadi" in
            let updated =
              Process.run_capture ~cwd:workspace
                ~env:[ ("WADI_BIN", wadi_bin ()) ]
                update_script
                [ "--tap-dir"; tap_dir; "--formula"; Filename.concat workspace "Formula/wadi.rb"; "--commit" ]
            in
            assert_int_equal 0 updated.status
              ("tap updater should clone and update the remote checkout\n"
             ^ updated.output);
            assert_string_not_contains ~needle:"setlocale" updated.output
              "the cloned tap updater should not leak shell locale warnings";
            assert_file_exists (Filename.concat tap_dir "Formula/wadi.rb");
            let origin =
              Process.run_capture ~cwd:tap_dir "git"
                [ "remote"; "get-url"; "origin" ]
            in
            assert_int_equal 0 origin.status
              ("git remote get-url origin should succeed\n" ^ origin.output);
            assert_string_equal remote_dir (String.trim origin.output)
              "the tap updater should clone from the metadata-defined remote";
            let log =
              Process.run_capture ~cwd:tap_dir "git"
                [ "log"; "-1"; "--pretty=%s" ]
            in
            assert_int_equal 0 log.status
              ("git log should succeed in the cloned tap checkout\n" ^ log.output);
            assert_string_contains ~needle:"wadi v0.1.0" log.output
              "the cloned tap checkout should receive the rendered formula commit"));
    ( "cuts a release version, refreshes packaging manifests, and creates the matching tag",
      fun () ->
        let repo_root = Sys.getcwd () in
        with_temp_dir "wadi-packaging-cut" (fun workspace ->
            copy_tracked_repo ~src_root:repo_root ~dst_root:workspace
              ~extra_paths:
                [
                  "scripts/cut_release.sh";
                  "scripts/update_homebrew_tap.sh";
                  "scripts/release_locale.sh";
                ]
              ();
            let cut_script = Filename.concat workspace "scripts/cut_release.sh" in
            let init = Process.run_capture ~cwd:workspace "git" [ "init" ] in
            assert_int_equal 0 init.status
              ("git init should succeed in the release-cut sandbox\n" ^ init.output);
            let add = Process.run_capture ~cwd:workspace "git" [ "add"; "." ] in
            assert_int_equal 0 add.status
              ("git add should succeed in the release-cut sandbox\n" ^ add.output);
            let commit =
              Process.run_capture ~cwd:workspace "git"
                [
                  "-c";
                  "user.name=Test";
                  "-c";
                  "user.email=test@example.com";
                  "commit";
                  "-m";
                  "initial";
                ]
            in
            assert_int_equal 0 commit.status
              ("git commit should succeed in the release-cut sandbox\n"
             ^ commit.output);
            let cut =
              Process.run_capture ~cwd:workspace
                ~env:[ ("WADI_BIN", wadi_bin ()) ]
                cut_script
                [ "--version"; "0.1.1"; "--tag" ]
            in
            assert_int_equal 0 cut.status
              ("release-cut should succeed\n" ^ cut.output);
            assert_string_not_contains ~needle:"setlocale" cut.output
              "release-cut should not leak shell locale warnings";
            assert_string_contains ~needle:"dist/wadi-0.1.1-source.tar.gz"
              cut.output
              "release-cut should report the refreshed local source archive";
            let metadata =
              Fs.read_file (Filename.concat workspace "release/metadata.sh")
            in
            let formula =
              Fs.read_file (Filename.concat workspace "Formula/wadi.rb")
            in
            assert_string_contains ~needle:"WADI_RELEASE_VERSION='0.1.1'"
              metadata
              "release-cut should bump the canonical release metadata version";
            assert_string_contains
              ~needle:"/releases/download/v0.1.1/wadi-0.1.1-source.tar.gz"
              formula
              "release-cut should refresh the Homebrew formula from the new source archive";
            assert_file_exists
              (Filename.concat workspace "dist/wadi-0.1.1-source.tar.gz");
            assert_file_exists
              (Filename.concat workspace "dist/release-assets.json");
            let tags =
              Process.run_capture ~cwd:workspace "git" [ "tag"; "--list" ]
            in
            assert_int_equal 0 tags.status
              ("git tag --list should succeed after release-cut\n" ^ tags.output);
            assert_string_contains ~needle:"v0.1.1\n" tags.output
              "release-cut should create the matching release tag when requested"));
    ( "release-cut refreshes packaging metadata and tags the copied repo from the CLI",
      fun () ->
        let repo_root = Sys.getcwd () in
        with_temp_dir "wadi-packaging-cut-command" (fun workspace ->
            copy_tracked_repo ~src_root:repo_root ~dst_root:workspace ();
            let init = Process.run_capture ~cwd:workspace "git" [ "init" ] in
            assert_int_equal 0 init.status
              ("git init should succeed in the release-cut sandbox\n" ^ init.output);
            let add = Process.run_capture ~cwd:workspace "git" [ "add"; "." ] in
            assert_int_equal 0 add.status
              ("git add should succeed in the release-cut sandbox\n" ^ add.output);
            let commit =
              Process.run_capture ~cwd:workspace "git"
                [
                  "-c";
                  "user.name=Test";
                  "-c";
                  "user.email=test@example.com";
                  "commit";
                  "-m";
                  "initial";
                ]
            in
            assert_int_equal 0 commit.status
              ("git commit should succeed in the release-cut sandbox\n"
             ^ commit.output);
            let cut =
              run_wadi ~cwd:workspace
                [ "release-cut"; "--version"; "0.1.1"; "--tag" ]
            in
            assert_int_equal 0 cut.status
              ("wadi release-cut should succeed\n" ^ cut.output);
            assert_string_contains ~needle:"dist/wadi-0.1.1-source.tar.gz"
              cut.output
              "release-cut should report the refreshed local source archive";
            assert_file_exists
              (Filename.concat workspace "dist/wadi-0.1.1-source.tar.gz");
            let tags =
              Process.run_capture ~cwd:workspace "git" [ "tag"; "--list" ]
            in
            assert_int_equal 0 tags.status
              ("git tag --list should succeed after release-cut\n" ^ tags.output);
            assert_string_contains ~needle:"v0.1.1\n" tags.output
              "release-cut should create the matching release tag when requested"));
    ( "keeps the release workflow aligned with the release metadata and formula",
      fun () ->
        let repo_root = Sys.getcwd () in
        let workflow =
          Fs.read_file
            (Filename.concat repo_root ".github/workflows/release.yml")
        in
        assert_string_contains
          ~needle:"./scripts/build_release_archives.sh --source-only --output-dir dist --source-archive-mode tracked"
          workflow
          "the release workflow should publish a deterministic source archive";
        assert_string_contains
          ~needle:"./scripts/generate_packaging_manifests.sh"
          workflow
          "the release workflow should render packaging manifests through the shared generator";
        assert_string_contains ~needle:"--reuse-source-archive-dir dist" workflow
          "the release workflow should reuse the downloaded source archive through the packaging generator";
        assert_string_contains ~needle:"--formula-output dist/wadi.rb" workflow
          "the release workflow should emit a flat Homebrew formula asset for GitHub releases";
        assert_string_contains ~needle:"--checksums-output dist/SHA256SUMS" workflow
          "the release workflow should generate archive checksums through the shared packaging generator";
        assert_string_contains
          ~needle:"--asset-index-output dist/release-assets.json" workflow
          "the release workflow should generate a machine-readable asset index through the shared packaging generator";
        assert_string_contains
          ~needle:"./scripts/update_homebrew_tap.sh"
          workflow
          "the release workflow should publish the rendered formula through the dedicated tap update flow";
        assert_string_not_contains
          ~needle:"bash scripts/build_release_archives.sh"
          workflow
          "the release workflow should execute archive scripts directly instead of forcing bash";
        assert_string_not_contains ~needle:"sha256sum dist/*.tar.gz" workflow
          "the release workflow should not maintain a second checksum path outside the packaging generator";
        assert_string_contains
          ~needle:"repository: ${{ steps.metadata.outputs.tap_repo }}"
          workflow
          "the release workflow should check out the dedicated tap repository before pushing formula updates";
        assert_string_contains ~needle:"softprops/action-gh-release@v2" workflow
          "the release workflow should publish the generated release assets";
        assert_string_contains ~needle:"dist/release-assets.json" workflow
          "the release workflow should publish the machine-readable asset index");
  ]
