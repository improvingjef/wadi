open Test_support

let render_bootstrap workspace =
  Bootstrap.render_makefile ~manifest_path:(manifest_path workspace)

let write_source = write_workspace_file

let cases =
  [
    ( "derives bootstrap object lists and ordered rules from the workspace model",
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
              ~needle:"$(OBJ_DIR)/alpha.$(OBJ_EXT): src/alpha.ml $(OBJ_DIR)/beta.$(OBJ_EXT) | $(OBJ_DIR)"
              makefile
              "bootstrap generation should emit ordered common dependencies";
            assert_string_contains
              ~needle:"$(OBJ_DIR)/main.$(OBJ_EXT): src/main.ml $(OBJ_DIR)/cli.$(OBJ_EXT) | $(OBJ_DIR)"
              makefile
              "bootstrap generation should chain executable modules";
            assert_string_contains
              ~needle:"$(BIN_DIR)/demo: $(APP_OBJS) | $(BIN_DIR)"
              makefile
              "bootstrap generation should emit the executable link rule";
            assert_string_contains
              ~needle:"$(BIN_DIR)/suite: $(TEST_OBJS) | $(BIN_DIR)"
              makefile
              "bootstrap generation should emit the test link rule")) );
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
              ~needle:"$(OBJ_DIR)/alpha.cmi: src/alpha.mli $(OBJ_DIR)/beta.$(OBJ_EXT) | $(OBJ_DIR)"
              makefile
              "bootstrap generation should compile interfaces before dependent modules";
            assert_string_contains
              ~needle:"$(OBJ_DIR)/alpha.$(OBJ_EXT): src/alpha.ml $(OBJ_DIR)/alpha.cmi $(OBJ_DIR)/beta.$(OBJ_EXT) | $(OBJ_DIR)"
              makefile
              "bootstrap generation should make object files depend on generated interfaces";
            assert_string_contains
              ~needle:"$(call BOOTSTRAP_TOOL_CMD,$(APP_PACKAGE_FLAGS)) $(OCAMLFLAGS) -I $(OBJ_DIR) $(APP_LINK_FLAGS) -o $@ $(APP_OBJS)"
              makefile
              "bootstrap generation should link through the package-aware driver")) );
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
