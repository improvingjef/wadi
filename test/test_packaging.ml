open Test_support

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
    ( "keeps package-manager definitions aligned with the shared release install script",
      (fun () ->
        let repo_root = Sys.getcwd () in
        let opam = Fs.read_file (Filename.concat repo_root "oasis.opam") in
        let flake = Fs.read_file (Filename.concat repo_root "flake.nix") in
        assert_string_contains ~needle:"[make \"release-artifacts\"]" opam
          "the opam package should build through the canonical release-artifact target";
        assert_string_contains ~needle:"scripts/install_release_tree.sh" opam
          "the opam package should install through the shared release-tree installer";
        assert_string_contains ~needle:"make release-artifacts" flake
          "the Nix flake should build through the canonical release-artifact target";
        assert_string_contains ~needle:"scripts/install_release_tree.sh" flake
          "the Nix flake should install through the shared release-tree installer")) ;
    ( "keeps oasis.opam valid under opam lint",
      (fun () ->
        let repo_root = Sys.getcwd () in
        let lint =
          Process.run_capture ~cwd:repo_root "opam" [ "lint"; "oasis.opam" ]
        in
        assert_int_equal 0 lint.status
          ("oasis.opam should stay valid under opam lint\n" ^ lint.output))) ;
  ]
