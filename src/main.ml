let () =
  match Cli.run Sys.argv with
  | Cli.Exit_code code -> exit code
  | Cli.Forward_status status -> Process.exit_with_status status
