#directory "+unix";;
#load "unix.cma";;
#use_output "ocaml scripts/render_bootstrap_mod_use.ml";;

let manifest_path =
  let rec loop index =
    if index >= Array.length Sys.argv then
      match Sys.getenv_opt "BOOTSTRAP_MANIFEST" with
      | Some path when String.trim path <> "" -> path
      | Some _ | None -> "oasis.toml"
    else
      match Sys.argv.(index) with
      | "--manifest" ->
          if index + 1 >= Array.length Sys.argv then (
            prerr_endline "oasis bootstrap: --manifest requires a path";
            exit 2)
          else Sys.argv.(index + 1)
      | _ -> loop (index + 1)
  in
  loop 1

let profile =
  let rec loop index =
    if index >= Array.length Sys.argv then
      match Sys.getenv_opt "BOOTSTRAP_PROFILE" with
      | Some profile when String.trim profile <> "" -> Some profile
      | Some _ | None -> None
    else
      match Sys.argv.(index) with
      | "--profile" ->
          if index + 1 >= Array.length Sys.argv then (
            prerr_endline "oasis bootstrap: --profile requires a name";
            exit 2)
          else Some Sys.argv.(index + 1)
      | _ -> loop (index + 1)
  in
  loop 1

let scope =
  let rec loop index =
    if index >= Array.length Sys.argv then Bootstrap.Full
    else
      match Sys.argv.(index) with
      | "--scope" ->
          if index + 1 >= Array.length Sys.argv then (
            prerr_endline "oasis bootstrap: --scope requires app or full";
            exit 2)
          else (
            match String.lowercase_ascii (String.trim Sys.argv.(index + 1)) with
            | "app" | "executable" -> Bootstrap.Executable_only
            | "full" -> Bootstrap.Full
            | value ->
                prerr_endline
                  ("oasis bootstrap: unknown scope '" ^ value
                 ^ "'; expected app or full");
                exit 2)
      | _ -> loop (index + 1)
  in
  loop 1

let () =
  match Bootstrap.render_makefile ?profile ~scope ~manifest_path () with
  | Ok text -> print_string text
  | Error message ->
      prerr_endline ("oasis bootstrap: " ^ message);
      exit 1
