open Test_support

let load_manifest contents =
  with_temp_dir "oasis-manifest" (fun workspace ->
      write_manifest workspace contents;
      Manifest.load (manifest_path workspace))

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
  ]
