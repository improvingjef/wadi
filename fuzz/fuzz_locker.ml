(* fuzz_locker.ml — Fuzz the hand-rolled JSON parser in the lock file system.
   This is a high-value target: custom recursive descent JSON parsing. *)

let raw_bytes = Crowbar.map [ Crowbar.bytes ] (fun b -> b)

(* JSON-like structured input *)
let json_char =
  Crowbar.choose
    [
      Crowbar.const '{';
      Crowbar.const '}';
      Crowbar.const '[';
      Crowbar.const ']';
      Crowbar.const '"';
      Crowbar.const ':';
      Crowbar.const ',';
      Crowbar.const ' ';
      Crowbar.const '\n';
      Crowbar.const '\t';
      Crowbar.const '\\';
      Crowbar.const '/';
      Crowbar.const 'n';
      Crowbar.const 't';
      Crowbar.const 'r';
      Crowbar.const 'f';
      Crowbar.const 'a';
      Crowbar.const '0';
      Crowbar.const '-';
      Crowbar.const '.';
      Crowbar.map [ Crowbar.uint8 ] Char.chr;
    ]

let json_string =
  Crowbar.map
    [ Crowbar.list json_char ]
    (fun chars -> String.init (List.length chars) (List.nth chars))

(* Structured JSON objects *)
let json_value_str =
  Crowbar.choose
    [
      Crowbar.map [ Crowbar.bytes ] (fun s ->
          let clean =
            String.map (fun c -> if c = '"' || c = '\\' || c = '\n' then '_' else c) s
          in
          Printf.sprintf "\"%s\"" clean);
      Crowbar.map [ Crowbar.int32 ] (fun n -> Int32.to_string n);
      Crowbar.const "null";
      Crowbar.const "true";
      Crowbar.const "false";
      Crowbar.const "[]";
      Crowbar.const "{}";
    ]

let json_kv =
  Crowbar.map [ Crowbar.bytes; json_value_str ] (fun k v ->
      let clean_k =
        String.map (fun c -> if c = '"' || c = '\\' || c = '\n' then '_' else c) k
      in
      Printf.sprintf "\"%s\": %s" clean_k v)

let json_object =
  Crowbar.map
    [ Crowbar.list json_kv ]
    (fun kvs -> Printf.sprintf "{%s}" (String.concat ", " kvs))

(* Lock file structured format *)
let lock_file_json =
  Crowbar.map [ Crowbar.bytes; Crowbar.bytes ] (fun version manifest_hash ->
      let clean s =
        String.map (fun c -> if c = '"' || c = '\\' || c = '\n' then '_' else c) s
      in
      Printf.sprintf
        {|{"format_version": 1, "manifest_digest": "%s", "compiler_version": "%s", "backend": "native", "stdlib": "/lib/ocaml", "targets": {}, "toolchain": {}}|}
        (clean manifest_hash) (clean version))

let with_temp_file prefix contents f =
  let path = Filename.temp_file prefix ".json" in
  Fun.protect
    ~finally:(fun () -> try Sys.remove path with _ -> ())
    (fun () ->
      let oc = open_out_bin path in
      output_string oc contents;
      close_out oc;
      f path)

let load_does_not_crash input =
  with_temp_file "wadi-fuzz-lock" input (fun path ->
      match Locker.load_snapshot path with
      | Ok _ -> ()
      | Error _ -> ()
      | exception Failure _ -> ()
      | exception Invalid_argument _ -> ()
      | exception Not_found -> ())

let () =
  Crowbar.add_test ~name:"lock JSON parser does not crash on arbitrary bytes"
    [ raw_bytes ] load_does_not_crash;

  Crowbar.add_test ~name:"lock JSON parser does not crash on JSON-like input"
    [ json_string ] load_does_not_crash;

  Crowbar.add_test ~name:"lock JSON parser does not crash on structured objects"
    [ json_object ] load_does_not_crash;

  Crowbar.add_test ~name:"lock JSON parser does not crash on lock-file-like input"
    [ lock_file_json ] load_does_not_crash
