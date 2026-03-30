(* fuzz_vendor.ml — Fuzz vendor name validation and checksum parsing. *)

let raw_bytes = Crowbar.map [ Crowbar.bytes ] (fun b -> b)

(* Checksum strings *)
let hex_char =
  Crowbar.choose
    [
      Crowbar.const '0';
      Crowbar.const '1';
      Crowbar.const '9';
      Crowbar.const 'a';
      Crowbar.const 'f';
      Crowbar.map [ Crowbar.uint8 ] Char.chr;
    ]

let hex_string =
  Crowbar.map
    [ Crowbar.list hex_char ]
    (fun chars -> String.init (List.length chars) (List.nth chars))

let checksum_string =
  Crowbar.choose
    [
      Crowbar.map [ hex_string ] (fun h -> "sha256:" ^ h);
      Crowbar.map [ hex_string ] (fun h -> "sha512:" ^ h);
      Crowbar.map [ hex_string ] (fun h -> "git:" ^ h);
      Crowbar.map [ hex_string ] (fun h -> "sha1:" ^ h);
      hex_string;
      raw_bytes;
    ]

let name_does_not_crash input =
  match Vendor.validate_name "test" input with
  | Ok _ -> ()
  | Error _ -> ()
  | exception _ -> ()

let archive_checksum_does_not_crash input =
  match Vendor.parse_archive_checksum input with
  | Ok _ -> ()
  | Error _ -> ()
  | exception _ -> ()

let git_checksum_does_not_crash input =
  match Vendor.parse_git_checksum input with
  | Ok _ -> ()
  | Error _ -> ()
  | exception _ -> ()

let () =
  Crowbar.add_test ~name:"vendor name validation does not crash" [ raw_bytes ]
    name_does_not_crash;

  Crowbar.add_test ~name:"archive checksum parsing does not crash" [ checksum_string ]
    archive_checksum_does_not_crash;

  Crowbar.add_test ~name:"archive checksum parsing does not crash on arbitrary bytes"
    [ raw_bytes ] archive_checksum_does_not_crash;

  Crowbar.add_test ~name:"git checksum parsing does not crash" [ checksum_string ]
    git_checksum_does_not_crash
