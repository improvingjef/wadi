(* fuzz_toolchain.ml — Fuzz backend parsing, PATH splitting,
   and package resolution input handling. *)

let raw_bytes = Crowbar.map [ Crowbar.bytes ] (fun b -> b)

(* Backend request strings *)
let backend_string =
  Crowbar.choose [
    Crowbar.const "auto";
    Crowbar.const "native";
    Crowbar.const "bytecode";
    Crowbar.const "Auto";
    Crowbar.const "NATIVE";
    Crowbar.const "Bytecode";
    Crowbar.const "";
    Crowbar.const "invalid";
    Crowbar.const "ocamlopt";
    Crowbar.const "ocamlc";
    Crowbar.map [ Crowbar.bytes ] (fun s -> s);
  ]

(* PATH-like strings *)
let path_entry =
  Crowbar.choose [
    Crowbar.const "/usr/bin";
    Crowbar.const "/usr/local/bin";
    Crowbar.const "";
    Crowbar.const ".";
    Crowbar.const "/";
    Crowbar.const "relative/path";
    Crowbar.map [ Crowbar.bytes ] (fun s ->
      String.map (fun c -> if c = '\n' then '_' else c) s);
  ]

let path_string =
  Crowbar.map [ Crowbar.list path_entry ] (fun entries ->
    String.concat ":" entries)

let backend_parse_does_not_crash input =
  match Toolchain.parse_backend input with
  | _ -> ()
  | exception Failure _ -> ()
  | exception Invalid_argument _ -> ()

let backend_request_does_not_crash input =
  match Toolchain.parse_backend_request input with
  | _ -> ()
  | exception Failure _ -> ()
  | exception Invalid_argument _ -> ()

let () =
  Crowbar.add_test ~name:"backend parsing does not crash"
    [ backend_string ] backend_parse_does_not_crash;

  Crowbar.add_test ~name:"backend request parsing does not crash"
    [ backend_string ] backend_request_does_not_crash;

  Crowbar.add_test ~name:"backend parsing does not crash on arbitrary bytes"
    [ raw_bytes ] backend_parse_does_not_crash
