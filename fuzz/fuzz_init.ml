(* fuzz_init.ml — Fuzz project scaffolding validation. *)

let raw_bytes = Crowbar.map [ Crowbar.bytes ] (fun b -> b)

let target_name_does_not_crash input =
  match Init.validate_target_name "test" input with
  | Ok _ -> ()
  | Error _ -> ()
  | exception _ -> ()

let member_path_does_not_crash input =
  match Init.validate_member_path input with
  | Ok _ -> ()
  | Error _ -> ()
  | exception _ -> ()

let module_stem_does_not_crash input =
  let _ = Init.safe_module_stem input in
  ()

let () =
  Crowbar.add_test ~name:"target name validation does not crash" [ raw_bytes ]
    target_name_does_not_crash;

  Crowbar.add_test ~name:"member path validation does not crash" [ raw_bytes ]
    member_path_does_not_crash;

  Crowbar.add_test ~name:"module stem sanitization does not crash" [ raw_bytes ]
    module_stem_does_not_crash
