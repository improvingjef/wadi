(* fuzz_cli.ml — AFL-powered fuzzer for the wadi CLI argument parser.

   Generates arbitrary argument vectors and feeds them through the CLI
   dispatch. The parser must never crash — returning errors or printing
   usage is fine.
*)

(* CLI dispatch is in Cli.run which calls parse_*_args functions.
   We can't call Cli.run directly (it exits the process), so we
   fuzz the individual parse functions via Cli.dispatch_for_testing
   if exposed, or call the CLI binary with arguments. *)

let cli_arg =
  Crowbar.choose [
    Crowbar.const "--workspace";
    Crowbar.const "--profile";
    Crowbar.const "--backend";
    Crowbar.const "--verbose";
    Crowbar.const "-v";
    Crowbar.const "--help";
    Crowbar.const "--locked";
    Crowbar.const "--warn-locked";
    Crowbar.const "--current";
    Crowbar.const "--json";
    Crowbar.const "--stdout";
    Crowbar.const "--force";
    Crowbar.const "--prefix";
    Crowbar.const "--destdir";
    Crowbar.const "--output";
    Crowbar.const "--poll-ms";
    Crowbar.const "--debounce-ms";
    Crowbar.const "--max-runs";
    Crowbar.const "--keep-going";
    Crowbar.const "--warmup";
    Crowbar.const "--iterations";
    Crowbar.const "--bare";
    Crowbar.const "--member";
    Crowbar.const "--";
    Crowbar.const "auto";
    Crowbar.const "native";
    Crowbar.const "bytecode";
    Crowbar.const "bash";
    Crowbar.const "zsh";
    Crowbar.const "fish";
    Crowbar.const "build";
    Crowbar.const "run";
    Crowbar.const "test";
    Crowbar.const "clean";
    Crowbar.const "explain";
    Crowbar.const "install";
    Crowbar.const "toolchain";
    Crowbar.const "graph";
    Crowbar.const "deps";
    Crowbar.const "watch";
    Crowbar.const "repl";
    Crowbar.const "migrate";
    Crowbar.const "completion";
    Crowbar.const "docs";
    Crowbar.const "env";
    Crowbar.const "init";
    Crowbar.const "lock";
    Crowbar.const "bench";
    Crowbar.const "vendor";
    Crowbar.const "doctor";
    Crowbar.const "status";
    Crowbar.map [ Crowbar.bytes ] (fun s -> s);
    Crowbar.map [ Crowbar.int32 ] (fun n -> Int32.to_string n);
    Crowbar.const "";
    Crowbar.const "/tmp";
    Crowbar.const ".";
    Crowbar.const "..";
    Crowbar.const "some_target";
  ]

let arg_list =
  Crowbar.list cli_arg

(* Fuzz the CLI help/dispatch path. We write a minimal manifest so
   the CLI can load it, then exercise argument parsing. *)
let with_temp_workspace f =
  let dir = Filename.temp_file "wadi-fuzz-cli" ".tmp" in
  (try Sys.remove dir with _ -> ());
  Unix.mkdir dir 0o755;
  Fun.protect
    ~finally:(fun () -> try Fs.remove_tree dir with _ -> ())
    (fun () ->
      let manifest = Filename.concat dir "wadi.toml" in
      let oc = open_out manifest in
      output_string oc "workspace = \"fuzz\"\nversion = 1\n\n[library.fuzz]\ndir = \"src\"\nmodules = [\"a\"]\n";
      close_out oc;
      let src = Filename.concat dir "src" in
      Unix.mkdir src 0o755;
      let a_ml = Filename.concat src "a.ml" in
      let oc = open_out a_ml in
      output_string oc "let x = 1\n";
      close_out oc;
      f dir)

(* Test: argument parsing never crashes the process *)
let cli_parse_does_not_crash args =
  with_temp_workspace (fun workspace ->
    let full_args = "--workspace" :: workspace :: args in
    let result =
      Process.run_capture
        (try Sys.getenv "WADI_BIN"
         with Not_found -> "_bootstrap/bin/wadi")
        full_args
    in
    (* Any exit code is fine — 0, 1, 2 all acceptable.
       We only care that it doesn't segfault (signal). *)
    match result.Process.status with
    | 0 | 1 | 2 -> ()
    | n when n > 128 ->
        Crowbar.fail (Printf.sprintf "CLI crashed with signal %d on args: %s"
          (n - 128) (String.concat " " full_args))
    | _ -> ())

let () =
  Crowbar.add_test ~name:"CLI argument parser does not crash"
    [ arg_list ] (fun args ->
      cli_parse_does_not_crash args)
