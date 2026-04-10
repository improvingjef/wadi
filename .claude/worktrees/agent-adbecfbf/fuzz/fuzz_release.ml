(* fuzz_release.ml — Fuzz the release metadata parser (shell variable format)
   and version validation in maintenance. *)

let raw_bytes = Crowbar.map [ Crowbar.bytes ] (fun b -> b)

(* Shell variable assignment lines *)
let var_name =
  Crowbar.choose [
    Crowbar.const "WADI_PACKAGE_NAME";
    Crowbar.const "WADI_FORMULA_CLASS";
    Crowbar.const "WADI_RELEASE_VERSION";
    Crowbar.const "WADI_RELEASE_TAG_PREFIX";
    Crowbar.const "WADI_SYNOPSIS";
    Crowbar.const "WADI_DESCRIPTION";
    Crowbar.const "WADI_MAINTAINER_NAME";
    Crowbar.const "WADI_MAINTAINER_EMAIL";
    Crowbar.const "WADI_AUTHORS";
    Crowbar.const "WADI_LICENSE";
    Crowbar.const "WADI_REPOSITORY_URL";
    Crowbar.const "WADI_BUG_REPORTS_URL";
    Crowbar.const "WADI_DEV_REPO";
    Crowbar.const "WADI_HOMEBREW_TAP";
    Crowbar.const "WADI_HOMEBREW_TAP_REMOTE_URL";
    Crowbar.map [ Crowbar.bytes ] (fun s ->
      String.map (fun c ->
        if c = '=' || c = '\n' || c = '\'' || c = '"' then '_' else c) s);
  ]

let shell_value =
  Crowbar.choose [
    (* Single quoted *)
    Crowbar.map [ Crowbar.bytes ] (fun s ->
      let clean = String.map (fun c -> if c = '\'' || c = '\n' then '_' else c) s in
      Printf.sprintf "'%s'" clean);
    (* Double quoted *)
    Crowbar.map [ Crowbar.bytes ] (fun s ->
      let clean = String.map (fun c -> if c = '"' || c = '\n' then '_' else c) s in
      Printf.sprintf "\"%s\"" clean);
    (* Unquoted *)
    Crowbar.map [ Crowbar.bytes ] (fun s ->
      String.map (fun c ->
        if c = ' ' || c = '\n' || c = '\'' || c = '"' || c = '#' then '_' else c) s);
  ]

let metadata_line =
  Crowbar.choose [
    Crowbar.map [ var_name; shell_value ] (fun k v ->
      Printf.sprintf "%s=%s" k v);
    Crowbar.map [ Crowbar.bytes ] (fun s -> "# " ^ s);
    Crowbar.const "";
    raw_bytes;
  ]

let metadata_file =
  Crowbar.map [ Crowbar.list metadata_line ] (fun lines ->
    String.concat "\n" lines)

(* Version strings for maintenance.validate_version *)
let version_string =
  Crowbar.choose [
    Crowbar.const "0.1.0";
    Crowbar.const "1.0.0";
    Crowbar.const "10.20.30";
    Crowbar.const "0.0.0";
    Crowbar.const "";
    Crowbar.const "1";
    Crowbar.const "1.2";
    Crowbar.const "1.2.3.4";
    Crowbar.const "a.b.c";
    Crowbar.const "-1.0.0";
    Crowbar.const "1.0.0-beta";
    Crowbar.map [ Crowbar.bytes ] (fun s -> s);
  ]

let with_temp_file prefix contents f =
  let path = Filename.temp_file prefix ".sh" in
  Fun.protect
    ~finally:(fun () -> try Sys.remove path with _ -> ())
    (fun () ->
      let oc = open_out_bin path in
      output_string oc contents;
      close_out oc;
      f path)

let metadata_does_not_crash input =
  with_temp_file "wadi-fuzz-meta" input (fun path ->
    match Release_metadata.load path with
    | Ok _ -> ()
    | Error _ -> ()
    | exception Failure _ -> ()
    | exception Invalid_argument _ -> ()
    | exception Not_found -> ())

let version_does_not_crash input =
  match Maintenance.validate_version input with
  | Ok _ -> ()
  | Error _ -> ()
  | exception Failure _ -> ()
  | exception Invalid_argument _ -> ()

let () =
  Crowbar.add_test ~name:"release metadata parser does not crash on arbitrary bytes"
    [ raw_bytes ] metadata_does_not_crash;

  Crowbar.add_test ~name:"release metadata parser does not crash on structured input"
    [ metadata_file ] metadata_does_not_crash;

  Crowbar.add_test ~name:"version validation does not crash"
    [ version_string ] version_does_not_crash
