open Test_support

let write_source workspace relative_path contents =
  Fs.write_file (Filename.concat workspace relative_path) contents

let cases =
  [
    ( "graphs target build order, package paths, and module order",
      (fun () ->
        with_temp_dir "wadi-graph-order" (fun workspace ->
            write_manifest workspace
              {|
workspace = "graph-demo"
version = 1
members = ["packages/core", "packages/app"]

[library.shared]
dir = "shared"
modules = ["shared"]
|};
            write_workspace_file workspace "packages/core/wadi.toml"
              {|
[library.core]
dir = "lib"
modules = ["core"]
deps = ["shared"]
|};
            write_workspace_file workspace "packages/app/wadi.toml"
              {|
[executable.demo]
dir = "app"
main = "main"
modules = ["cli"]
deps = ["core"]
|};
            write_source workspace "shared/shared.ml" {|let value = "shared"|};
            write_source workspace "packages/core/lib/core.ml"
              {|let value = Shared.value|};
            write_source workspace "packages/app/app/cli.ml"
              {|let render () = Core.value|};
            write_source workspace "packages/app/app/main.ml"
              {|let () = print_endline (Cli.render ())|};
            let graph = run_wadi ~cwd:workspace [ "graph"; "demo" ] in
            assert_int_equal 0 graph.status
              "graph should render the selected target closure";
            assert_string_contains ~needle:"Workspace: graph-demo\n" graph.output
              "graph should report the workspace name";
            assert_string_contains ~needle:"Requested-targets: demo\n" graph.output
              "graph should report which targets were requested";
            assert_string_contains ~needle:"1. library shared\n" graph.output
              "graph should start with transitive libraries";
            assert_string_contains
              ~needle:"2. library core (packages/core)\n"
              graph.output
              "graph should surface member package paths for libraries";
            assert_string_contains
              ~needle:"3. executable demo (packages/app)\n"
              graph.output
              "graph should surface member package paths for executables";
            assert_string_contains ~needle:"depends-on: shared\n" graph.output
              "graph should show direct workspace dependencies";
            assert_string_contains ~needle:"module-order: cli, main\n" graph.output
              "graph should show runnable helper modules before the main module")) );
  ]

