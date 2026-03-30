(* fuzz_watch.ml — Fuzz ignore file parsing and watch config loading. *)

let raw_bytes = Crowbar.map [ Crowbar.bytes ] (fun b -> b)

(* Glob patterns *)
let glob_segment =
  Crowbar.choose
    [
      Crowbar.const "*";
      Crowbar.const "**";
      Crowbar.const "*.ml";
      Crowbar.const "src";
      Crowbar.const "_wadi";
      Crowbar.const ".git";
      Crowbar.const "";
      Crowbar.map [ Crowbar.bytes ] (fun s ->
          String.map (fun c -> if c = '\n' then '_' else c) s);
    ]

let glob_pattern =
  Crowbar.map [ Crowbar.list1 glob_segment ] (fun segs -> String.concat "/" segs)

(* Ignore file lines *)
let ignore_line =
  Crowbar.choose
    [
      glob_pattern;
      Crowbar.map [ Crowbar.bytes ] (fun s -> "# " ^ s);
      Crowbar.const "";
      raw_bytes;
    ]

let ignore_file =
  Crowbar.map [ Crowbar.list ignore_line ] (fun lines -> String.concat "\n" lines)

(* Watch config in manifest format *)
let watch_config =
  Crowbar.map
    [ Crowbar.list1 glob_pattern; Crowbar.list glob_pattern ]
    (fun includes excludes ->
      let escape s =
        String.map (fun c -> if c = '"' || c = '\\' || c = '\n' then '_' else c) s
      in
      let quoted_includes =
        List.map (fun s -> Printf.sprintf "\"%s\"" (escape s)) includes
      in
      let quoted_excludes =
        List.map (fun s -> Printf.sprintf "\"%s\"" (escape s)) excludes
      in
      Printf.sprintf
        "version = 1\n\
         [library.x]\n\
         dir = \"src\"\n\
         modules = [\"a\"]\n\
         [watch]\n\
         include = [%s]\n\
         exclude = [%s]\n"
        (String.concat ", " quoted_includes)
        (String.concat ", " quoted_excludes))

let with_temp_file prefix contents f =
  let path = Filename.temp_file prefix ".txt" in
  Fun.protect
    ~finally:(fun () -> try Sys.remove path with _ -> ())
    (fun () ->
      let oc = open_out_bin path in
      output_string oc contents;
      close_out oc;
      f path)

let with_temp_manifest contents f =
  let path = Filename.temp_file "wadi-fuzz-watch" ".toml" in
  Fun.protect
    ~finally:(fun () -> try Sys.remove path with _ -> ())
    (fun () ->
      let oc = open_out_bin path in
      output_string oc contents;
      close_out oc;
      f path)

let ignore_file_does_not_crash input =
  with_temp_file "wadi-fuzz-ignore" input (fun path ->
      match Watch.load_ignore_file_globs path with
      | _ -> ()
      | exception Failure _ -> ()
      | exception Invalid_argument _ -> ())

let watch_config_does_not_crash input =
  with_temp_manifest input (fun path ->
      match Manifest.load_watch_config path with
      | Ok _ -> ()
      | Error _ -> ()
      | exception Failure _ -> ()
      | exception Invalid_argument _ -> ())

let split_glob_does_not_crash input =
  let _ = Watch.split_glob_segments input in
  ()

let () =
  Crowbar.add_test ~name:"ignore file parser does not crash on arbitrary bytes"
    [ raw_bytes ] ignore_file_does_not_crash;

  Crowbar.add_test ~name:"ignore file parser does not crash on structured input"
    [ ignore_file ] ignore_file_does_not_crash;

  Crowbar.add_test ~name:"watch config parser does not crash" [ watch_config ]
    watch_config_does_not_crash;

  Crowbar.add_test ~name:"glob segment splitting does not crash" [ raw_bytes ]
    split_glob_does_not_crash
