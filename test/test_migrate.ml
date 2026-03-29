open Test_support

let write_source workspace relative_path contents =
  Fs.write_file (Filename.concat workspace relative_path) contents

let write_executable workspace relative_path contents =
  let path = Filename.concat workspace relative_path in
  Fs.write_file path contents;
  Unix.chmod path 0o755;
  path

let cases =
  [
    ( "migrates dune files into an oasis manifest on stdout",
      (fun () ->
        with_temp_dir "oasis-migrate-basic" (fun workspace ->
            write_workspace_file workspace "dune-project"
              {|
(lang dune 3.11)
(name migrate_demo)
|};
            write_workspace_file workspace "lib/dune"
              {|
(library
 (name core)
 (public_name migrate_demo.core)
 (libraries unix))
|};
            write_workspace_file workspace "app/dune"
              {|
(executable
 (name main)
 (public_name migrate-demo)
 (libraries core str))
|};
            write_workspace_file workspace "test/dune"
              {|
(test
 (name unit)
 (libraries core ounit2))
|};
            write_source workspace "lib/core.ml" {|let value = "core"|};
            write_source workspace "app/main.ml" {|let () = print_endline Core.value|};
            write_source workspace "test/unit.ml" {|let () = print_endline Core.value|};
            let migrate = run_oasis ~cwd:workspace [ "migrate"; "--stdout" ] in
            assert_int_equal 0 migrate.status
              "migrate --stdout should render a manifest";
            assert_string_contains ~needle:"workspace = \"migrate_demo\"\n"
              migrate.output
              "migrate should preserve the dune-project name";
            assert_string_contains
              ~needle:"[library.core]\npublic_name = \"migrate_demo.core\"\n"
              migrate.output
              "migrate should preserve dune public names as manifest fields";
            assert_string_contains ~needle:"dir = \"lib\"\n" migrate.output
              "migrate should preserve stanza directories";
            assert_string_contains ~needle:"packages = [\"unix\"]\n"
              migrate.output
              "migrate should keep external package dependencies on libraries";
            assert_string_contains
              ~needle:"[executable.main]\npublic_name = \"migrate-demo\"\ndir = \"app\"\nmain = \"main\"\ndeps = [\"core\"]\npackages = [\"str\"]\n"
              migrate.output
              "migrate should split local libraries from external packages";
            assert_string_contains
              ~needle:"[test.unit]\ndir = \"test\"\nmain = \"unit\"\ndeps = [\"core\"]\npackages = [\"ounit2\"]\n"
              migrate.output
              "migrate should translate dune tests into oasis test targets")) );
    ( "infers helper modules for dune executables groups",
      (fun () ->
        with_temp_dir "oasis-migrate-executables" (fun workspace ->
            write_workspace_file workspace "app/dune"
              {|
(executables
 (names alpha beta)
 (libraries unix))
|};
            write_source workspace "app/alpha.ml" {|let () = print_endline Shared.value|};
            write_source workspace "app/beta.ml" {|let () = print_endline Shared.value|};
            write_source workspace "app/shared.ml" {|let value = "shared"|};
            let migrate = run_oasis ~cwd:workspace [ "migrate"; "--stdout" ] in
            assert_int_equal 0 migrate.status
              "migrate should handle dune executables groups";
            assert_string_contains
              ~needle:"[executable.alpha]\ndir = \"app\"\nmain = \"alpha\"\nmodules = [\"shared\"]\npackages = [\"unix\"]\n"
              migrate.output
              "migrate should infer helper modules for the first executable";
            assert_string_contains
              ~needle:"[executable.beta]\ndir = \"app\"\nmain = \"beta\"\nmodules = [\"shared\"]\npackages = [\"unix\"]\n"
              migrate.output
              "migrate should infer helper modules for the second executable")) );
    ( "refuses to overwrite an existing oasis manifest without force",
      (fun () ->
        with_temp_dir "oasis-migrate-overwrite" (fun workspace ->
            write_workspace_file workspace "app/dune"
              {|
(executable
 (name main))
|};
            write_source workspace "app/main.ml" {|let () = ()|};
            write_manifest workspace
              {|
workspace = "existing"
version = 1
|};
            let migrate = run_oasis ~cwd:workspace [ "migrate" ] in
            assert_true (migrate.status <> 0)
              "migrate should not overwrite an existing manifest by default";
            assert_string_contains
              ~needle:"refusing to overwrite existing file"
              migrate.output
              "migrate should explain how to opt into overwriting")) );
    ( "migrates dune preprocess, pps, public names, and rules into first-class oasis sections",
      (fun () ->
        with_temp_dir "oasis-migrate-advanced" (fun workspace ->
            write_workspace_file workspace "dune-project"
              {|
(lang dune 3.11)
(name migrate_demo)
|};
            write_workspace_file workspace "dune"
              {|
(library
 (name core)
 (public_name migrate_demo.core)
 (modules core version)
 (preprocess (action (run ./tools/expand.sh)))
 (libraries unix))

(executable
 (name main)
 (public_name migrate-demo)
 (libraries core)
 (pps ppx.demo))

(rule
 (targets version.ml)
 (deps config/version.txt)
 (action (with-stdout-to %{target} (run ./tools/version.sh))))
|};
            write_source workspace "core.ml" {|let message = Version.value|};
            write_source workspace "main.ml" {|let () = print_endline Core.message|};
            write_source workspace "config/version.txt" "1.0.0\n";
            ignore
              (write_executable workspace "tools/expand.sh"
                 "#!/bin/sh\ncat\n");
            ignore
              (write_executable workspace "tools/version.sh"
                 "#!/bin/sh\nprintf 'let value = \"1.0.0\"\\n'\n");
            let ocamlfind =
              write_executable workspace "fake-ocamlfind.sh"
                "#!/bin/sh\nset -eu\nif [ \"$1\" = printppx ]; then\n  shift\n  printf './ppx/demo.exe --as-ppx\\n'\nelse\n  echo unsupported >&2\n  exit 1\nfi\n"
            in
            with_env "OCAMLFIND" ocamlfind (fun () ->
                let migrate = run_oasis ~cwd:workspace [ "migrate"; "--stdout" ] in
                assert_int_equal 0 migrate.status
                  "migrate should translate richer dune forms";
                assert_string_contains
                  ~needle:"[preprocess.dune_preprocess_1]\nargv = [\"tools/expand.sh\"]\ncwd = \".\"\n"
                  migrate.output
                  "migrate should turn dune preprocess actions into preprocess sections";
                assert_string_contains
                  ~needle:"[ppx.dune_ppx_2]\nargv = [\"sh\", \"-c\", \"./ppx/demo.exe --as-ppx\"]\n"
                  migrate.output
                  "migrate should resolve dune pps into ppx sections";
                assert_string_contains
                  ~needle:"[action.dune_action_3]\nargv = [\"sh\", \"-c\", \"'tools/version.sh' > 'version.ml'\"]\noutputs = [\"version.ml\"]\ndeps = [\"config/version.txt\"]\ncwd = \".\"\n"
                  migrate.output
                  "migrate should turn dune rules into oasis actions";
                assert_string_contains
                  ~needle:"[library.core]\npublic_name = \"migrate_demo.core\"\ndir = \".\"\nmodules = [\"core\", \"version\"]\nactions = [\"dune_action_3\"]\npreprocess = [\"dune_preprocess_1\"]\npackages = [\"unix\"]\n"
                  migrate.output
                  "migrate should preserve public library metadata and attach generated tools";
                assert_string_contains
                  ~needle:"[executable.main]\npublic_name = \"migrate-demo\"\ndir = \".\"\nmain = \"main\"\nppx = [\"dune_ppx_2\"]\ndeps = [\"core\"]\n"
                  migrate.output
                  "migrate should preserve executable public names and ppx references";
                assert_string_not_contains
                  ~needle:"# dune public_name"
                  migrate.output
                  "public names should be emitted as manifest fields instead of review comments")) ));
  ]
