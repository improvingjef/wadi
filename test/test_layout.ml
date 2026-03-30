open Test_support

let cases =
  [
    ( "computes library, executable, and test artifact paths",
      (fun () ->
        let workspace = "/tmp/wadi-layout" in
        assert_string_equal "/tmp/wadi-layout/_wadi"
          (Layout.artifact_root workspace)
          "artifact root should live under the workspace";
        assert_string_equal "/tmp/wadi-layout/_wadi/build/default"
          (Layout.build_root workspace)
          "build root should be stable";
        assert_string_equal
          "/tmp/wadi-layout/_wadi/build/default/lib/core/libcore.cmxa"
          (Layout.library_archive workspace "core")
          "library archives should live in the lib target root";
        assert_string_equal
          "/tmp/wadi-layout/_wadi/build/default/lib/core/libcore.cma"
          (Layout.library_archive_for_backend workspace Toolchain.Bytecode "core")
          "bytecode archives should live next to native archives";
        assert_string_equal "/tmp/wadi-layout/_wadi/build/default/exe/app/app"
          (Layout.executable_binary workspace "app")
          "executables should use the exe target root";
        assert_string_equal
          "/tmp/wadi-layout/_wadi/build/default/test/unit/unit"
          (Layout.test_binary workspace "unit")
          "tests should use the test target root";
        assert_string_equal "/tmp/wadi-layout/_wadi/build/default/exe/app/.wadi-stamp"
          (Layout.stamp_path (Layout.executable_out_dir workspace "app"))
          "target stamps should live next to the target artifacts";
        assert_string_equal
          "/tmp/wadi-layout/_wadi/build/default/exe/app/.wadi-explain"
          (Layout.explain_path (Layout.executable_out_dir workspace "app"))
          "target explain reports should live next to the target artifacts";
        assert_string_equal "/tmp/wadi-layout/_wadi/build/default/repl/core.top"
          (Layout.repl_binary workspace "core")
          "repl binaries should live under a dedicated repl root";
        assert_string_equal "/tmp/wadi-layout/lib/core/META"
          (Layout.install_library_meta_path "/tmp/wadi-layout" "core")
          "installed library META files should live beside staged library artifacts";
        assert_string_equal "/tmp/wadi-layout/share/wadi/demo/install.json"
          (Layout.install_metadata_path "/tmp/wadi-layout" "demo")
          "install metadata should live under the workspace share root";
        assert_string_equal "share/wadi/demo/wadi.toml"
          (Layout.relative_install_manifest_copy_path "demo")
          "manifest copies should have a stable relative install path")) ;
  ]
