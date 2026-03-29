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
                    "bash" [ release_script; "--output-dir"; output_dir ]
                in
                assert_int_equal 0 generated.status
                  "release artifact generation should succeed before install";
                let installed =
                  Process.run_capture ~cwd:repo_root "bash"
                    [
                      install_script;
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
              Process.run_capture ~cwd:repo_root "bash"
                [ manifest_script; "--output-dir"; output_dir ]
            in
            assert_int_equal 0 generated.status
              "packaging manifest generation should succeed";
            assert_string_equal
              (Fs.read_file (Filename.concat output_dir "oasis.opam"))
              (Fs.read_file (Filename.concat repo_root "oasis.opam"))
              "oasis.opam should be generated from the shared release metadata";
            assert_string_equal
              (Fs.read_file (Filename.concat output_dir "Formula/oasis.rb"))
              (Fs.read_file (Filename.concat repo_root "Formula/oasis.rb"))
              "the committed Homebrew formula should be generated from the shared release metadata"));
    ( "builds deterministic source and binary release archives",
      fun () ->
        let repo_root = Sys.getcwd () in
        let archive_script =
          Filename.concat repo_root "scripts/build_release_archives.sh"
        in
        with_temp_dir "oasis-packaging-archives" (fun output_dir ->
            let source_run =
              Process.run_capture ~cwd:repo_root "bash"
                [ archive_script; "--source-only"; "--output-dir"; output_dir ]
            in
            assert_int_equal 0 source_run.status
              "source archive generation should succeed";
            let binary_run =
              Process.run_capture ~cwd:repo_root
                ~env:[ ("OASIS_BIN", oasis_bin ()) ]
                "bash"
                [
                  archive_script;
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
            assert_string_contains ~needle:"oasis-0.1.0/LICENSE\n"
              source_listing.output
              "source release archives should include the license text";
            assert_string_contains ~needle:"oasis-0.1.0/release/metadata.sh\n"
              source_listing.output
              "source release archives should include the canonical release metadata"));
    ( "keeps package-manager definitions aligned with the shared release install script",
      (fun () ->
        let repo_root = Sys.getcwd () in
        let opam = Fs.read_file (Filename.concat repo_root "oasis.opam") in
        let flake = Fs.read_file (Filename.concat repo_root "flake.nix") in
        let formula =
          Fs.read_file (Filename.concat repo_root "Formula/oasis.rb")
        in
        assert_string_contains ~needle:"[make \"release-artifacts\"]" opam
          "the opam package should build through the canonical release-artifact target";
        assert_string_contains ~needle:"scripts/install_release_tree.sh" opam
          "the opam package should install through the shared release-tree installer";
        assert_string_contains ~needle:"make release-artifacts" flake
          "the Nix flake should build through the canonical release-artifact target";
        assert_string_contains ~needle:"scripts/install_release_tree.sh" flake
          "the Nix flake should install through the shared release-tree installer";
        assert_string_contains ~needle:"system \"make\", \"release-artifacts\""
          formula
          "the Homebrew formula should build through the canonical release-artifact target";
        assert_string_contains ~needle:"scripts/install_release_tree.sh" formula
          "the Homebrew formula should install through the shared release-tree installer")) ;
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
              Process.run_capture ~cwd:repo_root "bash"
                [ update_script; "--tap-dir"; tap_dir; "--formula"; Filename.concat repo_root "Formula/oasis.rb"; "--commit" ]
            in
            assert_int_equal 0 updated.status
              ("Homebrew tap update should succeed\n" ^ updated.output);
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
    ( "cuts a release version, refreshes packaging manifests, and creates the matching tag",
      fun () ->
        let repo_root = Sys.getcwd () in
        with_temp_dir "oasis-packaging-cut" (fun workspace ->
            copy_tracked_repo ~src_root:repo_root ~dst_root:workspace
              ~extra_paths:
                [ "scripts/cut_release.sh"; "scripts/update_homebrew_tap.sh" ]
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
              Process.run_capture ~cwd:workspace "bash"
                [ cut_script; "--version"; "0.1.1"; "--tag" ]
            in
            assert_int_equal 0 cut.status
              ("release-cut should succeed\n" ^ cut.output);
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
          ~needle:"scripts/build_release_archives.sh --source-only --output-dir dist"
          workflow
          "the release workflow should publish a deterministic source archive";
        assert_string_contains
          ~needle:"scripts/render_homebrew_formula.sh"
          workflow
          "the release workflow should render the Homebrew formula from the source archive";
        assert_string_contains
          ~needle:"scripts/update_homebrew_tap.sh"
          workflow
          "the release workflow should publish the rendered formula through the dedicated tap update flow";
        assert_string_contains
          ~needle:"repository: ${{ steps.metadata.outputs.tap_repo }}"
          workflow
          "the release workflow should check out the dedicated tap repository before pushing formula updates";
        assert_string_contains ~needle:"softprops/action-gh-release@v2" workflow
          "the release workflow should publish the generated release assets");
  ]
