type summary = {
  name : string;
  package_path : string option;
  binary : string;
  warmup : int;
  iterations : int;
  samples : float list;
  min_seconds : float;
  max_seconds : float;
  mean_seconds : float;
  median_seconds : float;
}

let ( let* ) = Result.bind

let display_name name package_path =
  name ^ Manifest.package_suffix package_path

let executable_targets workspace =
  List.filter_map
    (function
      | Manifest.Executable executable -> Some executable
      | Manifest.Library _ | Manifest.Test _ -> None)
    workspace.Manifest.targets

let resolve_requested_targets workspace requested_targets =
  let requested_targets = String_util.dedup_preserve requested_targets in
  if requested_targets = [] then
    match executable_targets workspace with
    | [] -> Error "workspace does not define any executables to benchmark"
    | executables -> Ok executables
  else
    let rec loop acc = function
      | [] -> Ok (List.rev acc)
      | name :: rest -> (
          match
            List.find_opt
              (fun target -> Manifest.target_name target = name)
              workspace.Manifest.targets
          with
          | Some (Manifest.Executable executable) -> loop (executable :: acc) rest
          | Some (Manifest.Library _) ->
              Error
                (Printf.sprintf
                   "target '%s' is a library; oasis bench only supports executables"
                   name)
          | Some (Manifest.Test _) ->
              Error
                (Printf.sprintf
                   "target '%s' is a test; oasis bench only supports executables"
                   name)
          | None -> Error (Printf.sprintf "unknown target '%s'" name))
    in
    loop [] requested_targets

let find_built_executable name artifacts =
  List.find_map
    (function
      | Builder.Built_executable executable when executable.name = name ->
          Some executable.binary
      | _ -> None)
    artifacts

let nth values index =
  let rec loop index = function
    | [] -> invalid_arg "nth"
    | value :: _ when index = 0 -> value
    | _ :: rest -> loop (index - 1) rest
  in
  loop index values

let summarize ~(target : Manifest.executable) ~binary ~warmup ~iterations
    samples =
  let sorted = List.sort Float.compare samples in
  let count = List.length sorted in
  let total = List.fold_left ( +. ) 0.0 sorted in
  let median_seconds =
    if count mod 2 = 1 then nth sorted (count / 2)
    else (nth sorted ((count / 2) - 1) +. nth sorted (count / 2)) /. 2.0
  in
  {
    name = target.name;
    package_path = target.package_path;
    binary;
    warmup;
    iterations;
    samples;
    min_seconds = List.hd sorted;
    max_seconds = List.hd (List.rev sorted);
    mean_seconds = total /. float_of_int count;
    median_seconds;
  }

let run_sample ~verbose binary =
  let started = Unix.gettimeofday () in
  let outcome = Process.run_capture ~verbose binary [] in
  let elapsed = Unix.gettimeofday () -. started in
  if outcome.status = 0 then Ok elapsed
  else
    Error
      (Printf.sprintf "benchmark command failed: %s\n%s" outcome.command
         outcome.output)

let rec repeat count f =
  if count <= 0 then Ok []
  else
    let* value = f () in
    let* values = repeat (count - 1) f in
    Ok (value :: values)

let benchmark_target ~verbose ~warmup ~iterations
    (target : Manifest.executable) binary =
  let rec run_warmups remaining =
    if remaining <= 0 then Ok ()
    else
      let* _ = run_sample ~verbose binary in
      run_warmups (remaining - 1)
  in
  let* () = run_warmups warmup in
  let* samples = repeat iterations (fun () -> run_sample ~verbose binary) in
  Ok (summarize ~target ~binary ~warmup ~iterations samples)

let json_string value = "\"" ^ String_util.json_escape value ^ "\""

let json_float value = Printf.sprintf "%.9f" value

let json_string_option = function
  | Some value -> json_string value
  | None -> "null"

let render_summary summary =
  String.concat "\n"
    [
      Printf.sprintf "Benchmark %s -> %s"
        (display_name summary.name summary.package_path)
        summary.binary;
      Printf.sprintf "  warmup: %d" summary.warmup;
      Printf.sprintf "  iterations: %d" summary.iterations;
      Printf.sprintf "  min: %.6fs" summary.min_seconds;
      Printf.sprintf "  mean: %.6fs" summary.mean_seconds;
      Printf.sprintf "  median: %.6fs" summary.median_seconds;
      Printf.sprintf "  max: %.6fs" summary.max_seconds;
    ]

let render_report summaries =
  String.concat "\n\n" (List.map render_summary summaries) ^ "\n"

let render_json_report summaries =
  let render_summary_json summary =
    String.concat "\n"
      [
        "    {";
        "      \"target\": " ^ json_string summary.name ^ ",";
        "      \"package_path\": " ^ json_string_option summary.package_path ^ ",";
        "      \"binary\": " ^ json_string summary.binary ^ ",";
        "      \"warmup\": " ^ string_of_int summary.warmup ^ ",";
        "      \"iterations\": " ^ string_of_int summary.iterations ^ ",";
        "      \"min_seconds\": " ^ json_float summary.min_seconds ^ ",";
        "      \"mean_seconds\": " ^ json_float summary.mean_seconds ^ ",";
        "      \"median_seconds\": " ^ json_float summary.median_seconds ^ ",";
        "      \"max_seconds\": " ^ json_float summary.max_seconds ^ ",";
        "      \"samples_seconds\": ["
        ^ String.concat ", " (List.map json_float summary.samples)
        ^ "]";
        "    }";
      ]
  in
  String.concat "\n"
    [
      "{";
      "  \"results\": [";
      String.concat ",\n" (List.map render_summary_json summaries);
      "  ]";
      "}";
      "";
    ]

let report ~workspace_root ~verbose ~backend_request ?profile ~warmup
    ~iterations ~requested_targets workspace =
  let* targets = resolve_requested_targets workspace requested_targets in
  let* build_result =
    Builder.build ~workspace_root ~verbose
      ~requested_targets:
        (List.map (fun (target : Manifest.executable) -> target.name) targets)
      ~backend_request ?profile workspace
  in
  let rec loop (acc : summary list) = function
    | [] -> Ok (List.rev acc)
    | (target : Manifest.executable) :: rest -> (
        match find_built_executable target.name build_result.Builder.artifacts with
        | Some binary ->
            let* summary = benchmark_target ~verbose ~warmup ~iterations target binary in
            loop (summary :: acc) rest
        | None ->
            Error
              (Printf.sprintf
                 "internal error: build completed without executable '%s'"
                 target.name))
  in
  loop [] targets
