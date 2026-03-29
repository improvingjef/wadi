let cases =
  Test_manifest.cases @ Test_layout.cases @ Test_build.cases @ Test_clean.cases
  @ Test_process.cases @ Test_run.cases @ Test_test.cases
  @ Test_toolchain.cases @ Test_explain.cases @ Test_bootstrap.cases

let () =
  let failures = ref [] in
  List.iter
    (fun (name, test) ->
      try
        test ();
        print_endline ("ok - " ^ name)
      with
      | Failure message ->
          failures := (name, message) :: !failures;
          prerr_endline ("not ok - " ^ name ^ "\n" ^ message)
      | exn ->
          let message = Printexc.to_string exn in
          failures := (name, message) :: !failures;
          prerr_endline ("not ok - " ^ name ^ "\n" ^ message))
    cases;
  if !failures = [] then (
    print_endline (Printf.sprintf "All %d tests passed" (List.length cases));
    exit 0)
  else (
    prerr_endline
      (Printf.sprintf "%d/%d tests failed" (List.length !failures)
         (List.length cases));
    exit 1)
