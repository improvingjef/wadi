open Test_support

let render_bootstrap ?profile ?(scope = Bootstrap.Full) workspace =
  Bootstrap.render_makefile ?profile ~scope ~manifest_path:(manifest_path workspace)
    ()

let write_source = write_workspace_file

let write_executable workspace relative_path contents =
  let path = Filename.concat workspace relative_path in
  Fs.write_file path contents;
  Unix.chmod path 0o755;
  path

let run_bootstrap_loader ?(env = []) () =
  Process.run_capture ~env "ocaml" [ "scripts/render_bootstrap_mod_use.ml" ]

let render_format_name = function
  | Bootstrap.Makefile -> "makefile"
  | Bootstrap.Seed_metadata -> "seed-metadata"

let run_compiled_bootstrap ?profile ?(scope = Bootstrap.Full)
    ?(format = Bootstrap.Makefile) ?seed_root workspace =
  let args =
    [
      Bootstrap.hidden_command_name;
      "--manifest";
      manifest_path workspace;
      "--format";
      render_format_name format;
      "--scope";
      (match scope with
      | Bootstrap.Executable_only -> "app"
      | Bootstrap.Full -> "full");
    ]
    @
    (match profile with
    | Some profile -> [ "--profile"; profile ]
    | None -> [])
    @
    (match seed_root with
    | Some seed_root -> [ "--seed-root"; seed_root ]
    | None -> [])
  in
  run_binary (oasis_bin ()) args

let write_bootstrap_driver workspace generated_makefile =
  write_workspace_file workspace "scripts/render_bootstrap_mod_use.ml" "";
  write_workspace_file workspace "scripts/generate_bootstrap_makefile.ml" "";
  write_workspace_file workspace "Makefile"
    {|
OCAMLFIND ?= ocamlfind
OCAMLOPT ?= ocamlopt
OCAMLFLAGS ?= -g

BUILD_DIR := _bootstrap
OBJ_DIR := $(BUILD_DIR)/obj
BIN_DIR := $(BUILD_DIR)/bin
BOOTSTRAP_MANIFEST := oasis.toml
BOOTSTRAP_GENERATOR := scripts/generate_bootstrap_makefile.ml
BOOTSTRAP_MK := $(BUILD_DIR)/bootstrap.generated.mk
BOOTSTRAP_COMPILER_KIND := ocamlopt
BOOTSTRAP_COMPILER := $(OCAMLOPT)
OBJ_EXT := cmx

$(BUILD_DIR) $(OBJ_DIR) $(BIN_DIR):
	mkdir -p $@

define BOOTSTRAP_TOOL_CMD
$(if $(strip $(1)),$(OCAMLFIND) $(BOOTSTRAP_COMPILER_KIND) $(1),$(BOOTSTRAP_COMPILER))
endef

-include $(BOOTSTRAP_MK)
|};
  write_workspace_file workspace "_bootstrap/bootstrap.generated.mk"
    generated_makefile

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
    ( "derives bootstrap loader directives from the manifest instead of a hard-coded module list",
      (fun () ->
        with_temp_dir "oasis-bootstrap-loader" (fun workspace ->
            write_manifest workspace
              {|
[library.core]
dir = "src"
modules = ["alpha", "beta", "gamma"]
|};
            write_source workspace "src/beta.ml" {|let value = "beta"|};
            write_source workspace "src/alpha.ml" {|let value = Beta.value|};
            write_source workspace "src/gamma.ml"
              {|let value = Alpha.value ^ " + gamma"|};
            let loader =
              run_bootstrap_loader
                ~env:[ ("BOOTSTRAP_MODULE_MANIFEST", manifest_path workspace) ]
                ()
            in
            assert_int_equal 0 loader.status
              "the bootstrap loader helper should read manifest-driven modules";
            let beta_line =
              Printf.sprintf "#mod_use %S;;"
                (Filename.concat workspace "src/beta.ml")
            in
            let alpha_line =
              Printf.sprintf "#mod_use %S;;"
                (Filename.concat workspace "src/alpha.ml")
            in
            let gamma_line =
              Printf.sprintf "#mod_use %S;;"
                (Filename.concat workspace "src/gamma.ml")
            in
            assert_string_contains
              ~needle:(beta_line ^ "\n" ^ alpha_line ^ "\n" ^ gamma_line)
              loader.output
              "bootstrap loader directives should be ordered from source dependencies")) );
    ( "derives bootstrap object lists, self-dependencies, and ordered rules from the workspace model",
      (fun () ->
        with_temp_dir "oasis-bootstrap" (fun workspace ->
            write_manifest workspace
              {|
[library.core]
dir = "src"
modules = ["alpha", "beta"]

[executable.demo]
dir = "src"
main = "main"
modules = ["cli"]
deps = ["core"]

[test.suite]
dir = "test"
main = "test_main"
modules = ["test_helper"]
deps = ["core"]
|};
            write_source workspace "src/beta.ml" {|let value = "beta"|};
            write_source workspace "src/alpha.ml" {|let value = Beta.value|};
            write_source workspace "src/cli.ml" {|let run () = ignore Alpha.value|};
            write_source workspace "src/main.ml" {|let () = Cli.run ()|};
            write_source workspace "test/test_helper.ml"
              {|let run () = ignore Alpha.value|};
            write_source workspace "test/test_main.ml"
              {|let () = Test_helper.run ()|};
            let makefile = expect_ok (render_bootstrap workspace) in
            assert_string_contains
              ~needle:"$(BOOTSTRAP_MK): $(BOOTSTRAP_MANIFEST) $(BOOTSTRAP_GENERATOR) src/alpha.ml src/beta.ml src/cli.ml src/main.ml test/test_helper.ml test/test_main.ml"
              makefile
              "bootstrap generation should track the manifest-driven inputs that require a regenerated makefile";
            assert_string_contains ~needle:"COMMON_SEED_REUSE := yes" makefile
              "bootstrap generation should explicitly mark when shared seed objects are reusable";
            assert_string_contains
              ~needle:"COMMON_OBJS := $(OBJ_DIR)/beta.$(OBJ_EXT) $(OBJ_DIR)/alpha.$(OBJ_EXT)"
              makefile
              "bootstrap generation should sort common modules by dependencies";
            assert_string_contains
              ~needle:"APP_OBJS := $(COMMON_OBJS) $(OBJ_DIR)/cli.$(OBJ_EXT) $(OBJ_DIR)/main.$(OBJ_EXT)"
              makefile
              "bootstrap generation should derive executable object lists";
            assert_string_contains
              ~needle:"TEST_OBJS := $(COMMON_OBJS) $(OBJ_DIR)/test_helper.$(OBJ_EXT) $(OBJ_DIR)/test_main.$(OBJ_EXT)"
              makefile
              "bootstrap generation should derive test object lists";
            assert_string_contains
              ~needle:"$(OBJ_DIR)/alpha.$(OBJ_EXT): src/alpha.ml $(BOOTSTRAP_MK) $(OBJ_DIR)/beta.$(OBJ_EXT) | $(OBJ_DIR)"
              makefile
              "bootstrap generation should rebuild objects when the generated makefile changes";
            assert_string_contains
              ~needle:"$(OBJ_DIR)/main.$(OBJ_EXT): src/main.ml $(BOOTSTRAP_MK) $(OBJ_DIR)/cli.$(OBJ_EXT) | $(OBJ_DIR)"
              makefile
              "bootstrap generation should chain executable modules while depending on bootstrap metadata";
            assert_string_contains
              ~needle:"$(BIN_DIR)/demo: $(BOOTSTRAP_MK) $(APP_OBJS) | $(BIN_DIR)"
              makefile
              "bootstrap generation should make executable links depend on bootstrap metadata";
            assert_string_contains
              ~needle:"$(BIN_DIR)/suite: $(BOOTSTRAP_MK) $(TEST_OBJS) | $(BIN_DIR)"
              makefile
              "bootstrap generation should make test links depend on bootstrap metadata")) );
    ( "includes generated wrapper modules for wrapped libraries in bootstrap plans",
      (fun () ->
        with_temp_dir "oasis-bootstrap-wrapped" (fun workspace ->
            write_manifest workspace
              {|
[library.core]
wrapped = true
dir = "src"
modules = ["alpha"]

[executable.demo]
dir = "src"
main = "main"
deps = ["core"]

[test.suite]
dir = "test"
main = "test_main"
deps = ["core"]
|};
            write_source workspace "src/alpha.ml" {|let value = "alpha"|};
            write_source workspace "src/main.ml"
              {|let () = print_endline Core.Alpha.value|};
            write_source workspace "test/test_main.ml"
              {|let () = print_endline Core.Alpha.value|};
            let makefile = expect_ok (render_bootstrap workspace) in
            let wrapper_path =
              "_bootstrap/materialized/default/library-core/generated/core.ml"
            in
            assert_file_exists (Filename.concat workspace wrapper_path);
            assert_string_contains
              ~needle:"COMMON_OBJS := $(OBJ_DIR)/alpha.$(OBJ_EXT) $(OBJ_DIR)/core.$(OBJ_EXT)"
              makefile
              "wrapped libraries should add the generated wrapper module to bootstrap object lists";
            assert_string_contains
              ~needle:("$(OBJ_DIR)/core.$(OBJ_EXT): " ^ wrapper_path ^ " $(BOOTSTRAP_MK) $(OBJ_DIR)/alpha.$(OBJ_EXT) | $(OBJ_DIR)")
              makefile
              "bootstrap generation should compile the generated wrapper after its child modules")) );
    ( "uses checked-in wrapper modules in bootstrap plans without materializing generated wrappers",
      (fun () ->
        with_temp_dir "oasis-bootstrap-custom-wrapper" (fun workspace ->
            write_manifest workspace
              {|
[library.core]
wrapped = true
dir = "src"
modules = ["alpha"]

[executable.demo]
dir = "src"
main = "main"
deps = ["core"]

[test.suite]
dir = "test"
main = "test_main"
deps = ["core"]
|};
            write_source workspace "src/core.ml" {|module Alpha = Alpha|};
            write_source workspace "src/alpha.ml" {|let value = "alpha"|};
            write_source workspace "src/main.ml"
              {|let () = print_endline Core.Alpha.value|};
            write_source workspace "test/test_main.ml"
              {|let () = print_endline Core.Alpha.value|};
            let makefile = expect_ok (render_bootstrap workspace) in
            let generated_wrapper =
              Filename.concat workspace
                "_bootstrap/materialized/default/library-core/generated/core.ml"
            in
            assert_true (not (Fs.exists generated_wrapper))
              "bootstrap generation should not materialize a generated wrapper when a checked-in wrapper exists";
            assert_string_contains
              ~needle:"COMMON_OBJS := $(OBJ_DIR)/alpha.$(OBJ_EXT) $(OBJ_DIR)/core.$(OBJ_EXT)"
              makefile
              "checked-in wrapper modules should still participate in bootstrap object lists";
            assert_string_contains
              ~needle:"$(OBJ_DIR)/core.$(OBJ_EXT): src/core.ml $(BOOTSTRAP_MK) $(OBJ_DIR)/alpha.$(OBJ_EXT) | $(OBJ_DIR)"
              makefile
              "bootstrap generation should compile the checked-in wrapper source instead of a generated one")) );
    ( "renders the full bootstrap makefile through the compiled oasis binary",
      (fun () ->
        with_temp_dir "oasis-bootstrap-compiled" (fun workspace ->
            write_manifest workspace
              {|
[library.core]
dir = "src"
modules = ["alpha"]

[executable.demo]
dir = "src"
main = "main"
deps = ["core"]

[test.suite]
dir = "test"
main = "test_main"
deps = ["core"]
|};
            write_source workspace "src/alpha.ml" {|let value = "alpha"|};
            write_source workspace "src/main.ml"
              {|let () = print_endline Alpha.value|};
            write_source workspace "test/test_main.ml"
              {|let () = print_endline Alpha.value|};
            let expected = expect_ok (render_bootstrap workspace) in
            let compiled = run_compiled_bootstrap workspace in
            assert_int_equal 0 compiled.status
              "the hidden compiled bootstrap command should render successfully";
            assert_string_equal expected compiled.output
              "the compiled bootstrap planner should match Bootstrap.render_makefile")) );
    ( "uses a compiled seed binary for app-only bootstrap generation",
      (fun () ->
        let makefile = Fs.read_file (Filename.concat (Sys.getcwd ()) "Makefile") in
        assert_string_contains ~needle:"BOOTSTRAP_SEED_BIN := $(BIN_DIR)/oasis-seed"
          makefile
          "the top-level Makefile should define a compiled bootstrap seed binary";
        assert_string_contains
          ~needle:"include $(BOOTSTRAP_SEED_METADATA)"
          makefile
          "bootstrap should read cached seed metadata instead of probing the interpreter at runtime";
        assert_string_not_contains
          ~needle:"$(shell BOOTSTRAP_MODULE_MANIFEST=$(BOOTSTRAP_MANIFEST) $(OCAML) $(BOOTSTRAP_SOURCE_HELPER)"
          makefile
          "cold-start bootstrap should not shell out through the OCaml toplevel to discover seed metadata";
        assert_string_contains
          ~needle:"$(BOOTSTRAP_SEED_BIN) --manifest $(BOOTSTRAP_MANIFEST) --scope app"
          makefile
          "app-only bootstrap generation should run through the compiled seed binary";
        assert_string_contains
          ~needle:"$(OASIS_BIN) $(BOOTSTRAP_INTERNAL_COMMAND) --manifest $(BOOTSTRAP_MANIFEST) --format seed-metadata"
          makefile
          "bootstrap seed metadata refresh should run through the compiled bootstrap planner";
        assert_string_contains
          ~needle:"-I $(OBJ_DIR) -c \"$$src\" -o $(OBJ_DIR)/$$stem.$(OBJ_EXT)"
          makefile
          "bootstrap seed compilation should populate the shared object directory for reuse by the final app build";
        assert_string_contains
          ~needle:"grep -q '^COMMON_SEED_REUSE := yes$$' \"$(1)\""
          makefile
          "bootstrap makefile generation should consult the compiled plan before reusing shared seed objects";
        assert_string_contains ~needle:"rm -f $(BOOTSTRAP_SHARED_OUTPUTS)"
          makefile
          "bootstrap makefile generation should drop incompatible shared seed objects instead of reusing them";
        assert_string_not_contains
          ~needle:"render_bootstrap_mod_use.ml --format seed-metadata"
          makefile
          "seed metadata refresh should not fall back to the legacy script path";
        assert_string_not_contains
          ~needle:"ocaml scripts/generate_bootstrap_makefile.ml"
          makefile
          "cold-start bootstrap should no longer evaluate the planner through the OCaml toplevel")) ;
    ( "uses the compiled seed binary for full bootstrap generation without recursive app builds",
      (fun () ->
        let makefile = Fs.read_file (Filename.concat (Sys.getcwd ()) "Makefile") in
        assert_string_contains
          ~needle:"$(BOOTSTRAP_SEED_BIN) --manifest $(BOOTSTRAP_MANIFEST) --scope full"
          makefile
          "full bootstrap generation should run through the compiled seed binary";
        assert_string_not_contains
          ~needle:"$(MAKE) BOOTSTRAP_SCOPE=app $(BIN_DIR)/oasis"
          makefile
          "full bootstrap generation should not recurse through a separate app bootstrap build";
        assert_string_not_contains
          ~needle:"$(BIN_DIR)/oasis $(BOOTSTRAP_INTERNAL_COMMAND) --manifest $(BOOTSTRAP_MANIFEST) --scope full"
          makefile
          "full bootstrap generation should not require a freshly built app binary before the makefile exists")) ;
    ( "keeps cached bootstrap seed metadata in sync with the compiled bootstrap planner",
      (fun () ->
        let generated =
          run_compiled_bootstrap ~format:Bootstrap.Seed_metadata
            ~seed_root:"scripts/bootstrap_seed" (Sys.getcwd ())
        in
        assert_int_equal 0 generated.status
          "the compiled bootstrap planner should render seed metadata successfully";
        let cached =
          Fs.read_file
            (Filename.concat (Sys.getcwd ()) "scripts/bootstrap_seed_metadata.mk")
        in
        assert_string_equal generated.output cached
          "the cached bootstrap seed metadata should stay in sync with the compiled helper")) ;
    ( "renders transform-aware seed metadata for default-profile bootstrap libraries",
      (fun () ->
        with_temp_dir "oasis-bootstrap-seed-transforms" (fun workspace ->
            write_manifest workspace
              {|
[defaults]
profile = "release"

[profile.release]
compile_flags = ["-w", "+a"]
env = ["BUILD_PROFILE=release"]

[action.generate_version]
argv = ["./tools/generate.sh"]
cwd = "."
deps = ["config/version.txt"]
outputs = ["version.ml"]
sandbox = "target"

[preprocess.expand]
argv = ["./tools/expand.sh"]
deps = ["config/banner.txt"]

[ppx.rewrite]
argv = ["./ppx/rewrite.exe"]
deps = ["ppx/message.txt"]

[library.core]
dir = "lib"
modules = ["core", "version"]
actions = ["generate_version"]
preprocess = ["expand"]
ppx = ["rewrite"]

[executable.demo]
dir = "app"
main = "main"
deps = ["core"]
preprocess = ["expand"]
ppx = ["rewrite"]

[test.suite]
dir = "test"
main = "test_main"
deps = ["core"]
preprocess = ["expand"]
ppx = ["rewrite"]
|};
            write_source workspace "config/version.txt" "action";
            write_source workspace "config/banner.txt" "banner";
            write_source workspace "ppx/message.txt" "ppx";
            ignore
              (write_executable workspace "tools/generate.sh"
                 "#!/bin/sh\nset -eu\nversion=$(cat config/version.txt)\nprintf 'let value = \"%s\"\\n' \"$version\" > lib/version.ml\n");
            ignore
              (write_executable workspace "tools/expand.sh"
                 "#!/bin/sh\nset -eu\nbanner=$(cat config/banner.txt)\nsed \"s/@@PROFILE@@/${BUILD_PROFILE}/g; s/@@BANNER@@/${banner}/g\"\n");
            let _ppx_binary =
              Test_build.compile_ppx workspace "ppx/rewrite.ml"
                {|
open Ast_helper
open Ast_mapper
open Parsetree

let replacement () =
  let channel = open_in "ppx/message.txt" in
  Fun.protect
    ~finally:(fun () -> close_in_noerr channel)
    (fun () -> input_line channel)

let expr mapper expression =
  match expression.pexp_desc with
  | Pexp_constant
      { pconst_desc = Pconst_string ("ppx-marker", _, delimiter); pconst_loc = loc } ->
      Exp.constant
        {
          pconst_desc = Pconst_string (replacement (), loc, delimiter);
          pconst_loc = loc;
        }
  | _ -> default_mapper.expr mapper expression

let () =
  run_main (fun _argv -> { default_mapper with expr })
|}
                "ppx/rewrite.exe"
            in
            write_source workspace "lib/core.ml"
              {|let message = "@@PROFILE@@:@@BANNER@@:" ^ Version.value ^ ":" ^ "ppx-marker"|};
            write_source workspace "app/main.ml"
              {|let () = print_endline Core.message|};
            write_source workspace "test/test_main.ml"
              {|let () = print_endline Core.message|};
            let metadata =
              run_compiled_bootstrap ~format:Bootstrap.Seed_metadata
                ~seed_root:"scripts/bootstrap_seed" workspace
            in
            assert_int_equal 0 metadata.status
              "the compiled bootstrap planner should render transform-aware seed metadata";
            write_workspace_file workspace "scripts/bootstrap_seed_metadata.mk"
              metadata.output;
            assert_string_contains
              ~needle:"BOOTSTRAP_LIBRARY_ENV_PREFIX := BUILD_PROFILE='release'"
              metadata.output
              "seed metadata should capture profile environment bindings";
            assert_string_contains
              ~needle:"BOOTSTRAP_LIBRARY_COMPILE_FLAGS := -w +a"
              metadata.output
              "seed metadata should capture compile flags";
            assert_string_contains
              ~needle:"ppx/rewrite.exe"
              metadata.output
              "seed metadata should capture ppx arguments";
            assert_string_contains
              ~needle:"scripts/bootstrap_seed/release/library-core/version.ml"
              metadata.output
              "seed metadata should snapshot transformed generated sources";
            assert_string_contains
              ~needle:"scripts/bootstrap_seed/release/library-core/core.ml"
              metadata.output
              "seed metadata should snapshot transformed preprocessed sources";
            assert_file_exists
              (Filename.concat workspace
                 "scripts/bootstrap_seed/release/library-core/version.ml");
            assert_file_exists
              (Filename.concat workspace
                 "scripts/bootstrap_seed/release/library-core/core.ml");
            let makefile =
              expect_ok (render_bootstrap ~profile:"release" workspace)
            in
            assert_string_contains ~needle:"COMMON_SEED_REUSE := yes" makefile
              "the generated bootstrap plan should keep common seed reuse enabled when the requested profile matches the seed metadata profile")) );
    ( "benchmarks bootstrap latency and emits machine-readable summaries",
      (fun () ->
        with_temp_dir "oasis-bootstrap-benchmark" (fun workspace ->
            let fake_make = Filename.concat workspace "fake-make.sh" in
            write_workspace_file workspace "Makefile" "all:\n\t@:\n";
            write_workspace_file workspace "fake-make.sh"
              {|
#!/bin/sh
set -eu
while [ "$#" -gt 0 ]; do
  case "$1" in
    clean)
      rm -rf _bootstrap
      exit 0
      ;;
    _bootstrap/bin/oasis)
      mkdir -p _bootstrap/bin
      : > _bootstrap/bin/oasis
      ;;
    _bootstrap/bin/test_runner)
      mkdir -p _bootstrap/bin
      : > _bootstrap/bin/test_runner
      ;;
  esac
  shift
done
|};
            Unix.chmod fake_make 0o755;
            let benchmark =
              Process.run_capture
                ~env:[ ("MAKE", fake_make) ]
                ~cwd:(Sys.getcwd ()) "scripts/benchmark_bootstrap.sh"
                [
                  "--workspace";
                  workspace;
                  "--json";
                ]
            in
            assert_int_equal 0 benchmark.status
              "the bootstrap benchmark harness should succeed";
            assert_string_contains ~needle:"\"workspace\": " benchmark.output
              "benchmark JSON should record the measured workspace";
            assert_string_contains ~needle:"\"name\": \"cold_app\"" benchmark.output
              "benchmark JSON should include the cold app bootstrap phase";
            assert_string_contains ~needle:"\"name\": \"cold_full\"" benchmark.output
              "benchmark JSON should include the cold full bootstrap phase";
            assert_string_contains ~needle:"\"name\": \"warm_app\"" benchmark.output
              "benchmark JSON should include the warm app bootstrap phase")) );
    ( "emits interface-aware and package-aware bootstrap rules",
      (fun () ->
        with_temp_dir "oasis-bootstrap-packages" (fun workspace ->
            write_manifest workspace
              {|
[library.core]
dir = "src"
modules = ["alpha", "beta"]
packages = ["str"]

[executable.demo]
dir = "src"
main = "main"
deps = ["core"]

[test.suite]
dir = "test"
main = "test_main"
deps = ["core"]
|};
            write_source workspace "src/beta.ml"
              {|type t = string let value = "beta"|};
            write_source workspace "src/alpha.mli" {|val render : Beta.t -> string|};
            write_source workspace "src/alpha.ml"
              {|let render value = Str.global_replace (Str.regexp "b") "B" value|};
            write_source workspace "src/main.ml"
              {|let () = print_endline (Alpha.render Beta.value)|};
            write_source workspace "test/test_main.ml"
              {|let () = print_endline (Alpha.render Beta.value)|};
            let makefile = expect_ok (render_bootstrap workspace) in
            assert_string_contains ~needle:"COMMON_PACKAGE_FLAGS := -package str"
              makefile
              "bootstrap generation should derive common package flags from the manifest";
            assert_string_contains ~needle:"APP_PACKAGE_FLAGS := -package str"
              makefile
              "bootstrap generation should propagate library packages into executables";
            assert_string_contains ~needle:"TEST_PACKAGE_FLAGS := -package str"
              makefile
              "bootstrap generation should propagate library packages into tests";
            assert_string_contains ~needle:"APP_LINK_FLAGS := -linkpkg" makefile
              "bootstrap generation should derive link flags from executable packages";
            assert_string_contains
              ~needle:"$(OBJ_DIR)/alpha.cmi: src/alpha.mli $(BOOTSTRAP_MK) $(OBJ_DIR)/beta.$(OBJ_EXT) | $(OBJ_DIR)"
              makefile
              "bootstrap generation should compile interfaces before dependent modules";
            assert_string_contains
              ~needle:"$(OBJ_DIR)/alpha.$(OBJ_EXT): src/alpha.ml $(BOOTSTRAP_MK) $(OBJ_DIR)/alpha.cmi $(OBJ_DIR)/beta.$(OBJ_EXT) | $(OBJ_DIR)"
              makefile
              "bootstrap generation should make object files depend on generated interfaces";
            assert_string_contains
              ~needle:"$(call BOOTSTRAP_TOOL_CMD,$(APP_PACKAGE_FLAGS)) $(OCAMLFLAGS) -I $(OBJ_DIR) $(APP_LINK_FLAGS) -o $@ $(APP_OBJS)"
              makefile
              "bootstrap generation should link through the package-aware driver")) );
    ( "builds profile-aware bootstrap outputs through actions, preprocessors, and ppx",
      (fun () ->
        with_temp_dir "oasis-bootstrap-transforms" (fun workspace ->
            write_manifest workspace
              {|
[defaults]
profile = "release"

[profile.release]
compile_flags = ["-w", "+a"]
env = ["BUILD_PROFILE=release"]

[action.generate_version]
argv = ["./tools/generate.sh"]
cwd = "."
deps = ["config/version.txt"]
outputs = ["version.ml"]
sandbox = "target"

[preprocess.expand]
argv = ["./tools/expand.sh"]
deps = ["config/banner.txt"]

[ppx.rewrite]
argv = ["./ppx/rewrite.exe"]
deps = ["ppx/message.txt"]

[library.core]
dir = "lib"
modules = ["core", "version"]
actions = ["generate_version"]
preprocess = ["expand"]
ppx = ["rewrite"]

[executable.demo]
dir = "app"
main = "main"
deps = ["core"]
preprocess = ["expand"]
ppx = ["rewrite"]

[test.suite]
dir = "test"
main = "test_main"
deps = ["core"]
preprocess = ["expand"]
ppx = ["rewrite"]
|};
            write_source workspace "config/version.txt" "action";
            write_source workspace "config/banner.txt" "banner";
            write_source workspace "ppx/message.txt" "ppx";
            ignore
              (write_executable workspace "tools/generate.sh"
                 "#!/bin/sh\nset -eu\nversion=$(cat config/version.txt)\nprintf 'let value = \"%s\"\\n' \"$version\" > lib/version.ml\n");
            ignore
              (write_executable workspace "tools/expand.sh"
                 "#!/bin/sh\nset -eu\nbanner=$(cat config/banner.txt)\nsed \"s/@@PROFILE@@/${BUILD_PROFILE}/g; s/@@BANNER@@/${banner}/g\"\n");
            let _ppx_binary =
              Test_build.compile_ppx workspace "ppx/rewrite.ml"
                {|
open Ast_helper
open Ast_mapper
open Parsetree

let replacement () =
  let channel = open_in "ppx/message.txt" in
  Fun.protect
    ~finally:(fun () -> close_in_noerr channel)
    (fun () -> input_line channel)

let expr mapper expression =
  match expression.pexp_desc with
  | Pexp_constant
      { pconst_desc = Pconst_string ("ppx-marker", _, delimiter); pconst_loc = loc } ->
      Exp.constant
        {
          pconst_desc = Pconst_string (replacement (), loc, delimiter);
          pconst_loc = loc;
        }
  | _ -> default_mapper.expr mapper expression

let () =
  run_main (fun _argv -> { default_mapper with expr })
|}
                "ppx/rewrite.exe"
            in
            write_source workspace "lib/core.ml"
              {|let message = "@@PROFILE@@:@@BANNER@@:" ^ Version.value ^ ":" ^ "ppx-marker"|};
            write_source workspace "app/main.ml"
              {|let () = print_endline Core.message|};
            write_source workspace "test/test_main.ml"
              {|let () = print_endline Core.message|};
            let makefile =
              expect_ok (render_bootstrap ~profile:"release" workspace)
            in
            assert_string_contains
              ~needle:"# Bootstrap profile: release"
              makefile
              "bootstrap generation should record the resolved profile";
            assert_string_contains ~needle:"COMMON_SEED_REUSE := yes" makefile
              "bootstrap generation should keep shared seed reuse available when the requested bootstrap profile matches the seed profile";
            assert_string_contains
              ~needle:"COMMON_COMPILE_FLAGS := -w +a"
              makefile
              "bootstrap generation should surface profile compile flags in compile rules";
            assert_string_contains
              ~needle:"BUILD_PROFILE='release'"
              makefile
              "bootstrap generation should surface profile environment bindings in compile rules";
            assert_string_contains ~needle:"-ppx" makefile
              "bootstrap generation should include ppx invocations in compile flags";
            assert_string_contains
              ~needle:"ppx/rewrite.exe"
              makefile
              "bootstrap generation should resolve ppx tool paths into the makefile";
            assert_string_contains
              ~needle:"_bootstrap/materialized/release/library-core/preprocessed/version.ml"
              makefile
              "bootstrap generation should compile transformed action outputs from the materialized bootstrap tree";
            write_bootstrap_driver workspace makefile;
            let build =
              run_make ~cwd:workspace [ "_bootstrap/bin/demo"; "_bootstrap/bin/suite" ]
            in
            assert_int_equal 0 build.status
              ("bootstrap makefiles should build transformed executables and tests\n"
             ^ build.output);
            assert_file_exists (Filename.concat workspace "_bootstrap/bin/demo");
            assert_file_exists (Filename.concat workspace "_bootstrap/bin/suite");
            let demo =
              Process.run_capture ~cwd:workspace "./_bootstrap/bin/demo" []
            in
            let suite =
              Process.run_capture ~cwd:workspace "./_bootstrap/bin/suite" []
            in
            assert_int_equal 0 demo.status
              "the bootstrap-built executable should run successfully";
            assert_int_equal 0 suite.status
              "the bootstrap-built test should run successfully";
            assert_string_equal "release:banner:action:ppx\n" demo.output
              "actions, preprocessors, ppx, and profile env should affect bootstrap-built executables";
            assert_string_equal "release:banner:action:ppx\n" suite.output
              "actions, preprocessors, ppx, and profile env should affect bootstrap-built tests")) );
    ( "allows executable-only bootstrap generation without scanning broken tests",
      (fun () ->
        with_temp_dir "oasis-bootstrap-app-only" (fun workspace ->
            write_manifest workspace
              {|
[library.core]
dir = "lib"
modules = ["core"]

[executable.demo]
dir = "app"
main = "main"
deps = ["core"]

[test.broken]
dir = "test"
main = "main"
deps = ["core"]
|};
            write_source workspace "lib/core.ml" {|let message = "app-scope"|};
            write_source workspace "app/main.ml"
              {|let () = print_endline Core.message|};
            write_source workspace "test/main.ml" {|let () = this is broken|};
            let makefile =
              expect_ok
                (render_bootstrap ~scope:Bootstrap.Executable_only workspace)
            in
            assert_string_not_contains ~needle:"TEST_OBJS" makefile
              "app-only bootstrap generation should not emit test object lists";
            assert_string_not_contains ~needle:"test/main.ml" makefile
              "app-only bootstrap generation should ignore broken test sources";
            write_bootstrap_driver workspace makefile;
            let build = run_make ~cwd:workspace [ "_bootstrap/bin/demo" ] in
            assert_int_equal 0 build.status
              "app-only bootstrap generation should still build the executable";
            assert_string_not_contains ~needle:"test/main.ml" build.output
              "app-only bootstrap builds should not compile broken test sources")) );
    ( "rejects bootstrap manifests without exactly one executable and test",
      (fun () ->
        with_temp_dir "oasis-bootstrap-missing" (fun workspace ->
            write_manifest workspace
              {|
[library.core]
dir = "src"
modules = ["core"]

[executable.demo]
dir = "src"
main = "main"
|};
            write_source workspace "src/core.ml" {|let value = 1|};
            write_source workspace "src/main.ml" {|let () = ignore Core.value|};
            let error = expect_error (render_bootstrap workspace) in
            assert_string_contains ~needle:"exactly one test target" error
              "bootstrap generation should fail clearly when a test target is missing")) );
    ( "rejects duplicate module stems across bootstrap groups before generating rules",
      (fun () ->
        with_temp_dir "oasis-bootstrap-collisions" (fun workspace ->
            write_manifest workspace
              {|
[library.core]
dir = "lib"
modules = ["shared"]

[executable.demo]
dir = "app"
main = "main"
modules = ["shared"]
deps = ["core"]

[test.suite]
dir = "test"
main = "main"
deps = ["core"]
|};
            write_source workspace "lib/shared.ml" {|let value = "library"|};
            write_source workspace "app/shared.ml" {|let value = "app"|};
            write_source workspace "app/main.ml" {|let () = print_endline Shared.value|};
            write_source workspace "test/main.ml" {|let () = print_endline Shared.value|};
            let error = expect_error (render_bootstrap workspace) in
            assert_string_contains
              ~needle:"bootstrap manifest reuses module stems in the shared _bootstrap/obj directory"
              error
              "bootstrap generation should reject colliding object names early";
            assert_string_contains ~needle:"shared ->" error
              "bootstrap generation should identify the colliding module stem";
            assert_string_contains ~needle:"library 'core' (lib/shared.ml)" error
              "bootstrap generation should identify the first colliding owner";
            assert_string_contains ~needle:"executable 'demo' (app/shared.ml)" error
              "bootstrap generation should identify the second colliding owner")) );
  ]
