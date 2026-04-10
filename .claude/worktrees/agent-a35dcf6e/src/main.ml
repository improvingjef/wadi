let () =
  match Array.to_list Sys.argv with
  | _program :: command :: args when command = Bootstrap.hidden_command_name ->
      exit (Bootstrap.run_hidden_command args)
  | _ -> (
      match Cli.run Sys.argv with
      | Cli.Exit_code code -> exit code
      | Cli.Forward_status status -> Process.exit_with_status status)
