(* fuzz_migrate.ml — Fuzz the dune s-expression parser used in migration.
   Custom recursive descent parser for a non-trivial format. *)

let raw_bytes = Crowbar.map [ Crowbar.bytes ] (fun b -> b)

(* S-expression characters *)
let sexp_char =
  Crowbar.choose [
    Crowbar.const '('; Crowbar.const ')';
    Crowbar.const '"'; Crowbar.const ' ';
    Crowbar.const '\n'; Crowbar.const '\t';
    Crowbar.const '\\'; Crowbar.const ';';
    Crowbar.const 'a'; Crowbar.const '_';
    Crowbar.const '-'; Crowbar.const '.';
    Crowbar.const ':'; Crowbar.const '/';
    Crowbar.const '*'; Crowbar.const '%';
    Crowbar.map [ Crowbar.uint8 ] Char.chr;
  ]

let sexp_string =
  Crowbar.map [ Crowbar.list sexp_char ] (fun chars ->
    String.init (List.length chars) (List.nth chars))

(* Structured dune-like s-expressions *)
let atom =
  Crowbar.choose [
    Crowbar.const "library";
    Crowbar.const "executable";
    Crowbar.const "executables";
    Crowbar.const "test";
    Crowbar.const "name";
    Crowbar.const "names";
    Crowbar.const "public_name";
    Crowbar.const "libraries";
    Crowbar.const "modules";
    Crowbar.const "preprocess";
    Crowbar.const "pps";
    Crowbar.const "ocamllex";
    Crowbar.const "menhir";
    Crowbar.const "rule";
    Crowbar.const "alias";
    Crowbar.const "action";
    Crowbar.const "run";
    Crowbar.const "lang";
    Crowbar.const "dune";
    Crowbar.const "using";
    Crowbar.const ":standard";
    Crowbar.const "ocamlopt_flags";
    Crowbar.const "ocamlc_flags";
    Crowbar.const "instrumentation";
    Crowbar.const "backend";
    Crowbar.const "dirs";
    Crowbar.const "wrapped";
    Crowbar.const "true";
    Crowbar.const "false";
    Crowbar.map [ Crowbar.bytes ] (fun s ->
      String.map (fun c ->
        if c = '(' || c = ')' || c = '"' || c = ' ' || c = '\n' then '_' else c) s);
  ]

let quoted_atom =
  Crowbar.map [ Crowbar.bytes ] (fun s ->
    let clean = String.map (fun c ->
      if c = '"' || c = '\\' || c = '\n' then '_' else c) s in
    Printf.sprintf "\"%s\"" clean)

let sexp_value =
  Crowbar.choose [ atom; quoted_atom ]

(* Build nested s-expressions *)
let rec sexp_expr depth =
  if depth <= 0 then sexp_value
  else
    Crowbar.choose [
      sexp_value;
      Crowbar.map [ Crowbar.list1 (sexp_expr (depth - 1)) ] (fun items ->
        Printf.sprintf "(%s)" (String.concat " " items));
    ]

let dune_stanza =
  Crowbar.map [ atom; Crowbar.list (sexp_expr 2) ] (fun kind fields ->
    Printf.sprintf "(%s %s)" kind (String.concat " " fields))

let dune_file =
  Crowbar.map [ Crowbar.list dune_stanza ] (fun stanzas ->
    String.concat "\n" stanzas)

(* dune-project file *)
let _dune_project =
  Crowbar.map [ Crowbar.bytes ] (fun name ->
    let clean = String.map (fun c ->
      if c = '"' || c = '\\' || c = '\n' || c = '(' || c = ')' then '_' else c) name in
    Printf.sprintf "(lang dune 3.0)\n(name %s)\n" clean)

let with_temp_dune_workspace contents f =
  let dir = Filename.temp_file "wadi-fuzz-migrate" ".tmp" in
  (try Sys.remove dir with _ -> ());
  Unix.mkdir dir 0o755;
  Fun.protect
    ~finally:(fun () -> try Fs.remove_tree dir with _ -> ())
    (fun () ->
      let dp = Filename.concat dir "dune-project" in
      let oc = open_out dp in
      output_string oc "(lang dune 3.0)\n(name fuzz)\n";
      close_out oc;
      let df = Filename.concat dir "dune" in
      let oc = open_out df in
      output_string oc contents;
      close_out oc;
      f dir)

let migrate_does_not_crash input =
  with_temp_dune_workspace input (fun dir ->
    match Migrate.run ~workspace_root:dir with
    | Ok _ -> ()
    | Error _ -> ()
    | exception Failure _ -> ()
    | exception Invalid_argument _ -> ()
    | exception Not_found -> ())

let () =
  Crowbar.add_test ~name:"dune sexp parser does not crash on arbitrary bytes"
    [ raw_bytes ] migrate_does_not_crash;

  Crowbar.add_test ~name:"dune sexp parser does not crash on sexp-like input"
    [ sexp_string ] migrate_does_not_crash;

  Crowbar.add_test ~name:"dune sexp parser does not crash on structured dune input"
    [ dune_file ] migrate_does_not_crash
