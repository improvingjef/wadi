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
    ( "migrates dune files into an wadi manifest on stdout",
      (fun () ->
        with_temp_dir "wadi-migrate-basic" (fun workspace ->
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
            let migrate = run_wadi ~cwd:workspace [ "migrate"; "--stdout" ] in
            assert_int_equal 0 migrate.status
              "migrate --stdout should render a manifest";
            assert_string_contains ~needle:"workspace = \"migrate_demo\"\n"
              migrate.output
              "migrate should preserve the dune-project name";
            assert_string_contains
              ~needle:"[library.core]\npublic_name = \"migrate_demo.core\"\n"
              migrate.output
              "migrate should preserve dune public names as manifest fields";
            assert_string_contains ~needle:"wrapped = true\n" migrate.output
              "migrate should preserve dune's default wrapped-library behavior";
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
              "migrate should translate dune tests into wadi test targets")) );
    ( "preserves explicit dune wrapped=false libraries",
      (fun () ->
        with_temp_dir "wadi-migrate-wrapped-false" (fun workspace ->
            write_workspace_file workspace "lib/dune"
              {|
(library
 (name core)
 (wrapped false))
|};
            write_source workspace "lib/core.ml" {|let value = "core"|};
            let migrate = run_wadi ~cwd:workspace [ "migrate"; "--stdout" ] in
            assert_int_equal 0 migrate.status
              "migrate should handle explicit dune wrapped flags";
            assert_string_not_contains ~needle:"wrapped = true" migrate.output
              "wrapped=false dune libraries should not opt into generated wrappers";
            assert_string_contains
              ~needle:"[library.core]\ndir = \"lib\"\nmodules = [\"core\"]\n"
              migrate.output
              "wrapped=false dune libraries should still migrate as normal libraries")) );
    ( "drops checked-in wrapper sources from migrated wrapped-library module lists",
      (fun () ->
        with_temp_dir "wadi-migrate-custom-wrapper" (fun workspace ->
            write_workspace_file workspace "lib/dune"
              {|
(library
 (name core))
|};
            write_source workspace "lib/core.ml" {|module Greeting = Greeting|};
            write_source workspace "lib/greeting.ml" {|let message = "hello"|};
            let migrate = run_wadi ~cwd:workspace [ "migrate"; "--stdout" ] in
            assert_int_equal 0 migrate.status
              "migrate should preserve wrapped libraries with checked-in wrapper modules";
            assert_string_contains
              ~needle:"[library.core]\nwrapped = true\ndir = \"lib\"\nmodules = [\"greeting\"]\n"
              migrate.output
              "migrate should omit the checked-in wrapper stem from wrapped-library child modules";
            assert_string_not_contains ~needle:"modules = [\"core\", \"greeting\"]"
              migrate.output
              "migrate should not emit the wrapper stem as a child module")) );
    ( "drops checked-in wrapper sources from explicit dune wrapped-library module lists",
      (fun () ->
        with_temp_dir "wadi-migrate-explicit-wrapper-modules" (fun workspace ->
            write_workspace_file workspace "lib/dune"
              {|
(library
 (name core)
 (modules core greeting))
|};
            write_source workspace "lib/core.ml" {|module Greeting = Greeting|};
            write_source workspace "lib/greeting.ml" {|let message = "hello"|};
            let migrate = run_wadi ~cwd:workspace [ "migrate"; "--stdout" ] in
            assert_int_equal 0 migrate.status
              "migrate should preserve explicit dune wrapped-library module lists with a checked-in wrapper";
            assert_string_contains
              ~needle:"[library.core]\nwrapped = true\ndir = \"lib\"\nmodules = [\"greeting\"]\n"
              migrate.output
              "migrate should omit the checked-in wrapper stem even when dune lists it explicitly";
            assert_string_not_contains ~needle:"modules = [\"core\", \"greeting\"]"
              migrate.output
              "migrate should not keep the wrapper stem in the migrated module list")) );
    ( "infers helper modules for dune executables groups",
      (fun () ->
        with_temp_dir "wadi-migrate-executables" (fun workspace ->
            write_workspace_file workspace "app/dune"
              {|
(executables
 (names alpha beta)
 (libraries unix))
|};
            write_source workspace "app/alpha.ml" {|let () = print_endline Shared.value|};
            write_source workspace "app/beta.ml" {|let () = print_endline Shared.value|};
            write_source workspace "app/shared.ml" {|let value = "shared"|};
            let migrate = run_wadi ~cwd:workspace [ "migrate"; "--stdout" ] in
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
    ( "refuses to overwrite an existing wadi manifest without force",
      (fun () ->
        with_temp_dir "wadi-migrate-overwrite" (fun workspace ->
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
            let migrate = run_wadi ~cwd:workspace [ "migrate" ] in
            assert_true (migrate.status <> 0)
              "migrate should not overwrite an existing manifest by default";
            assert_string_contains
              ~needle:"refusing to overwrite existing file"
              migrate.output
              "migrate should explain how to opt into overwriting")) );
    ( "migrates dune preprocess, pps, public names, and rules into first-class wadi sections",
      (fun () ->
        with_temp_dir "wadi-migrate-advanced" (fun workspace ->
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
                let migrate = run_wadi ~cwd:workspace [ "migrate"; "--stdout" ] in
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
                  ~needle:"[action.dune_action_3]\nargv = [\"tools/version.sh\"]\noutputs = [\"version.ml\"]\ndeps = [\"config/version.txt\"]\nstdout = \"version.ml\"\ncwd = \".\"\n"
                  migrate.output
                  "migrate should turn dune rules into wadi actions";
                assert_string_contains
                  ~needle:"[library.core]\npublic_name = \"migrate_demo.core\"\nwrapped = true\ndir = \".\"\nmodules = [\"version\"]\nactions = [\"dune_action_3\"]\npreprocess = [\"dune_preprocess_1\"]\npackages = [\"unix\"]\n"
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
    ( "migrates dune promote-mode source rules into checked-in generated source outputs",
      (fun () ->
        with_temp_dir "wadi-migrate-promote-source" (fun workspace ->
            write_workspace_file workspace "dune"
              {|
(library
 (name core)
 (modules core version))

(rule
 (mode promote)
 (targets version.ml)
 (action (with-stdout-to %{target} (run ./tools/version.sh))))
|};
            write_source workspace "core.ml" {|let message = Version.value|};
            write_source workspace "version.ml" {|let value = "checked-in"|};
            ignore
              (write_executable workspace "tools/version.sh"
                 "#!/bin/sh\nprintf 'let value = \"generated\"\\n'\n");
            let migrate = run_wadi ~cwd:workspace [ "migrate"; "--stdout" ] in
            assert_int_equal 0 migrate.status
              "migrate should translate dune promote-mode rules";
            assert_string_contains
              ~needle:"[action.dune_action_1]\nargv = [\"tools/version.sh\"]\noutputs = [\"version.ml\"]\nchecked_in_sources = [\"version.ml\"]\nstdout = \"version.ml\"\ncwd = \".\"\n"
              migrate.output
              "migrate should preserve promote-mode source targets as checked-in generated sources";
            assert_string_contains
              ~needle:"[library.core]\nwrapped = true\ndir = \".\"\nmodules = [\"version\"]\nactions = [\"dune_action_1\"]\n"
              migrate.output
              "migrate should still attach the promote-mode action to the matching target")) );
    ( "infers explicit auxiliary file deps from dune preprocess actions and rules",
      (fun () ->
        with_temp_dir "wadi-migrate-inferred-deps" (fun workspace ->
            write_workspace_file workspace "dune"
              {|
(library
 (name core)
 (modules core generated)
 (preprocess (action (run ./tools/expand.sh templates/banner.txt))))

(rule
 (targets generated.ml)
 (action (run ./tools/render.sh data/source.txt generated.ml)))
|};
            write_source workspace "core.ml" {|let message = Generated.value|};
            write_workspace_file workspace "templates/banner.txt" "banner\n";
            write_workspace_file workspace "data/source.txt" "source\n";
            ignore
              (write_executable workspace "tools/expand.sh"
                 "#!/bin/sh\ncat\n");
            ignore
              (write_executable workspace "tools/render.sh"
                 "#!/bin/sh\ncat \"$1\" > \"$2\"\n");
            let migrate = run_wadi ~cwd:workspace [ "migrate"; "--stdout" ] in
            assert_int_equal 0 migrate.status
              "migrate should infer auxiliary deps for straightforward dune actions";
            assert_string_contains
              ~needle:"[preprocess.dune_preprocess_1]\nargv = [\"tools/expand.sh\", \"templates/banner.txt\"]\ncwd = \".\"\ndeps = [\"templates/banner.txt\"]\n"
              migrate.output
              "migrate should infer preprocess deps from explicit file arguments";
            assert_string_contains
              ~needle:"[action.dune_action_2]\nargv = [\"tools/render.sh\", \"data/source.txt\", \"generated.ml\"]\noutputs = [\"generated.ml\"]\ndeps = [\"data/source.txt\"]\ncwd = \".\"\n"
              migrate.output
              "migrate should infer dune rule deps from explicit file arguments while excluding outputs";
            assert_string_not_contains
              ~needle:"generated preprocess 'dune_preprocess_1' from dune action"
              migrate.output
              "migrate should drop the old manual-deps warning when explicit inputs are inferred")) );
    ( "preserves dune modules_without_implementation entries in migrated targets",
      (fun () ->
        with_temp_dir "wadi-migrate-interface-only" (fun workspace ->
            write_workspace_file workspace "lib/dune"
              {|
(library
 (name demo)
 (modules logic)
 (modules_without_implementation api))
|};
            write_source workspace "lib/logic.ml" {|let value = "logic"|};
            write_source workspace "lib/api.mli" {|val value : string|};
            let migrate = run_wadi ~cwd:workspace [ "migrate"; "--stdout" ] in
            assert_int_equal 0 migrate.status
              "migrate should preserve interface-only dune modules";
            assert_string_contains
              ~needle:"[library.demo]\nwrapped = true\ndir = \"lib\"\nmodules = [\"logic\", \"api\"]\n"
              migrate.output
              "migrate should merge modules_without_implementation into the manifest module list")) );
    ( "migrates dune progn, with-stdin-from, diff, and alias deps into usable wadi actions",
      (fun () ->
        with_temp_dir "wadi-migrate-composite-actions" (fun workspace ->
            write_workspace_file workspace "dune"
              {|
(library
 (name core)
 (modules core)
 (preprocess (action (with-stdin-from fixtures/input.txt (run ./tools/filter.sh)))))

(rule
 (targets copied.txt)
 (deps fixtures/expected.txt (alias runtest))
 (action
  (progn
    (copy fixtures/expected.txt copied.txt)
    (diff fixtures/expected.txt copied.txt))))
|};
            write_source workspace "core.ml" {|let value = 1|};
            write_workspace_file workspace "fixtures/input.txt" "input\n";
            write_workspace_file workspace "fixtures/expected.txt" "expected\n";
            ignore
              (write_executable workspace "tools/filter.sh"
                 "#!/bin/sh\ncat\n");
            let migrate = run_wadi ~cwd:workspace [ "migrate"; "--stdout" ] in
            assert_int_equal 0 migrate.status
              "migrate should support richer dune action forms without manual fallback";
            assert_string_contains
              ~needle:"[preprocess.dune_preprocess_1]\nargv = [\"tools/filter.sh\"]\ncwd = \".\"\nstdin_path = \"fixtures/input.txt\"\ndeps = [\"fixtures/input.txt\"]\n"
              migrate.output
              "migrate should translate with-stdin-from preprocess actions and infer their file deps";
            assert_string_contains
              ~needle:"[action.dune_action_2]\nsteps = [[\"cp\", \"fixtures/expected.txt\", \"copied.txt\"], [\"diff\", \"-u\", \"fixtures/expected.txt\", \"copied.txt\"]]\noutputs = [\"copied.txt\"]\ndeps = [\"fixtures/expected.txt\"]\ncwd = \".\"\n"
              migrate.output
              "migrate should translate progn/diff rules into a first-class multi-step wadi action";
            assert_string_contains
              ~needle:"# - generated action 'dune_action_2' from dune rule in"
              migrate.output
              "migrate should keep a review comment when alias deps cannot map to concrete wadi file deps";
            assert_string_contains ~needle:"references alias deps (runtest)"
              migrate.output
              "migrate should explain which dune alias dependency needs manual review";
            assert_string_not_contains
              ~needle:"ignored unsupported dune rule action"
              migrate.output
              "migrate should no longer drop progn/diff rules as unsupported")) );
  ]
