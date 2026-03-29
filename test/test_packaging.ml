open Test_support

let nonempty_lines text =
  text |> String.split_on_char '\n' |> List.filter (fun line -> line <> "")

let copy_tracked_repo ~src_root ~dst_root ?(extra_paths = []) () =
  let listed = Process.run_capture ~cwd:src_root "git" [ "ls-files" ] in
  assert_int_equal 0 listed.status
    ("git ls-files should succeed before copying a tracked repo\n" ^ listed.output);
  let paths = nonempty_lines listed.output @ extra_paths |> String_util.dedup_preserve in
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

let run_make ~cwd goals =
  Process.run_capture ~cwd
    ~env:
      [
        ("MAKEFLAGS", "");
        ("MFLAGS", "");
        ("MAKELEVEL", "0");
        ("OCAMLOPT", "ocamlopt");
        ("OCAMLFIND", "ocamlfind");
        ("OCAMLFLAGS", "-g");
      ]
    "make" goals

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
        with_temp_dir "oasis-packaging-release" (fun output_dir ->
            with_temp_dir "oasis-packaging-prefix" (fun prefix ->
                let generated =
                  Process.run_capture ~cwd:repo_root
                    ~env:[ ("OASIS_BIN", oasis_bin ()) ]
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
                      oasis_bin ();
                      "--prefix";
                      prefix;
                    ]
                in
                assert_int_equal 0 installed.status
                  "install_release_tree.sh should stage the release tree";
                assert_file_exists (Filename.concat prefix "bin/oasis");
                assert_file_exists
                  (Filename.concat prefix "share/doc/oasis/cli.md");
                assert_file_exists
                  (Filename.concat prefix
                     "share/bash-completion/completions/oasis");
                assert_file_exists
                  (Filename.concat prefix "share/zsh/site-functions/_oasis");
                assert_file_exists
                  (Filename.concat prefix
                     "share/fish/vendor_completions.d/oasis.fish");
                let installed_docs =
                  run_binary (Filename.concat prefix "bin/oasis") [ "docs" ]
                in
                assert_int_equal 0 installed_docs.status
                  "the installed oasis binary should remain runnable";
                assert_string_equal installed_docs.output
                  (Fs.read_file
                     (Filename.concat prefix "share/doc/oasis/cli.md"))
                  "the installed doc copy should come from the installed binary"))) );
    ( "generates packaging manifests from the canonical release metadata",
      fun () ->
        let repo_root = Sys.getcwd () in
        let manifest_script =
          Filename.concat repo_root "scripts/generate_packaging_manifests.sh"
        in
        with_temp_dir "oasis-packaging-manifests" (fun output_dir ->
            let generated =
              Process.run_capture ~cwd:repo_root manifest_script
                [ "--output-dir"; output_dir ]
            in
            assert_int_equal 0 generated.status
              "packaging manifest generation should succeed";
            assert_string_not_contains ~needle:"setlocale" generated.output
              "packaging manifest generation should not leak shell locale warnings";
            assert_string_equal
              (Fs.read_file (Filename.concat output_dir "oasis.opam"))
              (Fs.read_file (Filename.concat repo_root "oasis.opam"))
              "oasis.opam should be generated from the shared release metadata";
            assert_string_equal
              (Fs.read_file (Filename.concat output_dir "Formula/oasis.rb"))
              (Fs.read_file (Filename.concat repo_root "Formula/oasis.rb"))
              "the committed Homebrew formula should be generated from the shared release metadata"));
    ( "can refresh a retained source archive while generating packaging manifests",
      fun () ->
        let repo_root = Sys.getcwd () in
        let manifest_script =
          Filename.concat repo_root "scripts/generate_packaging_manifests.sh"
        in
        with_temp_dir "oasis-packaging-manifests-retained" (fun workspace ->
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
              (Filename.concat archive_dir "oasis-0.1.0-source.tar.gz");
            assert_string_equal
              (Fs.read_file (Filename.concat output_dir "Formula/oasis.rb"))
              (Fs.read_file (Filename.concat repo_root "Formula/oasis.rb"))
              "retained-archive manifest generation should match the committed Homebrew formula"));
    ( "can reuse an explicit source archive when generating packaging manifests",
      fun () ->
        let repo_root = Sys.getcwd () in
        let manifest_script =
          Filename.concat repo_root "scripts/generate_packaging_manifests.sh"
        in
        let archive_script =
          Filename.concat repo_root "scripts/build_release_archives.sh"
        in
        with_temp_dir "oasis-packaging-manifests-archive" (fun workspace ->
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
                  Filename.concat archive_dir "oasis-0.1.0-source.tar.gz";
                ]
            in
            assert_int_equal 0 generated.status
              "packaging manifest generation should reuse explicit source archives";
            assert_string_equal
              (Fs.read_file (Filename.concat output_dir "oasis.opam"))
              (Fs.read_file (Filename.concat repo_root "oasis.opam"))
              "explicit-archive manifest generation should still render oasis.opam from shared metadata";
            assert_string_equal
              (Fs.read_file (Filename.concat output_dir "Formula/oasis.rb"))
              (Fs.read_file (Filename.concat repo_root "Formula/oasis.rb"))
              "explicit-archive manifest generation should match the committed Homebrew formula"));
    ( "release-manifests refreshes a local source archive alongside packaging manifests",
      fun () ->
        let repo_root = Sys.getcwd () in
        with_temp_dir "oasis-release-manifests" (fun workspace ->
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
              [ "oasis.opam"; "Formula/oasis.rb" ];
            let dist_dir = Filename.concat workspace "dist" in
            if Fs.exists dist_dir then Fs.remove_tree dist_dir;
            let generated = run_make ~cwd:workspace [ "release-manifests" ] in
            assert_int_equal 0 generated.status
              ("make release-manifests should succeed\n" ^ generated.output);
            assert_true
              (not (Fs.exists (Filename.concat workspace "_bootstrap")))
              "make release-manifests should not detour through bootstrap generation";
            assert_file_exists (Filename.concat workspace "oasis.opam");
            assert_file_exists (Filename.concat workspace "Formula/oasis.rb");
            assert_file_exists
              (Filename.concat workspace "dist/oasis-0.1.0-source.tar.gz")));
    ( "sync-generated refreshes bootstrap metadata and release artifacts in one pass",
      fun () ->
        let repo_root = Sys.getcwd () in
        with_temp_dir "oasis-sync-generated" (fun workspace ->
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
                "completions/oasis.bash";
                "completions/_oasis";
                "completions/oasis.fish";
                "oasis.opam";
                "Formula/oasis.rb";
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
            assert_file_exists (Filename.concat workspace "completions/oasis.bash");
            assert_file_exists (Filename.concat workspace "completions/_oasis");
            assert_file_exists (Filename.concat workspace "completions/oasis.fish");
            assert_file_exists (Filename.concat workspace "oasis.opam");
            assert_file_exists (Filename.concat workspace "Formula/oasis.rb");
            assert_file_exists
              (Filename.concat workspace "dist/oasis-0.1.0-source.tar.gz");
            assert_file_exists
              (Filename.concat workspace "package/share/doc/oasis/cli.md");
            assert_file_exists
              (Filename.concat workspace
                 "package/share/bash-completion/completions/oasis");
            assert_file_exists
              (Filename.concat workspace
                 "package/share/zsh/site-functions/_oasis");
            assert_file_exists
              (Filename.concat workspace
                 "package/share/fish/vendor_completions.d/oasis.fish");
            assert_string_equal
              (Fs.read_file (Filename.concat workspace "docs/cli.md"))
              (Fs.read_file
                 (Filename.concat workspace "package/share/doc/oasis/cli.md"))
              "sync-generated should keep the packaged doc copy aligned with oasis docs")) ;
    ( "builds deterministic source and binary release archives",
      fun () ->
        let repo_root = Sys.getcwd () in
        let archive_script =
          Filename.concat repo_root "scripts/build_release_archives.sh"
        in
        with_temp_dir "oasis-packaging-archives" (fun output_dir ->
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
                ~env:[ ("OASIS_BIN", oasis_bin ()) ]
                archive_script
                [
                  "--binary-only";
                  "--output-dir";
                  output_dir;
                  "--binary";
                  oasis_bin ();
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
              (Filename.concat output_dir "oasis-0.1.0-source.tar.gz");
            assert_file_exists
              (Filename.concat output_dir "oasis-0.1.0-arm64-macos.tar.gz");
            let listing =
              Process.run_capture ~cwd:output_dir "tar"
                [ "-tzf"; "oasis-0.1.0-arm64-macos.tar.gz" ]
            in
            assert_int_equal 0 listing.status
              "binary archives should be valid tarballs";
            let binary_entries = nonempty_lines listing.output in
            assert_int_equal (List.length binary_entries)
              (List.length (String_util.dedup_preserve binary_entries))
              "binary release archives should not contain duplicate tar entries";
            assert_string_contains ~needle:"oasis-0.1.0-arm64-macos/bin/oasis\n"
              listing.output
              "binary release archives should stage the oasis binary";
            assert_string_contains
              ~needle:"oasis-0.1.0-arm64-macos/share/doc/oasis/cli.md\n"
              listing.output
              "binary release archives should stage packaged docs";
            let source_listing =
              Process.run_capture ~cwd:output_dir "tar"
                [ "-tzf"; "oasis-0.1.0-source.tar.gz" ]
            in
            assert_int_equal 0 source_listing.status
              "source archives should be valid tarballs";
            let source_entries = nonempty_lines source_listing.output in
            assert_int_equal (List.length source_entries)
              (List.length (String_util.dedup_preserve source_entries))
              "source release archives should not contain duplicate tar entries";
            assert_string_contains ~needle:"oasis-0.1.0/LICENSE\n"
              source_listing.output
              "source release archives should include the license text";
            assert_string_contains ~needle:"oasis-0.1.0/release/metadata.sh\n"
              source_listing.output
              "source release archives should include the canonical release metadata";
            with_temp_dir "oasis-packaging-source-extract" (fun extract_dir ->
                let unpacked =
                  Process.run_capture ~cwd:extract_dir "tar"
                    [ "-xzf"; Filename.concat output_dir "oasis-0.1.0-source.tar.gz" ]
                in
                assert_int_equal 0 unpacked.status
                  ("source archive extraction should succeed\n" ^ unpacked.output);
                let install_script =
                  Filename.concat extract_dir
                    "oasis-0.1.0/scripts/install_release_tree.sh"
                in
                let release_artifacts_script =
                  Filename.concat extract_dir
                    "oasis-0.1.0/scripts/generate_release_artifacts.sh"
                in
                let release_locale_script =
                  Filename.concat extract_dir
                    "oasis-0.1.0/scripts/release_locale.sh"
                in
                assert_file_exists release_locale_script;
                assert_true
                  (((Unix.stat install_script).Unix.st_perm land 0o111) <> 0)
                  "the source archive should preserve execute bits for install_release_tree.sh";
                assert_true
                  (((Unix.stat release_artifacts_script).Unix.st_perm land 0o111) <> 0)
                  "the source archive should preserve execute bits for generate_release_artifacts.sh")));
    ( "keeps package-manager definitions aligned with the shared release install script",
      (fun () ->
        let repo_root = Sys.getcwd () in
        let opam = Fs.read_file (Filename.concat repo_root "oasis.opam") in
        let flake = Fs.read_file (Filename.concat repo_root "flake.nix") in
        let formula =
          Fs.read_file (Filename.concat repo_root "Formula/oasis.rb")
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
        with_temp_dir "oasis-packaging-locale" (fun workspace ->
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
              (Filename.concat output_dir "oasis-0.1.0-source.tar.gz");
            assert_string_not_contains ~needle:"unexpected archive locale"
              run.output
              "archive generation should fall back to LC_ALL=C when UTF-8 C locales are unavailable")) ;
    ( "keeps the Homebrew formula syntax-valid",
      fun () ->
        let repo_root = Sys.getcwd () in
        let check =
          Process.run_capture ~cwd:repo_root "ruby"
            [ "-c"; "Formula/oasis.rb" ]
        in
        assert_int_equal 0 check.status
          ("Formula/oasis.rb should stay valid Ruby\n" ^ check.output));
    ( "keeps oasis.opam valid under opam lint",
      fun () ->
        let repo_root = Sys.getcwd () in
        let lint =
          Process.run_capture ~cwd:repo_root "opam" [ "lint"; "oasis.opam" ]
        in
        assert_int_equal 0 lint.status
          ("oasis.opam should stay valid under opam lint\n" ^ lint.output));
    ( "updates a dedicated Homebrew tap checkout from the generated formula",
      fun () ->
        let repo_root = Sys.getcwd () in
        let update_script =
          Filename.concat repo_root "scripts/update_homebrew_tap.sh"
        in
        let formula = Fs.read_file (Filename.concat repo_root "Formula/oasis.rb") in
        with_temp_dir "oasis-packaging-tap" (fun workspace ->
            let tap_dir = Filename.concat workspace "homebrew-oasis" in
            Fs.ensure_dir tap_dir;
            let init = Process.run_capture ~cwd:tap_dir "git" [ "init" ] in
            assert_int_equal 0 init.status
              ("tap git init should succeed\n" ^ init.output);
            let updated =
              Process.run_capture ~cwd:repo_root update_script
                [ "--tap-dir"; tap_dir; "--formula"; Filename.concat repo_root "Formula/oasis.rb"; "--commit" ]
            in
            assert_int_equal 0 updated.status
              ("Homebrew tap update should succeed\n" ^ updated.output);
            assert_string_not_contains ~needle:"setlocale" updated.output
              "the Homebrew tap updater should not leak shell locale warnings";
            assert_string_equal formula
              (Fs.read_file (Filename.concat tap_dir "Formula/oasis.rb"))
              "the tap update flow should copy the generated formula into the tap checkout";
            let log =
              Process.run_capture ~cwd:tap_dir "git"
                [ "log"; "-1"; "--pretty=%s" ]
            in
            assert_int_equal 0 log.status
              ("tap git log should succeed\n" ^ log.output);
            assert_string_contains ~needle:"oasis v0.1.0" log.output
              "the tap update flow should commit the rendered formula with the release tag in the message"));
    ( "clones the Homebrew tap from release metadata when no local checkout exists",
      fun () ->
        let repo_root = Sys.getcwd () in
        with_temp_dir "oasis-packaging-tap-clone" (fun workspace ->
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
              ~name:"OASIS_HOMEBREW_TAP_REMOTE_URL" ~value:remote_dir;
            let update_script =
              Filename.concat workspace "scripts/update_homebrew_tap.sh"
            in
            let tap_dir = Filename.concat workspace "homebrew-oasis" in
            let updated =
              Process.run_capture ~cwd:workspace update_script
                [ "--tap-dir"; tap_dir; "--formula"; Filename.concat workspace "Formula/oasis.rb"; "--commit" ]
            in
            assert_int_equal 0 updated.status
              ("tap updater should clone and update the remote checkout\n"
             ^ updated.output);
            assert_string_not_contains ~needle:"setlocale" updated.output
              "the cloned tap updater should not leak shell locale warnings";
            assert_file_exists (Filename.concat tap_dir "Formula/oasis.rb");
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
            assert_string_contains ~needle:"oasis v0.1.0" log.output
              "the cloned tap checkout should receive the rendered formula commit"));
    ( "cuts a release version, refreshes packaging manifests, and creates the matching tag",
      fun () ->
        let repo_root = Sys.getcwd () in
        with_temp_dir "oasis-packaging-cut" (fun workspace ->
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
              Process.run_capture ~cwd:workspace cut_script
                [ "--version"; "0.1.1"; "--tag" ]
            in
            assert_int_equal 0 cut.status
              ("release-cut should succeed\n" ^ cut.output);
            assert_string_not_contains ~needle:"setlocale" cut.output
              "release-cut should not leak shell locale warnings";
            assert_string_contains ~needle:"dist/oasis-0.1.1-source.tar.gz"
              cut.output
              "release-cut should report the refreshed local source archive";
            let metadata =
              Fs.read_file (Filename.concat workspace "release/metadata.sh")
            in
            let formula =
              Fs.read_file (Filename.concat workspace "Formula/oasis.rb")
            in
            assert_string_contains ~needle:"OASIS_RELEASE_VERSION='0.1.1'"
              metadata
              "release-cut should bump the canonical release metadata version";
            assert_string_contains
              ~needle:"/releases/download/v0.1.1/oasis-0.1.1-source.tar.gz"
              formula
              "release-cut should refresh the Homebrew formula from the new source archive";
            assert_file_exists
              (Filename.concat workspace "dist/oasis-0.1.1-source.tar.gz");
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
        assert_string_contains ~needle:". release/metadata.sh" workflow
          "the release workflow should load the canonical release metadata";
        assert_string_contains
          ~needle:"./scripts/build_release_archives.sh --source-only --output-dir dist"
          workflow
          "the release workflow should publish a deterministic source archive";
        assert_string_contains
          ~needle:"./scripts/render_homebrew_formula.sh"
          workflow
          "the release workflow should render the Homebrew formula from the source archive";
        assert_string_contains
          ~needle:"./scripts/update_homebrew_tap.sh"
          workflow
          "the release workflow should publish the rendered formula through the dedicated tap update flow";
        assert_string_not_contains
          ~needle:"bash scripts/build_release_archives.sh"
          workflow
          "the release workflow should execute archive scripts directly instead of forcing bash";
        assert_string_contains
          ~needle:"repository: ${{ steps.metadata.outputs.tap_repo }}"
          workflow
          "the release workflow should check out the dedicated tap repository before pushing formula updates";
        assert_string_contains ~needle:"softprops/action-gh-release@v2" workflow
          "the release workflow should publish the generated release assets");
  ]
