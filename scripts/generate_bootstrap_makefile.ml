#directory "+unix"

#load "unix.cma"

#use_output "ocaml scripts/render_bootstrap_mod_use.ml"

let () =
  let args = Array.to_list Sys.argv |> List.tl in
  exit (Bootstrap.run_hidden_command args)
