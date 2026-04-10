type backend =
  | Native
  | Bytecode

type backend_request =
  | Auto
  | Select of backend

type package_resolution = {
  packages : string list;
  package_paths : (string * string) list;
}

type invocation = {
  prog : string;
  args : string list;
}

type resolved_command = {
  configured : string;
  resolved : string option;
}

type report = {
  ocamlc : resolved_command;
  ocamlopt : resolved_command;
  ocamldep : resolved_command;
  ocamlfind : resolved_command;
  selected_backend : (backend, string) result;
  compiler_version : (string, string) result;
  stdlib : (string, string) result;
  unix_dir : (string option, string) result;
  package_roots : (string list, string) result;
}

type session = {
  executable_paths : (string, string option) Hashtbl.t;
  command_availability : (string, bool) Hashtbl.t;
  backend_resolutions : (string, (backend, string) result) Hashtbl.t;
  compiler_versions : (string, (string, string) result) Hashtbl.t;
  package_resolutions : (string, (package_resolution, string) result) Hashtbl.t;
  mutable stdlib : (string, string) result option;
  mutable ocamlfind : (string, string) result option;
  mutable package_roots : (string list, string) result option;
}

let ( let* ) = Result.bind

let create_session () =
  {
    executable_paths = Hashtbl.create 8;
    command_availability = Hashtbl.create 8;
    backend_resolutions = Hashtbl.create 4;
    compiler_versions = Hashtbl.create 4;
    package_resolutions = Hashtbl.create 8;
    stdlib = None;
    ocamlfind = None;
    package_roots = None;
  }

let with_cached_field get set f =
  match get () with
  | Some value -> value
  | None ->
      let value = f () in
      set (Some value);
      value

let with_cached_table table key f =
  match Hashtbl.find_opt table key with
  | Some value -> value
  | None ->
      let value = f () in
      Hashtbl.replace table key value;
      value

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

let ocamlmktop_cmd () = command_override "OCAMLMKTOP" "ocamlmktop"

let ocamllex_cmd () = command_override "OCAMLLEX" "ocamllex"

let backend_name = function
  | Native -> "native"
  | Bytecode -> "bytecode"

let backend_request_name = function
  | Auto -> "auto"
  | Select backend -> backend_name backend

let compiler_kind = function
  | Native -> "ocamlopt"
  | Bytecode -> "ocamlc"

let compiler_cmd = function
  | Native -> ocamlopt_cmd ()
  | Bytecode -> ocamlc_cmd ()

let object_extension = function
  | Native -> ".cmx"
  | Bytecode -> ".cmo"

let library_archive_extension = function
  | Native -> ".cmxa"
  | Bytecode -> ".cma"

let parse_backend value =
  match String.lowercase_ascii (String.trim value) with
  | "native" -> Ok Native
  | "bytecode" -> Ok Bytecode
  | value ->
      Error
        (Printf.sprintf
           "unknown backend '%s'; expected auto, native, or bytecode" value)

let parse_backend_request value =
  match String.lowercase_ascii (String.trim value) with
  | "" | "auto" -> Ok Auto
  | value ->
      let* backend = parse_backend value in
      Ok (Select backend)

let env_backend_request () =
  match Sys.getenv_opt "WADI_BACKEND" with
  | None -> Ok Auto
  | Some value -> parse_backend_request value

let path_entries () =
  match Sys.getenv_opt "PATH" with
  | None -> []
  | Some value ->
      value |> String.split_on_char ':' |> List.filter (fun entry -> entry <> "")

let executable_candidates command =
  if String.contains command '/' then [ command ]
  else List.map (fun dir -> Filename.concat dir command) (path_entries ())

let uncached_resolve_executable_path command =
  executable_candidates command
  |> List.find_opt (fun path ->
         try
           Unix.access path [ Unix.X_OK ];
           true
         with
         | Unix.Unix_error _ -> false)
  |> Option.map Fs.realpath

let resolve_executable_path ?session command =
  match session with
  | None -> uncached_resolve_executable_path command
  | Some session ->
      with_cached_table session.executable_paths command (fun () ->
          uncached_resolve_executable_path command)

let version_of prog =
  let outcome = Process.run_capture prog [ "-version" ] in
  if outcome.status = 0 then Ok (String.trim outcome.output)
  else
    Error
      (Printf.sprintf "failed to query %s version\n%s" prog outcome.output)

let uncached_command_is_available prog =
  let outcome = Process.run_capture prog [ "-version" ] in
  outcome.status = 0

let command_is_available ?session prog =
  match session with
  | None -> uncached_command_is_available prog
  | Some session ->
      with_cached_table session.command_availability prog (fun () ->
          uncached_command_is_available prog)

let resolve_backend ?session request =
  let resolve () =
    match request with
    | Select backend ->
        let compiler = compiler_cmd backend in
        if command_is_available ?session compiler then Ok backend
        else
          Error
            (Printf.sprintf "%s backend requested but %s is unavailable"
               (backend_name backend) compiler)
    | Auto ->
        if command_is_available ?session (compiler_cmd Native) then Ok Native
        else if command_is_available ?session (compiler_cmd Bytecode) then Ok Bytecode
        else
          Error
            (Printf.sprintf
               "no working OCaml compiler found; tried %s and %s"
               (ocamlopt_cmd ()) (ocamlc_cmd ()))
  in
  match session with
  | None -> resolve ()
  | Some session ->
      with_cached_table session.backend_resolutions
        (backend_request_name request) resolve

let compiler_version ?session backend =
  let key = backend_name backend in
  let resolve () = version_of (compiler_cmd backend) in
  match session with
  | None -> resolve ()
  | Some session ->
      with_cached_table session.compiler_versions key resolve

let uncached_stdlib_dir () =
  let ocamlc = ocamlc_cmd () in
  let outcome = Process.run_capture ocamlc [ "-where" ] in
  if outcome.status = 0 then
    let path = String.trim outcome.output in
    if path = "" then
      Error
        (Printf.sprintf "failed to determine the stdlib directory via %s -where"
           ocamlc)
    else Ok path
  else
    Error
      (Printf.sprintf "failed to query %s -where\n%s" ocamlc outcome.output)

let stdlib_dir ?session () =
  match session with
  | None -> uncached_stdlib_dir ()
  | Some session ->
      with_cached_field
        (fun () -> session.stdlib)
        (fun value -> session.stdlib <- value)
        uncached_stdlib_dir

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

let uncached_ensure_ocamlfind () =
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

let ensure_ocamlfind ?session () =
  match session with
  | None -> uncached_ensure_ocamlfind ()
  | Some session ->
      with_cached_field
        (fun () -> session.ocamlfind)
        (fun value -> session.ocamlfind <- value)
        uncached_ensure_ocamlfind

let package_cache_key packages = String.concat "\000" packages

let uncached_package_search_roots ?session () =
  let* ocamlfind = ensure_ocamlfind ?session () in
  let outcome = Process.run_capture ocamlfind [ "printconf"; "path" ] in
  if outcome.status = 0 then Ok (String_util.split_lines outcome.output)
  else
    Error
      (Printf.sprintf "failed to query %s package roots\n%s" ocamlfind
         outcome.output)

let package_search_roots ?session () =
  match session with
  | None -> uncached_package_search_roots ()
  | Some session ->
      with_cached_field
        (fun () -> session.package_roots)
        (fun value -> session.package_roots <- value)
        (fun () -> uncached_package_search_roots ~session ())

let resolve_packages ?session packages =
  let packages = String_util.dedup_preserve packages in
  let resolve () =
    if packages = [] then Ok { packages; package_paths = [] }
    else
      let* ocamlfind = ensure_ocamlfind ?session () in
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
  in
  match session with
  | None -> resolve ()
  | Some session ->
      with_cached_table session.package_resolutions
        (package_cache_key packages) resolve

let package_args resolution =
  match resolution.packages with
  | [] -> []
  | packages -> [ "-package"; String.concat "," packages ]

let link_args resolution =
  match resolution.packages with
  | [] -> []
  | _ -> [ "-linkpkg" ]

let compiler_invocation ?session backend resolution args =
  match resolution.packages with
  | [] -> Ok { prog = compiler_cmd backend; args }
  | _ ->
      let* ocamlfind = ensure_ocamlfind ?session () in
      Ok
        {
          prog = ocamlfind;
          args = (compiler_kind backend :: package_args resolution) @ args;
        }

let ocamldep_invocation ?session resolution args =
  match resolution.packages with
  | [] -> Ok { prog = ocamldep_cmd (); args }
  | _ ->
      let* ocamlfind = ensure_ocamlfind ?session () in
      Ok
        {
          prog = ocamlfind;
          args = ("ocamldep" :: package_args resolution) @ args;
        }

let ocamlmktop_invocation ?session resolution args =
  match resolution.packages with
  | [] -> Ok { prog = ocamlmktop_cmd (); args }
  | _ ->
      let* ocamlfind = ensure_ocamlfind ?session () in
      Ok
        {
          prog = ocamlfind;
          args = ("ocamlmktop" :: package_args resolution) @ args;
        }

let render_invocation ?cwd ?(env = []) invocation =
  Process.render ?cwd ~env invocation.prog invocation.args

let ensure_success_compiler ?session ?(env = []) ~verbose backend resolution args =
  let* invocation = compiler_invocation ?session backend resolution args in
  Process.ensure_success ~verbose ~env invocation.prog invocation.args

let ensure_success_ocamldep ?session ?(env = []) ~verbose resolution args =
  let* invocation = ocamldep_invocation ?session resolution args in
  Process.ensure_success ~verbose ~env invocation.prog invocation.args

let ensure_success_ocamlmktop ?session ?(env = []) ~verbose resolution args =
  let* invocation = ocamlmktop_invocation ?session resolution args in
  Process.ensure_success ~verbose ~env invocation.prog invocation.args

let sort_sources ?session ?(env = []) ~verbose resolution source_files =
  let* outcome =
    ensure_success_ocamldep ?session ~env ~verbose resolution
      ("-sort" :: source_files)
  in
  Ok (String_util.split_whitespace outcome.Process.output)

let fingerprint_lines ?session resolution =
  let toolchain_lines =
    [
      "tool ocamlc " ^ ocamlc_cmd ();
      "tool ocamlopt " ^ ocamlopt_cmd ();
      "tool ocamldep " ^ ocamldep_cmd ();
      "tool ocamlfind " ^ ocamlfind_cmd ();
    ]
  in
  let stdlib_lines =
    match stdlib_dir ?session () with
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

let configured_command_report ?session command =
  { configured = command; resolved = resolve_executable_path ?session command }

let resolved_ocamlfind_report ?session () =
  let configured = ocamlfind_cmd () in
  match ensure_ocamlfind ?session () with
  | Ok command ->
      {
        configured;
        resolved =
          (match resolve_executable_path ?session command with
          | Some path -> Some path
          | None -> Some command);
      }
  | Error _ -> configured_command_report ?session configured

let inspect ?session () =
  let stdlib = stdlib_dir ?session () in
  let unix_dir =
    match stdlib with
    | Ok path ->
        Ok (resolve_library_dir ~exists:Sys.file_exists ~stdlib_dir:path "unix")
    | Error message -> Error message
  in
  {
    ocamlc = configured_command_report ?session (ocamlc_cmd ());
    ocamlopt = configured_command_report ?session (ocamlopt_cmd ());
    ocamldep = configured_command_report ?session (ocamldep_cmd ());
    ocamlfind = resolved_ocamlfind_report ?session ();
    selected_backend =
      Result.bind (env_backend_request ()) (resolve_backend ?session);
    compiler_version =
      Result.bind
        (Result.bind (env_backend_request ()) (resolve_backend ?session))
        (compiler_version ?session);
    stdlib;
    unix_dir;
    package_roots = package_search_roots ?session ();
  }

let render_command_report name command =
  match command.resolved with
  | Some resolved when resolved = command.configured ->
      Printf.sprintf "%s: %s" name resolved
  | Some resolved ->
      Printf.sprintf "%s: %s (configured as %s)" name resolved command.configured
  | None -> Printf.sprintf "%s: unresolved (%s)" name command.configured

let render_result name = function
  | Ok value -> Printf.sprintf "%s: %s" name value
  | Error message ->
      Printf.sprintf "%s-error: %s" name (String.trim message)

let render_report report =
  let base_lines =
    [
      render_command_report "ocamlc" report.ocamlc;
      render_command_report "ocamlopt" report.ocamlopt;
      render_command_report "ocamldep" report.ocamldep;
      render_command_report "ocamlfind" report.ocamlfind;
      (match report.selected_backend with
      | Ok backend -> "selected-backend: " ^ backend_name backend
      | Error message ->
          "selected-backend-error: " ^ String.trim message);
      render_result "compiler-version" report.compiler_version;
      render_result "stdlib" report.stdlib;
      (match report.unix_dir with
      | Ok (Some path) -> "unix-library-dir: " ^ path
      | Ok None -> "unix-library-dir: unavailable"
      | Error message ->
          "unix-library-dir-error: " ^ String.trim message);
    ]
  in
  match report.package_roots with
  | Ok roots ->
      String.concat "\n"
        (base_lines @ ("package-roots:" :: List.map (fun root -> "  " ^ root) roots))
  | Error message ->
      String.concat "\n"
        (base_lines @ [ "package-roots-error: " ^ String.trim message ])
