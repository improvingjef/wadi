open Test_support

let render_bootstrap workspace =
  Bootstrap.render_makefile ~manifest_path:(manifest_path workspace)

let write_source = write_workspace_file

let cases =
  [
    ( "derives bootstrap object lists and chain rules from the workspace model",
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
              ~needle:"COMMON_OBJS := $(OBJ_DIR)/beta.cmx $(OBJ_DIR)/alpha.cmx"
              makefile
              "bootstrap generation should sort common modules by dependencies";
            assert_string_contains
              ~needle:"APP_OBJS := $(COMMON_OBJS) $(OBJ_DIR)/cli.cmx $(OBJ_DIR)/main.cmx"
              makefile
              "bootstrap generation should derive executable object lists";
            assert_string_contains
              ~needle:"TEST_OBJS := $(COMMON_OBJS) $(OBJ_DIR)/test_helper.cmx $(OBJ_DIR)/test_main.cmx"
              makefile
              "bootstrap generation should derive test object lists";
            assert_string_contains
              ~needle:"$(OBJ_DIR)/alpha.cmx: $(OBJ_DIR)/beta.cmx" makefile
              "bootstrap generation should emit ordered common dependencies";
            assert_string_contains
              ~needle:"$(OBJ_DIR)/main.cmx: $(OBJ_DIR)/cli.cmx" makefile
              "bootstrap generation should chain executable modules";
            assert_string_contains
              ~needle:"$(BIN_DIR)/demo: $(APP_OBJS) | $(BIN_DIR)" makefile
              "bootstrap generation should emit the executable link rule";
            assert_string_contains
              ~needle:"$(BIN_DIR)/suite: $(TEST_OBJS) | $(BIN_DIR)" makefile
              "bootstrap generation should emit the test link rule")) );
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
  ]
