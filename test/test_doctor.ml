open Test_support

let write_source workspace relative_path contents =
  Fs.write_file (Filename.concat workspace relative_path) contents

let write_executable workspace relative_path contents =
  let path = Filename.concat workspace relative_path in
  Fs.write_file path contents;
  Unix.chmod path 0o755;
  path

let write_fake_compiler workspace relative_path ~stdlib_dir =
  write_executable workspace relative_path
    (Printf.sprintf
       "#!/bin/sh\n\
        set -eu\n\
        case \"${1-}\" in\n\
        \  -version)\n\
        \    printf '5.4.0\\n'\n\
        \    ;;\n\
        \  -where)\n\
        \    printf '%s\\n'\n\
        \    ;;\n\
        \  *)\n\
        \    echo unexpected invocation >&2\n\
        \    exit 2\n\
        \    ;;\n\
        esac\n"
       stdlib_dir)

let write_fake_ocamlfind workspace relative_path package_root =
  write_executable workspace relative_path
    (Printf.sprintf
       "#!/bin/sh\n\
        set -eu\n\
        if [ \"$#\" -ge 2 ] && [ \"$1\" = \"printconf\" ] && [ \"$2\" = \"path\" ]; \
        then\n\
        \  printf '%s\\n'\n\
        else\n\
        \  echo unexpected invocation >&2\n\
        \  exit 2\n\
        fi\n"
       package_root)

let generated_release_artifacts =
  [
    ("docs/cli.md", "cli docs\n");
    ("completions/wadi.bash", "bash completion\n");
    ("completions/_wadi", "zsh completion\n");
    ("completions/wadi.fish", "fish completion\n");
    ("package/share/doc/wadi/cli.md", "cli docs\n");
    ("package/share/bash-completion/completions/wadi", "bash completion\n");
    ("package/share/zsh/site-functions/_wadi", "zsh completion\n");
    ("package/share/fish/vendor_completions.d/wadi.fish", "fish completion\n");
  ]

let generated_release_metadata =
  [
    ("wadi.opam", "opam metadata\n");
    ("Formula/wadi.rb", "formula metadata\n");
    ("dist/release-assets.json", "{\"schema_version\":1}\n");
  ]

let write_generated_assets workspace =
  List.iter
    (fun (relative_path, contents) ->
      Fs.write_file (Filename.concat workspace relative_path) contents)
    (generated_release_artifacts @ generated_release_metadata)

let setup_generated_asset_workspace workspace =
  write_manifest workspace {|
[executable.demo]
dir = "app"
main = "main"
|};
  write_source workspace "app/main.ml" {|let () = print_endline "demo"|};
  write_generated_assets workspace;
  ignore
    (write_executable workspace "scripts/generate_release_artifacts.sh"
       {|
#!/bin/sh
set -eu
OUTPUT_DIR=.
while [ $# -gt 0 ]; do
  case "$1" in
    --output-dir)
      OUTPUT_DIR=$2
      shift 2
      ;;
    *)
      echo "unexpected option: $1" >&2
      exit 2
      ;;
  esac
done
mkdir -p \
  "$OUTPUT_DIR/docs" \
  "$OUTPUT_DIR/completions" \
  "$OUTPUT_DIR/package/share/doc/wadi" \
  "$OUTPUT_DIR/package/share/bash-completion/completions" \
  "$OUTPUT_DIR/package/share/zsh/site-functions" \
  "$OUTPUT_DIR/package/share/fish/vendor_completions.d"
printf 'cli docs\n' >"$OUTPUT_DIR/docs/cli.md"
printf 'bash completion\n' >"$OUTPUT_DIR/completions/wadi.bash"
printf 'zsh completion\n' >"$OUTPUT_DIR/completions/_wadi"
printf 'fish completion\n' >"$OUTPUT_DIR/completions/wadi.fish"
cp "$OUTPUT_DIR/docs/cli.md" "$OUTPUT_DIR/package/share/doc/wadi/cli.md"
cp "$OUTPUT_DIR/completions/wadi.bash" \
  "$OUTPUT_DIR/package/share/bash-completion/completions/wadi"
cp "$OUTPUT_DIR/completions/_wadi" \
  "$OUTPUT_DIR/package/share/zsh/site-functions/_wadi"
cp "$OUTPUT_DIR/completions/wadi.fish" \
  "$OUTPUT_DIR/package/share/fish/vendor_completions.d/wadi.fish"
|});
  ignore
    (write_executable workspace "scripts/generate_packaging_manifests.sh"
       {|
#!/bin/sh
set -eu
OUTPUT_DIR=.
SOURCE_ARCHIVE_DIR=
ASSET_INDEX_OUTPUT=
while [ $# -gt 0 ]; do
  case "$1" in
    --output-dir)
      OUTPUT_DIR=$2
      shift 2
      ;;
    --source-archive-dir)
      SOURCE_ARCHIVE_DIR=$2
      shift 2
      ;;
    --asset-index-output)
      ASSET_INDEX_OUTPUT=$2
      shift 2
      ;;
    *)
      echo "unexpected option: $1" >&2
      exit 2
      ;;
  esac
done
mkdir -p "$OUTPUT_DIR/Formula"
if [ -n "$SOURCE_ARCHIVE_DIR" ]; then
  mkdir -p "$SOURCE_ARCHIVE_DIR"
  printf 'source archive\n' >"$SOURCE_ARCHIVE_DIR/source.tar.gz"
fi
printf 'opam metadata\n' >"$OUTPUT_DIR/wadi.opam"
printf 'formula metadata\n' >"$OUTPUT_DIR/Formula/wadi.rb"
if [ -n "$ASSET_INDEX_OUTPUT" ]; then
  mkdir -p "$(dirname "$ASSET_INDEX_OUTPUT")"
  printf '{"schema_version":1}\n' >"$ASSET_INDEX_OUTPUT"
fi
|})

let cases =
  [
    ( "validates a healthy workspace and current lock snapshot",
      fun () ->
        with_fixture "hello" (fun workspace ->
            let lock = run_wadi ~cwd:workspace [ "lock" ] in
            assert_int_equal 0 lock.status
              "lock should succeed before doctor checks a strict snapshot";
            let doctor = run_wadi ~cwd:workspace [ "doctor"; "--locked" ] in
            assert_int_equal 0 doctor.status
              "doctor should pass for a healthy locked workspace";
            assert_string_contains ~needle:"manifest: pass" doctor.output
              "doctor should report manifest validation";
            assert_string_contains ~needle:"graph: pass" doctor.output
              "doctor should report dependency-graph validation";
            assert_string_contains ~needle:"toolchain: pass" doctor.output
              "doctor should report toolchain health";
            assert_string_contains ~needle:"packages: pass" doctor.output
              "doctor should report package resolution health";
            assert_string_contains ~needle:"lock: pass" doctor.output
              "doctor should report lock validation success";
            assert_string_contains ~needle:"Summary: pass=5 warn=0 fail=0" doctor.output
              "doctor should summarize all successful checks") );
    ( "reports missing external packages directly",
      fun () ->
        with_temp_dir "wadi-doctor-packages" (fun workspace ->
            write_manifest workspace
              {|
[library.core]
dir = "lib"
modules = ["core"]
packages = ["definitely_missing_wadi_pkg"]

[executable.demo]
dir = "app"
main = "main"
deps = ["core"]
|};
            write_source workspace "lib/core.ml" {|let value = "core"|};
            write_source workspace "app/main.ml" {|let () = print_endline Core.value|};
            let doctor = run_wadi ~cwd:workspace [ "doctor"; "demo" ] in
            assert_true (doctor.status <> 0)
              "doctor should fail when required packages cannot be resolved";
            assert_string_contains ~needle:"packages: fail" doctor.output
              "doctor should mark package resolution as failed";
            assert_string_contains
              ~needle:
                "executable 'demo' requires package 'definitely_missing_wadi_pkg' is not \
                 available via ocamlfind"
              doctor.output "doctor should keep the direct package-resolution error") );
    ( "warns about stale lock data by default",
      fun () ->
        with_fixture "hello" (fun workspace ->
            let lock = run_wadi ~cwd:workspace [ "lock" ] in
            assert_int_equal 0 lock.status
              "lock should succeed before simulating lock drift";
            Fs.write_file (Filename.concat workspace "wadi.lock") "{}\n";
            let doctor = run_wadi ~cwd:workspace [ "doctor" ] in
            assert_int_equal 0 doctor.status
              "doctor should warn about stale lock data by default";
            assert_string_contains ~needle:"lock: warn" doctor.output
              "doctor should downgrade lock drift to a warning by default";
            assert_string_contains ~needle:"failed to read" doctor.output
              "doctor should surface the lock parsing error in its warning output") );
    ( "fails on stale lock data when --locked is requested",
      fun () ->
        with_fixture "hello" (fun workspace ->
            let lock = run_wadi ~cwd:workspace [ "lock" ] in
            assert_int_equal 0 lock.status
              "lock should succeed before simulating a strict lock failure";
            Fs.write_file (Filename.concat workspace "wadi.lock") "{}\n";
            let doctor = run_wadi ~cwd:workspace [ "doctor"; "--locked" ] in
            assert_true (doctor.status <> 0)
              "doctor --locked should fail on stale or unreadable lock data";
            assert_string_contains ~needle:"lock: fail" doctor.output
              "doctor should upgrade lock drift to a failure with --locked";
            assert_string_contains ~needle:"Refresh the snapshot with `wadi lock`."
              doctor.output "doctor should keep the actionable lock refresh guidance") );
    ( "passes generated-asset checks when committed outputs are current",
      fun () ->
        with_temp_dir "wadi-doctor-generated-assets-pass" (fun workspace ->
            setup_generated_asset_workspace workspace;
            let lock = run_wadi ~cwd:workspace [ "lock" ] in
            assert_int_equal 0 lock.status
              "lock should succeed before doctor checks generated assets";
            let doctor = run_wadi ~cwd:workspace [ "doctor"; "--locked" ] in
            assert_int_equal 0 doctor.status
              "doctor should pass when generated assets are current";
            assert_string_contains ~needle:"generated-assets: pass" doctor.output
              "doctor should report generated asset validation";
            assert_string_contains ~needle:"release-artifacts: current" doctor.output
              "doctor should confirm release artifact outputs are current";
            assert_string_contains ~needle:"release-metadata: current" doctor.output
              "doctor should confirm release metadata outputs are current";
            assert_string_contains ~needle:"Summary: pass=6 warn=0 fail=0" doctor.output
              "doctor should include the generated-asset check in the passing summary") );
    ( "warns when generated assets drift from their generators",
      fun () ->
        with_temp_dir "wadi-doctor-generated-assets-warn" (fun workspace ->
            setup_generated_asset_workspace workspace;
            let lock = run_wadi ~cwd:workspace [ "lock" ] in
            assert_int_equal 0 lock.status
              "lock should succeed before doctor checks generated-asset drift";
            Fs.write_file (Filename.concat workspace "docs/cli.md") "drifted docs\n";
            let doctor = run_wadi ~cwd:workspace [ "doctor"; "--locked" ] in
            assert_int_equal 0 doctor.status
              "doctor should warn, not fail, on generated-asset drift";
            assert_string_contains ~needle:"generated-assets: warn" doctor.output
              "doctor should downgrade generated-asset drift to a warning";
            assert_string_contains ~needle:"docs/cli.md drifted" doctor.output
              "doctor should report which generated asset drifted";
            assert_string_contains
              ~needle:"Refresh generated assets with `make sync-generated`." doctor.output
              "doctor should include the maintenance command for refreshing drifted \
               assets";
            assert_string_contains ~needle:"Summary: pass=5 warn=1 fail=0" doctor.output
              "doctor should summarize generated-asset drift as a warning") );
    ( "fails when ocamlfind package roots do not match the compiler toolchain",
      fun () ->
        with_temp_dir "wadi-doctor-mixed-toolchain" (fun workspace ->
            write_manifest workspace
              {|
[executable.demo]
dir = "app"
main = "main"
|};
            write_source workspace "app/main.ml" {|let () = print_endline "demo"|};
            let stdlib_dir = Filename.concat workspace "fake-switch/lib/ocaml" in
            let ocamlc = write_fake_compiler workspace "bin/ocamlc-fake" ~stdlib_dir in
            let ocamlopt =
              write_fake_compiler workspace "bin/ocamlopt-fake" ~stdlib_dir
            in
            let ocamlfind =
              write_fake_ocamlfind workspace "bin/ocamlfind-homebrew"
                "/opt/homebrew/lib/ocaml"
            in
            let doctor =
              with_env "OCAMLC" ocamlc (fun () ->
                  with_env "OCAMLOPT" ocamlopt (fun () ->
                      with_env "OCAMLFIND" ocamlfind (fun () ->
                          run_wadi ~cwd:workspace [ "doctor"; "demo" ])))
            in
            assert_true (doctor.status <> 0)
              "doctor should fail for an inconsistent OCaml toolchain";
            assert_string_contains ~needle:"toolchain: fail" doctor.output
              "doctor should mark the toolchain check as failed";
            assert_string_contains
              ~needle:
                ("ocamlfind package roots (/opt/homebrew/lib/ocaml) do not match \
                  compiler stdlib root "
                ^ Filename.concat workspace "fake-switch/lib")
              doctor.output
              "doctor should preserve the direct mismatch explanation";
            assert_string_contains
              ~needle:
                ("put " ^ Filename.concat workspace "fake-switch/bin"
               ^ " ahead of other OCaml installations in PATH")
              doctor.output
              "doctor should include the PATH repair guidance") );
  ]
