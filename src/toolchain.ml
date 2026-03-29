type package_resolution = {
  packages : string list;
  package_paths : (string * string) list;
}

let ( let* ) = Result.bind

let command_override name default =
  match Sys.getenv_opt name with
  | Some value ->
      let value = String.trim value in
      if value = "" then default else value
  | None -> default

let ocamlc_cmd () = command_override "OCAMLC" "ocamlc"

let ocamlopt_cmd () = command_override "OCAMLOPT" "ocamlopt"

let ocamldep_cmd () = command_override "OCAMLDEP" "ocamldep"

let ocamlfind_cmd () = command_override "OCAMLFIND" "ocamlfind"

let version_of prog =
  let outcome = Process.run_capture prog [ "-version" ] in
  if outcome.status = 0 then Ok (String.trim outcome.output)
  else
    Error
      (Printf.sprintf "failed to query %s version\n%s" prog outcome.output)

let compiler_version () = version_of (ocamlopt_cmd ())

let stdlib_dir () =
  let ocamlc = ocamlc_cmd () in
  let outcome = Process.run_capture ocamlc [ "-where" ] in
  if outcome.status = 0 then
    let path = String.trim outcome.output in
    if path = "" then
      Error (Printf.sprintf "failed to determine the stdlib directory via %s -where" ocamlc)
    else Ok path
  else
    Error
      (Printf.sprintf "failed to query %s -where\n%s" ocamlc outcome.output)

let candidate_library_dirs stdlib_dir library =
  [ Filename.concat stdlib_dir library; stdlib_dir ]

let resolve_library_dir ~exists ~stdlib_dir library =
  List.find_opt
    (fun dir -> exists (Filename.concat dir (library ^ ".cmi")))
    (candidate_library_dirs stdlib_dir library)

let validate_ocamlfind prog =
  let outcome = Process.run_capture prog [ "printconf"; "path" ] in
  if outcome.status = 0 then Ok ()
  else Error outcome.output

let fallback_ocamlfind () =
  let outcome = Process.run_capture (ocamlc_cmd ()) [ "-where" ] in
  if outcome.status <> 0 then None
  else
    let stdlib_dir = String.trim outcome.output in
    let switch_root = Filename.dirname (Filename.dirname stdlib_dir) in
    let candidate = Filename.concat (Filename.concat switch_root "bin") "ocamlfind" in
    if Sys.file_exists candidate then Some candidate else None

let ensure_ocamlfind () =
  let preferred = ocamlfind_cmd () in
  match validate_ocamlfind preferred with
  | Ok () -> Ok preferred
  | Error _ -> (
      match fallback_ocamlfind () with
      | Some candidate -> (
          match validate_ocamlfind candidate with
          | Ok () -> Ok candidate
          | Error _ ->
              Error
                "external packages require ocamlfind; install it with `opam \
                 install ocamlfind`")
      | None ->
          Error
            "external packages require ocamlfind; install it with `opam install \
             ocamlfind`")

let resolve_packages packages =
  let packages = String_util.dedup_preserve packages in
  if packages = [] then Ok { packages; package_paths = [] }
  else
    let* ocamlfind = ensure_ocamlfind () in
    let rec loop acc = function
      | [] -> Ok { packages; package_paths = List.rev acc }
      | package_name :: rest ->
          let outcome = Process.run_capture ocamlfind [ "query"; package_name ] in
          if outcome.status = 0 then
            let package_path = String.trim outcome.output in
            loop ((package_name, package_path) :: acc) rest
          else
            Error
              (Printf.sprintf "package '%s' is not available via ocamlfind"
                 package_name)
    in
    loop [] packages

let package_args resolution =
  match resolution.packages with
  | [] -> []
  | packages -> [ "-package"; String.concat "," packages ]

let link_args resolution =
  match resolution.packages with
  | [] -> []
  | _ -> [ "-linkpkg" ]

let ensure_success_ocamlopt ~verbose resolution args =
  match resolution.packages with
  | [] -> Process.ensure_success ~verbose (ocamlopt_cmd ()) args
  | _ ->
      let* ocamlfind = ensure_ocamlfind () in
      Process.ensure_success ~verbose ocamlfind
        (("ocamlopt" :: package_args resolution) @ args)

let ensure_success_ocamldep ~verbose resolution args =
  match resolution.packages with
  | [] -> Process.ensure_success ~verbose (ocamldep_cmd ()) args
  | _ ->
      let* ocamlfind = ensure_ocamlfind () in
      Process.ensure_success ~verbose ocamlfind
        (("ocamldep" :: package_args resolution) @ args)

let sort_sources ~verbose resolution source_files =
  let* outcome = ensure_success_ocamldep ~verbose resolution ("-sort" :: source_files) in
  Ok (String_util.split_whitespace outcome.Process.output)

let fingerprint_lines resolution =
  let toolchain_lines =
    [
      "tool ocamlc " ^ ocamlc_cmd ();
      "tool ocamlopt " ^ ocamlopt_cmd ();
      "tool ocamldep " ^ ocamldep_cmd ();
      "tool ocamlfind " ^ ocamlfind_cmd ();
    ]
  in
  let stdlib_lines =
    match stdlib_dir () with
    | Ok path -> (
        match resolve_library_dir ~exists:Sys.file_exists ~stdlib_dir:path "unix" with
        | Some unix_dir -> [ "tool stdlib " ^ path; "tool unix " ^ unix_dir ]
        | None -> [ "tool stdlib " ^ path ])
    | Error message -> [ "tool stdlib-error " ^ message ]
  in
  toolchain_lines @ stdlib_lines
  @ List.map
      (fun (package_name, package_path) ->
        Printf.sprintf "package %s %s" package_name package_path)
      resolution.package_paths
