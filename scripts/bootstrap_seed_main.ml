let () =
  let args = Array.to_list Sys.argv |> List.tl in
  exit (Bootstrap.run_hidden_command args)
