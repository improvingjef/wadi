open Test_support

let load_manifest contents =
  with_temp_dir "oasis-manifest" (fun workspace ->
      write_manifest workspace contents;
      Manifest.load (manifest_path workspace))

let env_value name bindings =
  match List.find_opt (fun (binding_name, _) -> binding_name = name) bindings with
  | Some (_, value) -> value
  | None -> fail (Printf.sprintf "missing env binding %s" name)

let cases =
  [
    ( "parses a minimal workspace",
      (fun () ->
        let workspace =
          expect_ok
            (load_manifest
               {|
workspace = "demo"
version = 1

[library.core]
dir = "lib"
modules = ["core"]

[executable.app]
dir = "app"
main = "main"
deps = ["core"]
|})
        in
        assert_int_equal 2 (List.length workspace.Manifest.targets)
          "expected one library and one executable";
        match workspace.Manifest.targets with
        | [ Manifest.Library library; Manifest.Executable executable ] ->
            assert_string_equal "core" library.name
              "library name should come from the section path";
            assert_string_equal "app" executable.name
              "executable name should come from the section path"
        | _ -> fail "unexpected target layout in parsed workspace")) ;
    ( "rejects duplicate keys",
      (fun () ->
        let error =
          expect_error
            (load_manifest
               {|
[library.core]
dir = "lib"
dir = "src"
modules = ["core"]
|})
        in
        assert_string_contains ~needle:"duplicate key 'dir'" error
          "duplicate keys should be rejected")) ;
    ( "detects dependency cycles",
      (fun () ->
        let workspace =
          expect_ok
            (load_manifest
               {|
[library.alpha]
dir = "alpha"
modules = ["alpha"]
deps = ["beta"]

[library.beta]
dir = "beta"
modules = ["beta"]
deps = ["alpha"]
|})
        in
        let error = expect_error (Builder.resolve_build_order workspace []) in
        assert_string_contains ~needle:"dependency cycle detected" error
          "cycles should be reported")) ;
    ( "rejects executable dependencies",
      (fun () ->
        let workspace =
          expect_ok
            (load_manifest
               {|
[executable.tool]
dir = "tool"
main = "main"

[library.core]
dir = "core"
modules = ["core"]
deps = ["tool"]
|})
        in
        let error = expect_error (Builder.resolve_build_order workspace []) in
        assert_string_contains ~needle:"depends on executable" error
          "libraries should not be allowed to depend on executables")) ;
    ( "rejects test dependencies",
      (fun () ->
        let workspace =
          expect_ok
            (load_manifest
               {|
[test.alpha]
dir = "alpha"
main = "main"
deps = ["beta"]

[test.beta]
dir = "beta"
main = "main"
|})
        in
        let error = expect_error (Builder.resolve_build_order workspace []) in
        assert_string_contains ~needle:"depends on test 'beta'" error
          "tests should not be allowed to depend on other tests")) ;
    ( "parses test targets",
      (fun () ->
        let workspace =
          expect_ok
            (load_manifest
               {|
[library.core]
dir = "lib"
modules = ["core"]

[test.unit]
dir = "test"
main = "main"
modules = ["helpers"]
deps = ["core"]
|})
        in
        assert_int_equal 2 (List.length workspace.Manifest.targets)
          "expected one library and one test";
        match workspace.Manifest.targets with
        | [ Manifest.Library library; Manifest.Test test ] ->
            assert_string_equal "core" library.name
              "library name should come from the section path";
            assert_string_equal "unit" test.name
              "test name should come from the section path"
        | _ -> fail "unexpected target layout in parsed workspace")) ;
    ( "parses external package declarations",
      (fun () ->
        let workspace =
          expect_ok
            (load_manifest
               {|
[library.patterns]
dir = "lib"
modules = ["patterns"]
packages = ["str", "compiler-libs.common"]

[executable.demo]
dir = "app"
main = "main"
packages = ["unix"]
deps = ["patterns"]
|})
        in
        match workspace.Manifest.targets with
        | [ Manifest.Library library; Manifest.Executable executable ] ->
            assert_string_equal "str" (List.nth library.packages 0)
              "library packages should preserve manifest order";
            assert_string_equal "compiler-libs.common"
              (List.nth library.packages 1)
              "package names with dots should be accepted";
            assert_string_equal "unix" (List.hd executable.packages)
              "executables should parse direct package requirements"
        | _ -> fail "unexpected target layout in parsed workspace")) ;
    ( "parses defaults, tools, and profile target overrides",
      (fun () ->
        let workspace =
          expect_ok
            (load_manifest
               {|
[defaults]
profile = "release"
actions = ["generate"]
preprocess = ["expand"]
ppx = ["rewrite"]
compile_flags = ["-principal"]
env = ["MODE=default"]
sandbox = "workspace"

[action.generate]
argv = ["./scripts/generate.sh"]
deps = ["scripts/template.txt"]
outputs = ["version.ml"]
stdin = "hello"

[preprocess.expand]
argv = ["./scripts/expand.sh"]
cwd = "scripts"
env = ["MODE=pre"]

[ppx.rewrite]
argv = ["./ppx/rewrite.exe"]

[profile.release]
compile_flags = ["-strict-sequence"]
env = ["MODE=release", "PROFILE=release"]

[profile.release.executable.demo]
compile_flags = ["-rectypes"]
link_flags = ["-custom"]
env = ["MODE=demo"]
sandbox = "target"

[executable.demo]
dir = "app"
main = "main"
|})
        in
        assert_string_equal "release" workspace.Manifest.defaults.default_profile
          "defaults should define the implicit profile name";
        assert_int_equal 1 (List.length workspace.Manifest.actions)
          "actions should be collected separately from targets";
        assert_int_equal 1 (List.length workspace.Manifest.preprocessors)
          "preprocessors should be parsed into their own registry";
        assert_int_equal 1 (List.length workspace.Manifest.ppx_tools)
          "ppx tools should be parsed into their own registry";
        let target =
          match workspace.Manifest.targets with
          | [ Manifest.Executable executable ] ->
              Manifest.Executable executable
          | _ -> fail "expected a single executable target"
        in
        let options =
          expect_ok (Manifest.resolve_target_options workspace "release" target)
        in
        assert_string_equal "generate" (List.hd options.Manifest.actions)
          "default actions should flow into resolved target options";
        assert_string_equal "expand" (List.hd options.Manifest.preprocess)
          "default preprocessors should flow into resolved target options";
        assert_string_equal "rewrite" (List.hd options.Manifest.ppx)
          "default ppx tools should flow into resolved target options";
        assert_string_equal "-principal" (List.nth options.Manifest.compile_flags 0)
          "default compile flags should be preserved";
        assert_string_equal "-strict-sequence"
          (List.nth options.Manifest.compile_flags 1)
          "profile compile flags should append after defaults";
        assert_string_equal "-rectypes"
          (List.nth options.Manifest.compile_flags 2)
          "profile target overrides should append after profile flags";
        assert_string_equal "-custom" (List.hd options.Manifest.link_flags)
          "profile target link overrides should be applied";
        assert_string_equal "demo" (env_value "MODE" options.Manifest.env)
          "target env overrides should win over profile and default env";
        assert_string_equal "release" (env_value "PROFILE" options.Manifest.env)
          "profile env should be retained when not overridden";
        match options.Manifest.sandbox with
        | Some Manifest.Target -> ()
        | Some Manifest.Workspace ->
            fail "target override sandbox should replace the default sandbox"
        | None -> fail "resolved options should keep the target sandbox override")) ;
    ( "rejects invalid environment bindings",
      (fun () ->
        let error =
          expect_error
            (load_manifest
               {|
[defaults]
env = ["BROKEN_ENV"]
|})
        in
        assert_string_contains ~needle:"NAME=value" error
          "environment bindings should require NAME=value syntax")) ;
  ]
