open Test_support

let write_source workspace relative_path contents =
  Fs.write_file (Filename.concat workspace relative_path) contents

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
              ~needle:"# dune public_name = \"migrate_demo.core\"\n[library.core]\n"
              migrate.output
              "migrate should retain dune public names as review comments";
            assert_string_contains ~needle:"dir = \"lib\"\n" migrate.output
              "migrate should preserve stanza directories";
            assert_string_contains ~needle:"packages = [\"unix\"]\n"
              migrate.output
              "migrate should keep external package dependencies on libraries";
            assert_string_contains
              ~needle:"[executable.main]\ndir = \"app\"\nmain = \"main\"\ndeps = [\"core\"]\npackages = [\"str\"]\n"
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
  ]
