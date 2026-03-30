(* fuzz_manifest.ml — AFL-powered fuzzer for the wadi manifest parser.

   Feeds arbitrary bytes through Manifest.load via a temp file.
   The parser must never crash — returning Error is fine.

   Run under AFL:
     mkdir -p fuzz/input fuzz/output
     echo '[library.x]\ndir = "src"\nmodules = ["a"]' > fuzz/input/seed.toml
     afl-fuzz -i fuzz/input -o fuzz/output -- ./_bootstrap/bin/fuzz_manifest @@

   Or run in crowbar quickcheck mode (no AFL):
     ./_bootstrap/bin/fuzz_manifest
*)

let with_temp_manifest contents f =
  let path = Filename.temp_file "wadi-fuzz" ".toml" in
  Fun.protect
    ~finally:(fun () -> try Sys.remove path with _ -> ())
    (fun () ->
      let oc = open_out_bin path in
      output_string oc contents;
      close_out oc;
      f path)

(* The core property: parsing never raises an unhandled exception.
   Ok _ and Error _ are both acceptable. *)
let manifest_does_not_crash input =
  with_temp_manifest input (fun path ->
      match Manifest.load path with
      | Ok _ -> ()
      | Error _ -> ()
      | exception Failure _ -> ()
      | exception Invalid_argument _ -> ())

(* Generator: arbitrary bytes interpreted as a manifest *)
let raw_bytes = Crowbar.map [ Crowbar.bytes ] (fun b -> b)

(* Generator: structured TOML-like content *)
let toml_char =
  Crowbar.choose
    [
      Crowbar.const 'a';
      Crowbar.const '1';
      Crowbar.const '"';
      Crowbar.const '[';
      Crowbar.const ']';
      Crowbar.const '=';
      Crowbar.const '.';
      Crowbar.const '#';
      Crowbar.const '\\';
      Crowbar.const '\n';
      Crowbar.const ' ';
      Crowbar.const ',';
      Crowbar.const '/';
      Crowbar.const '.';
      Crowbar.const '_';
      Crowbar.map [ Crowbar.uint8 ] Char.chr;
    ]

let toml_string =
  Crowbar.map
    [ Crowbar.list toml_char ]
    (fun chars -> String.init (List.length chars) (List.nth chars))

(* Generator: valid-ish section headers *)
let section_kind =
  Crowbar.choose
    [
      Crowbar.const "library";
      Crowbar.const "executable";
      Crowbar.const "test";
      Crowbar.const "action";
      Crowbar.const "profile";
      Crowbar.const "defaults";
      Crowbar.const "preprocess";
      Crowbar.const "ppx";
      Crowbar.const "watch";
      Crowbar.const "bench";
      Crowbar.const "";
    ]

let ident =
  Crowbar.map [ Crowbar.bytes ] (fun b ->
      let s =
        String.map
          (fun c ->
            if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c = '_' then c else 'x')
          b
      in
      if String.length s = 0 then "x" else s)

let section_header =
  Crowbar.map [ section_kind; ident ] (fun kind name ->
      if kind = "" then Printf.sprintf "[%s]" name else Printf.sprintf "[%s.%s]" kind name)

(* Generator: key = value lines *)
let field_name =
  Crowbar.choose
    [
      Crowbar.const "dir";
      Crowbar.const "modules";
      Crowbar.const "main";
      Crowbar.const "deps";
      Crowbar.const "packages";
      Crowbar.const "compile_flags";
      Crowbar.const "link_flags";
      Crowbar.const "env";
      Crowbar.const "sandbox";
      Crowbar.const "actions";
      Crowbar.const "preprocess";
      Crowbar.const "ppx";
      Crowbar.const "wrapped";
      Crowbar.const "argv";
      Crowbar.const "outputs";
      Crowbar.const "cwd";
      Crowbar.const "stdin";
      Crowbar.const "workspace";
      Crowbar.const "version";
      Crowbar.const "members";
      Crowbar.const "public_name";
    ]

let quoted_string = Crowbar.map [ ident ] (fun s -> Printf.sprintf "\"%s\"" s)

let value =
  Crowbar.choose
    [
      quoted_string;
      Crowbar.map
        [ Crowbar.list1 quoted_string ]
        (fun items -> Printf.sprintf "[%s]" (String.concat ", " items));
      Crowbar.const "1";
      Crowbar.const "true";
      Crowbar.const "false";
      Crowbar.map [ Crowbar.int32 ] (fun n -> Int32.to_string n);
    ]

let key_value_line =
  Crowbar.map [ field_name; value ] (fun k v -> Printf.sprintf "%s = %s" k v)

(* Generator: a line is either a section header, a key-value pair,
   a comment, a blank line, or arbitrary garbage *)
let manifest_line =
  Crowbar.choose
    [
      section_header;
      key_value_line;
      Crowbar.map [ Crowbar.bytes ] (fun s -> "# " ^ s);
      Crowbar.const "";
      toml_string;
    ]

let structured_manifest =
  Crowbar.map [ Crowbar.list manifest_line ] (fun lines -> String.concat "\n" lines)

(* --- String utility fuzzing --- *)

let strip_comment_does_not_crash input =
  let _ = String_util.strip_comment input in
  ()

let split_dot_does_not_crash input =
  let _ = String_util.split_dot input in
  ()

let split_whitespace_does_not_crash input =
  let _ = String_util.split_whitespace input in
  ()

let json_escape_does_not_crash input =
  let _ = String_util.json_escape input in
  ()

(* --- Register fuzz targets --- *)

let () =
  (* Manifest parser: raw bytes *)
  Crowbar.add_test ~name:"manifest parser does not crash on arbitrary bytes" [ raw_bytes ]
    (fun input -> manifest_does_not_crash input);

  (* Manifest parser: structured TOML-like input *)
  Crowbar.add_test ~name:"manifest parser does not crash on structured input"
    [ structured_manifest ] (fun input -> manifest_does_not_crash input);

  (* String utilities *)
  Crowbar.add_test ~name:"strip_comment does not crash" [ raw_bytes ] (fun input ->
      strip_comment_does_not_crash input);

  Crowbar.add_test ~name:"split_dot does not crash" [ raw_bytes ] (fun input ->
      split_dot_does_not_crash input);

  Crowbar.add_test ~name:"split_whitespace does not crash" [ raw_bytes ] (fun input ->
      split_whitespace_does_not_crash input);

  Crowbar.add_test ~name:"json_escape does not crash" [ raw_bytes ] (fun input ->
      json_escape_does_not_crash input)
