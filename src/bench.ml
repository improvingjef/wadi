type summary = {
  name : string;
  package_path : string option;
  executable_name : string;
  binary : string;
  argv : string list;
  description : string option;
  warmup : int;
  iterations : int;
  samples : float list;
  min_seconds : float;
  max_seconds : float;
  mean_seconds : float;
  median_seconds : float;
}

type benchmark_request = {
  name : string;
  package_path : string option;
  executable : Manifest.executable;
  argv : string list;
  env : Manifest.env_binding list;
  warmup : int;
  iterations : int;
  description : string option;
}

let ( let* ) = Result.bind

let default_warmup = 1

let default_iterations = 5

let display_name name package_path =
  name ^ Manifest.package_suffix package_path

let executable_targets workspace =
  List.filter_map
    (function
      | Manifest.Executable executable -> Some executable
      | Manifest.Library _ | Manifest.Test _ -> None)
    workspace.Manifest.targets

let resolve_executable workspace name =
  match
    List.find_opt
      (fun target -> Manifest.target_name target = name)
      workspace.Manifest.targets
  with
  | Some (Manifest.Executable executable) -> Ok executable
  | Some (Manifest.Library _) ->
      Error
        (Printf.sprintf
           "target '%s' is a library; wadi bench only supports executables or [bench.*] declarations"
           name)
  | Some (Manifest.Test _) ->
      Error
        (Printf.sprintf
           "target '%s' is a test; wadi bench only supports executables or [bench.*] declarations"
           name)
  | None -> Error (Printf.sprintf "unknown target '%s'" name)

let executable_request ?(warmup = default_warmup)
    ?(iterations = default_iterations) (target : Manifest.executable) =
  {
    name = target.name;
    package_path = target.package_path;
    executable = target;
    argv = [];
    env = [];
    warmup;
    iterations;
    description = None;
  }

let declared_bench_request workspace ?warmup ?iterations
    (bench : Manifest.bench_target) =
  let* executable = resolve_executable workspace bench.executable in
  Ok
    {
      name = bench.name;
      package_path = bench.package_path;
      executable;
      argv = bench.argv;
      env = bench.env;
      warmup =
        (match warmup with
        | Some warmup -> warmup
        | None -> (
            match bench.warmup with
            | Some warmup -> warmup
            | None -> default_warmup));
      iterations =
        (match iterations with
        | Some iterations -> iterations
        | None -> (
            match bench.iterations with
            | Some iterations -> iterations
            | None -> default_iterations));
      description = bench.description;
    }

let resolve_requested_targets workspace ?warmup ?iterations requested_targets =
  let requested_targets = String_util.dedup_preserve requested_targets in
  if requested_targets = [] then
    match workspace.Manifest.benches with
    | bench :: benches ->
        let rec loop acc = function
          | [] -> Ok (List.rev acc)
          | bench :: rest ->
              let* request =
                declared_bench_request workspace ?warmup ?iterations bench
              in
              loop (request :: acc) rest
        in
        loop [] (bench :: benches)
    | [] -> (
        match executable_targets workspace with
        | [] -> Error "workspace does not define any benchmarks or executables to benchmark"
        | executables ->
            Ok
              (List.map
                 (fun executable ->
                   executable_request ?warmup ?iterations executable)
                 executables))
  else
    let rec loop acc = function
      | [] -> Ok (List.rev acc)
      | name :: rest -> (
          match Manifest.find_bench workspace name with
          | Some bench ->
              let* request =
                declared_bench_request workspace ?warmup ?iterations bench
              in
              loop (request :: acc) rest
          | None ->
              let* executable = resolve_executable workspace name in
              loop
                (executable_request ?warmup ?iterations executable :: acc)
                rest)
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

let summarize ~(request : benchmark_request) ~binary samples =
  let sorted = List.sort Float.compare samples in
  let count = List.length sorted in
  let total = List.fold_left ( +. ) 0.0 sorted in
  let median_seconds =
    if count mod 2 = 1 then nth sorted (count / 2)
    else (nth sorted ((count / 2) - 1) +. nth sorted (count / 2)) /. 2.0
  in
  {
    name = request.name;
    package_path = request.package_path;
    executable_name = request.executable.name;
    binary;
    argv = request.argv;
    description = request.description;
    warmup = request.warmup;
    iterations = request.iterations;
    samples;
    min_seconds = List.hd sorted;
    max_seconds = List.hd (List.rev sorted);
    mean_seconds = total /. float_of_int count;
    median_seconds;
  }

let run_sample ~verbose ~env binary argv =
  let started = Unix.gettimeofday () in
  let outcome = Process.run_capture ~verbose ~env binary argv in
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

let benchmark_target ~verbose (request : benchmark_request) binary =
  let rec run_warmups remaining =
    if remaining <= 0 then Ok ()
    else
      let* _ = run_sample ~verbose ~env:request.env binary request.argv in
      run_warmups (remaining - 1)
  in
  let* () = run_warmups request.warmup in
  let* samples =
    repeat request.iterations (fun () ->
        run_sample ~verbose ~env:request.env binary request.argv)
  in
  Ok (summarize ~request ~binary samples)

let json_string value = "\"" ^ String_util.json_escape value ^ "\""

let json_float value = Printf.sprintf "%.9f" value

let json_string_option = function
  | Some value -> json_string value
  | None -> "null"

let render_summary (summary : summary) =
  let details =
    [
      (if summary.executable_name = summary.name then None
       else Some ("  executable: " ^ summary.executable_name));
      (match summary.description with
      | Some description when String.trim description <> "" ->
          Some ("  description: " ^ description)
      | Some _ | None -> None);
      (match summary.argv with
      | [] -> None
      | argv -> Some ("  argv: " ^ String.concat " " argv));
    ]
    |> List.filter_map Fun.id
  in
  String.concat "\n"
    ([
       Printf.sprintf "Benchmark %s -> %s"
         (display_name summary.name summary.package_path)
         summary.binary;
     ]
    @ details
    @ [
        Printf.sprintf "  warmup: %d" summary.warmup;
        Printf.sprintf "  iterations: %d" summary.iterations;
        Printf.sprintf "  min: %.6fs" summary.min_seconds;
        Printf.sprintf "  mean: %.6fs" summary.mean_seconds;
        Printf.sprintf "  median: %.6fs" summary.median_seconds;
        Printf.sprintf "  max: %.6fs" summary.max_seconds;
      ])

let render_report summaries =
  String.concat "\n\n" (List.map render_summary summaries) ^ "\n"

let render_json_report summaries =
  let render_summary_json (summary : summary) =
    String.concat "\n"
      [
        "    {";
        "      \"target\": " ^ json_string summary.name ^ ",";
        "      \"package_path\": " ^ json_string_option summary.package_path ^ ",";
        "      \"executable\": " ^ json_string summary.executable_name ^ ",";
        "      \"binary\": " ^ json_string summary.binary ^ ",";
        "      \"argv\": ["
        ^ String.concat ", " (List.map json_string summary.argv)
        ^ "],";
        "      \"description\": " ^ json_string_option summary.description ^ ",";
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

let report ~workspace_root ~verbose ~backend_request ?profile ?warmup
    ?iterations ~requested_targets workspace =
  let* targets =
    resolve_requested_targets workspace ?warmup ?iterations requested_targets
  in
  let* build_result =
    Builder.build ~workspace_root ~verbose
      ~requested_targets:
        (List.map
           (fun (target : benchmark_request) -> target.executable.name)
           targets)
      ~backend_request ?profile workspace
  in
  let rec loop (acc : summary list) = function
    | [] -> Ok (List.rev acc)
    | (target : benchmark_request) :: rest -> (
        match
          find_built_executable target.executable.name
            build_result.Builder.artifacts
        with
        | Some binary ->
            let* summary = benchmark_target ~verbose target binary in
            loop (summary :: acc) rest
        | None ->
            Error
              (Printf.sprintf
                 "internal error: build completed without executable '%s'"
                 target.executable.name))
  in
  loop [] targets
