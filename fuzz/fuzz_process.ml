(* fuzz_process.ml — Fuzz command rendering and string splitting. *)

let raw_bytes = Crowbar.map [ Crowbar.bytes ] (fun b -> b)

let command_arg =
  Crowbar.choose
    [
      Crowbar.const "echo";
      Crowbar.const "hello world";
      Crowbar.const "";
      Crowbar.const "has\"quotes";
      Crowbar.const "has'single";
      Crowbar.const "has\\backslash";
      Crowbar.const "has\nnewline";
      Crowbar.const "-flag";
      Crowbar.const "--long-flag=value";
      Crowbar.map [ Crowbar.bytes ] (fun s -> s);
    ]

let () =
  Crowbar.add_test ~name:"command rendering does not crash" [ command_arg ] (fun prog ->
      let _ = Process.render ~cwd:"/tmp" ~env:[] prog [] in
      let _ = Process.render ~cwd:"/tmp" ~env:[] prog [ prog ] in
      let _ = Process.render ~cwd:"/tmp" ~env:[] prog [ prog; prog; prog ] in
      ());

  Crowbar.add_test ~name:"command rendering does not crash on arbitrary bytes"
    [ raw_bytes ] (fun input ->
      let _ = Process.render ~cwd:"/tmp" ~env:[] input [] in
      let _ = Process.render ~cwd:input ~env:[] "echo" [ input ] in
      ());

  Crowbar.add_test ~name:"split_once does not crash on arbitrary bytes" [ raw_bytes ]
    (fun input ->
      let _ = String_util.split_once ~on:'=' input in
      let _ = String_util.split_once ~on:':' input in
      let _ = String_util.split_once ~on:'.' input in
      ())
