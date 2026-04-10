type target_actions = {
  target : Manifest.target;
  out_dir : string;
  pipeline : Builder.resolved_pipeline;
  action_results : Builder.action_result list;
}

let ( let* ) = Result.bind

let resolve_profile workspace = function
  | Some profile when String.trim profile <> "" -> profile
  | Some _ | None -> Manifest.default_profile workspace

let actionful_targets ~workspace_root ~verbose ~profile requested_targets
    workspace =
  let workspace_root = Fs.realpath workspace_root in
  let profile = resolve_profile workspace profile in
  let* order = Builder.resolve_build_order workspace requested_targets in
  let rec loop acc = function
    | [] -> Ok (List.rev acc)
    | target :: rest ->
        let* pipeline =
          Builder.resolve_pipeline ~workspace_root workspace ~profile target
        in
        if pipeline.Builder.actions = [] then loop acc rest
        else
          let out_dir = Layout.target_out_dir ~profile workspace_root target in
          let* action_results =
            Builder.run_actions ~verbose ~mode:Builder.Materialize
              ~workspace_root ~out_dir ~target ~pipeline
          in
          loop ({ target; out_dir; pipeline; action_results } :: acc) rest
  in
  loop [] order

let action_results_regenerated results =
  List.exists
    (fun (result : Builder.action_result) ->
      match result.execution with
      | Builder.Action_cached -> false
      | Builder.Action_regenerated _ | Builder.Action_planned _ -> true)
    results

let render_target_report target_actions =
  let target = target_actions.target in
  let status =
    if action_results_regenerated target_actions.action_results then
      "Generated action outputs for"
    else "Up to date actions for"
  in
  Printf.sprintf "%s %s %s -> %s" status
    (Manifest.target_kind_name target)
    (Manifest.target_display_name target)
    (Builder.generated_root target_actions.out_dir)

let render_report target_actions =
  match target_actions with
  | [] -> "No declared actions for requested targets.\n"
  | target_actions ->
      String.concat "\n" (List.map render_target_report target_actions) ^ "\n"

let run ~workspace_root ~verbose ?profile ~requested_targets workspace =
  actionful_targets ~workspace_root ~verbose ~profile requested_targets workspace
