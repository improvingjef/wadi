type build_options = {
  workspace_dir : string;
  verbose : bool;
  targets : string list;
}

let usage () =
  String.concat "\n"
    [
      "Usage:";
      "  oasis build [--workspace DIR] [--verbose] [TARGET ...]";
      "";
      "Examples:";
      "  oasis build";
      "  oasis build hello";
      "  oasis build --workspace examples/hello --verbose";
    ]

let report_error message =
  prerr_endline ("oasis: " ^ message);
  1

let parse_build_args args =
  let rec loop options = function
    | [] -> Ok { options with targets = List.rev options.targets }
    | "--workspace" :: dir :: rest ->
        loop { options with workspace_dir = dir } rest
    | "--workspace" :: [] -> Error "--workspace requires a directory"
    | ("--verbose" | "-v") :: rest ->
        loop { options with verbose = true } rest
    | "--help" :: _ -> Error (usage ())
    | option :: _ when String_util.starts_with ~prefix:"-" option ->
        Error (Printf.sprintf "unknown option '%s'" option)
    | target :: rest -> loop { options with targets = target :: options.targets } rest
  in
  loop { workspace_dir = "."; verbose = false; targets = [] } args

let run argv =
  match Array.to_list argv with
  | _program :: "build" :: args -> (
      match parse_build_args args with
      | Error message -> report_error message
      | Ok options ->
          if not (Fs.is_directory options.workspace_dir) then
            report_error
              (Printf.sprintf "workspace directory does not exist: %s"
                 options.workspace_dir)
          else
            let manifest_path =
              Filename.concat options.workspace_dir Manifest.default_filename
            in
            if not (Fs.exists manifest_path) then
              report_error
                (Printf.sprintf "manifest not found: %s" manifest_path)
            else
              (match Manifest.load manifest_path with
              | Error message -> report_error message
              | Ok workspace -> (
                  match
                    Builder.build ~workspace_root:options.workspace_dir
                      ~verbose:options.verbose
                      ~requested_targets:options.targets workspace
                  with
                  | Ok _ -> 0
                  | Error message -> report_error message)))
  | _ -> report_error (usage ())
