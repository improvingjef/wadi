(* fuzz_explain.ml — Fuzz fingerprint comparison logic. *)

let raw_bytes = Crowbar.map [ Crowbar.bytes ] (fun b -> b)

let fingerprint_prefix =
  Crowbar.choose [
    Crowbar.const "compiler"; Crowbar.const "backend";
    Crowbar.const "manifest"; Crowbar.const "kind";
    Crowbar.const "target"; Crowbar.const "dir";
    Crowbar.const "main"; Crowbar.const "module";
    Crowbar.const "tool"; Crowbar.const "package";
    Crowbar.const "ml"; Crowbar.const "mli";
    Crowbar.const "dep"; Crowbar.const "";
    Crowbar.map [ Crowbar.bytes ] (fun s ->
      String.map (fun c -> if c = '\n' then '_' else c) s);
  ]

let fingerprint_value =
  Crowbar.choose [
    Crowbar.const "native"; Crowbar.const "bytecode";
    Crowbar.const "abc123"; Crowbar.const "missing";
    Crowbar.const ""; Crowbar.map [ Crowbar.bytes ] (fun s ->
      String.map (fun c -> if c = '\n' then '_' else c) s);
  ]

let fingerprint_line =
  Crowbar.map [ fingerprint_prefix; fingerprint_value ] (fun p v -> p ^ " " ^ v)

let fingerprint =
  Crowbar.map [ Crowbar.list fingerprint_line ] (fun lines ->
    String.concat "\n" lines)

let fingerprint_pair =
  Crowbar.map [ fingerprint; fingerprint ] (fun a b -> (a, b))

let raw_pair =
  Crowbar.map [ raw_bytes; raw_bytes ] (fun a b -> (a, b))

let () =
  Crowbar.add_test ~name:"fingerprint diff does not crash on structured input"
    [ fingerprint ] (fun fp ->
      let lines = String.split_on_char '\n' fp in
      let _ = Explain.changed_fingerprint_lines lines lines in
      let _ = Explain.changed_fingerprint_lines lines [] in
      let _ = Explain.changed_fingerprint_lines [] lines in
      ());

  Crowbar.add_test ~name:"fingerprint diff does not crash on arbitrary bytes"
    [ raw_bytes ] (fun input ->
      let lines = String.split_on_char '\n' input in
      let _ = Explain.changed_fingerprint_lines lines lines in
      let _ = Explain.changed_fingerprint_lines lines [] in
      let _ = Explain.changed_fingerprint_lines [] lines in
      ())
