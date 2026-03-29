#directory "+unix";;
#load "unix.cma";;
#mod_use "src/string_util.ml";;
#mod_use "src/fs.ml";;
#mod_use "src/process.ml";;
#mod_use "src/toolchain.ml";;
#mod_use "src/manifest.ml";;
#mod_use "src/layout.ml";;
#mod_use "src/builder.ml";;
#mod_use "src/bootstrap.ml";;

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

let () =
  match Bootstrap.render_makefile ~manifest_path with
  | Ok text -> print_string text
  | Error message ->
      prerr_endline ("oasis bootstrap: " ^ message);
      exit 1
