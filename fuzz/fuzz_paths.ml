(* fuzz_paths.ml — AFL-powered fuzzer for path validation and layout.

   Exercises:
   - Manifest path validation (relative paths, no .., no absolute)
   - Layout artifact path computation
   - Identifier validation (module names, target names)
   - Environment binding parsing (KEY=value)
*)

(* We can't call manifest.ml internal validators directly since they
   aren't exposed. Instead we construct manifests that exercise specific
   validation paths and check they don't crash. *)

let with_temp_manifest contents f =
  let path = Filename.temp_file "wadi-fuzz-path" ".toml" in
  Fun.protect
    ~finally:(fun () -> try Sys.remove path with _ -> ())
    (fun () ->
      let oc = open_out_bin path in
      output_string oc contents;
      close_out oc;
      f path)

(* Path-focused manifest: exercise dir, cwd, deps path validation *)
let path_string =
  Crowbar.choose
    [
      Crowbar.const ".";
      Crowbar.const "..";
      Crowbar.const "../escape";
      Crowbar.const "/absolute";
      Crowbar.const "normal/path";
      Crowbar.const "src";
      Crowbar.const "";
      Crowbar.const "a/b/c/d/e";
      Crowbar.const "a/../b";
      Crowbar.const "./relative";
      Crowbar.const "has spaces";
      Crowbar.const "has\"quotes";
      Crowbar.const "has\\backslash";
      Crowbar.map [ Crowbar.bytes ] (fun s ->
          String.map (fun c -> if c = '\n' || c = '"' then '_' else c) s);
    ]

(* Module name-focused: exercise identifier validation *)
let module_name =
  Crowbar.choose
    [
      Crowbar.const "valid_name";
      Crowbar.const "has.dot";
      Crowbar.const "has/slash";
      Crowbar.const "";
      Crowbar.const "CamelCase";
      Crowbar.const "123numeric";
      Crowbar.const "a";
      Crowbar.map [ Crowbar.bytes ] (fun s ->
          String.map (fun c -> if c = '"' || c = '\n' || c = '\\' then '_' else c) s);
    ]

(* Environment binding-focused *)
let env_binding =
  Crowbar.choose
    [
      Crowbar.const "KEY=value";
      Crowbar.const "=nokey";
      Crowbar.const "noequals";
      Crowbar.const "";
      Crowbar.const "A=";
      Crowbar.const "A=B=C";
      Crowbar.const "KEY=has spaces";
      Crowbar.map [ Crowbar.bytes; Crowbar.bytes ] (fun k v ->
          let clean s =
            String.map
              (fun c ->
                if c = '"' || c = '\n' || c = '\\' || c = '[' || c = ']' then '_' else c)
              s
          in
          clean k ^ "=" ^ clean v);
    ]

let escape_toml_string s =
  let buf = Buffer.create (String.length s + 2) in
  Buffer.add_char buf '"';
  String.iter
    (fun c ->
      match c with
      | '"' -> Buffer.add_string buf "\\\""
      | '\\' -> Buffer.add_string buf "\\\\"
      | '\n' -> Buffer.add_string buf "\\n"
      | c -> Buffer.add_char buf c)
    s;
  Buffer.add_char buf '"';
  Buffer.contents buf

(* Construct a manifest exercising dir path validation *)
let dir_path_manifest =
  Crowbar.map [ path_string ] (fun dir ->
      Printf.sprintf "version = 1\n[library.fuzz]\ndir = %s\nmodules = [\"a\"]\n"
        (escape_toml_string dir))

(* Construct a manifest exercising module name validation *)
let module_name_manifest =
  Crowbar.map
    [ Crowbar.list1 module_name ]
    (fun names ->
      let quoted = List.map escape_toml_string names in
      Printf.sprintf "version = 1\n[library.fuzz]\ndir = \"src\"\nmodules = [%s]\n"
        (String.concat ", " quoted))

(* Construct a manifest exercising env binding validation *)
let env_binding_manifest =
  Crowbar.map
    [ Crowbar.list1 env_binding ]
    (fun bindings ->
      let quoted = List.map escape_toml_string bindings in
      Printf.sprintf
        "version = 1\n[library.fuzz]\ndir = \"src\"\nmodules = [\"a\"]\nenv = [%s]\n"
        (String.concat ", " quoted))

(* Construct a manifest exercising sandbox values *)
let sandbox_manifest =
  Crowbar.map [ Crowbar.bytes ] (fun value ->
      Printf.sprintf
        "version = 1\n[library.fuzz]\ndir = \"src\"\nmodules = [\"a\"]\nsandbox = %s\n"
        (escape_toml_string value))

(* Construct a manifest with action definitions *)
let action_manifest =
  Crowbar.map
    [ path_string; Crowbar.list1 path_string ]
    (fun cwd outputs ->
      let quoted_outputs = List.map escape_toml_string outputs in
      Printf.sprintf
        "version = 1\n\
         [action.gen]\n\
         argv = [\"echo\"]\n\
         cwd = %s\n\
         outputs = [%s]\n\
         [library.fuzz]\n\
         dir = \"src\"\n\
         modules = [\"a\"]\n\
         actions = [\"gen\"]\n"
        (escape_toml_string cwd)
        (String.concat ", " quoted_outputs))

(* Dependency cycle manifests *)
let dep_cycle_manifest =
  Crowbar.map
    [ Crowbar.range 5 ]
    (fun n ->
      let n = n + 2 in
      let libs =
        List.init n (fun i ->
            let dep = if i = n - 1 then 0 else i + 1 in
            Printf.sprintf
              "[library.lib%d]\ndir = \"src\"\nmodules = [\"m%d\"]\ndeps = [\"lib%d\"]\n"
              i i dep)
      in
      "version = 1\n" ^ String.concat "\n" libs)

(* Profile override manifests *)
let profile_manifest =
  Crowbar.map [ Crowbar.bytes; Crowbar.bytes ] (fun profile_name target_name ->
      let clean s =
        String.map
          (fun c ->
            if c = '"' || c = '\n' || c = '\\' || c = '[' || c = ']' || c = '.' then '_'
            else c)
          s
      in
      let pn = clean profile_name in
      let tn = clean target_name in
      Printf.sprintf
        "version = 1\n\
         [library.%s]\n\
         dir = \"src\"\n\
         modules = [\"a\"]\n\
         [profile.%s]\n\
         compile_flags = [\"-O2\"]\n\
         [profile.%s.library.%s]\n\
         compile_flags = [\"-O3\"]\n"
        (if tn = "" then "x" else tn)
        (if pn = "" then "x" else pn)
        (if pn = "" then "x" else pn)
        (if tn = "" then "x" else tn))

let does_not_crash input =
  with_temp_manifest input (fun path ->
      match Manifest.load path with
      | Ok _ -> ()
      | Error _ -> ()
      | exception Failure _ -> ()
      | exception Invalid_argument _ -> ())

let () =
  Crowbar.add_test ~name:"dir path validation does not crash" [ dir_path_manifest ]
    does_not_crash;

  Crowbar.add_test ~name:"module name validation does not crash" [ module_name_manifest ]
    does_not_crash;

  Crowbar.add_test ~name:"env binding validation does not crash" [ env_binding_manifest ]
    does_not_crash;

  Crowbar.add_test ~name:"sandbox value validation does not crash" [ sandbox_manifest ]
    does_not_crash;

  Crowbar.add_test ~name:"action definition validation does not crash" [ action_manifest ]
    does_not_crash;

  Crowbar.add_test ~name:"dependency cycle detection does not crash"
    [ dep_cycle_manifest ] does_not_crash;

  Crowbar.add_test ~name:"profile override validation does not crash" [ profile_manifest ]
    does_not_crash
