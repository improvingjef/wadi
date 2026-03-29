type promotion_status =
  | Promoted
  | Up_to_date

type promoted_output = {
  target : Manifest.target;
  action_name : string;
  relative_path : string;
  generated_path : string;
  destination_path : string;
  status : promotion_status;
}

let ( let* ) = Result.bind

let source_like_promotion_error target action_name relative_path =
  Error
    (Printf.sprintf
       "target '%s' action '%s' output '%s' looks like checked-in OCaml source; \
        declare it under checked_in_sources = [...] if it is an intentional \
        promoted snapshot"
       (Manifest.target_name target) action_name relative_path)

let promote_output ~generated_path ~destination_path =
  if Fs.exists destination_path
     && Builder.digest_path destination_path = Builder.digest_path generated_path
  then Up_to_date
  else (
    if Fs.exists destination_path then Fs.remove_tree destination_path;
    Builder.copy_path ~src:generated_path ~dst:destination_path;
    Promoted)

let promote_action_outputs ~workspace_root (target_actions : Actioner.target_actions)
    =
  let target = target_actions.target in
  let target_dir = Manifest.target_dir target in
  let rec pair_actions acc actions action_results =
    match (actions, action_results) with
    | [], [] -> Ok (List.rev acc)
    | (action : Manifest.action) :: action_rest, action_result :: result_rest ->
        let rec pair_outputs acc outputs generated_paths =
          match (outputs, generated_paths) with
          | [], [] -> Ok acc
          | relative_path :: output_rest, generated_path :: path_rest ->
              if
                Builder.is_source_path relative_path
                && not
                     (Manifest.action_output_is_checked_in_source action
                        relative_path)
              then
                source_like_promotion_error target action.name relative_path
              else
                let destination_path =
                  Filename.concat workspace_root
                    (Filename.concat target_dir relative_path)
                in
                let status = promote_output ~generated_path ~destination_path in
                pair_outputs
                  ({
                     target;
                     action_name = action.name;
                     relative_path;
                     generated_path;
                     destination_path;
                     status;
                   }
                  :: acc)
                  output_rest path_rest
          | [], _ :: _ | _ :: _, [] ->
              Error
                (Printf.sprintf
                   "internal error: action '%s' output planning drifted during \
                    promotion"
                   action.name)
        in
        let* acc =
          pair_outputs acc action.outputs action_result.Builder.output_paths
        in
        pair_actions acc action_rest result_rest
    | [], _ :: _ | _ :: _, [] ->
        Error "internal error: action promotion target results drifted during execution"
  in
  pair_actions [] target_actions.pipeline.Builder.actions
    target_actions.action_results

let promote ~workspace_root ~verbose ?profile ~requested_targets workspace =
  let workspace_root = Fs.realpath workspace_root in
  let selected_names = String_util.dedup_preserve requested_targets in
  let selected = Hashtbl.create (List.length selected_names) in
  List.iter (fun name -> Hashtbl.replace selected name ()) selected_names;
  let* target_actions =
    Actioner.run ~workspace_root ~verbose ?profile ~requested_targets workspace
  in
  let rec loop acc = function
    | [] -> Ok (List.rev acc)
    | (target_action : Actioner.target_actions) :: rest ->
        if selected_names <> []
           && not (Hashtbl.mem selected (Manifest.target_name target_action.target))
        then
          loop acc rest
        else
          let* promoted = promote_action_outputs ~workspace_root target_action in
          loop (List.rev_append promoted acc) rest
  in
  loop [] target_actions

let render_promoted_output promoted =
  let status =
    match promoted.status with
    | Promoted -> "Promoted"
    | Up_to_date -> "Up to date promoted"
  in
  Printf.sprintf "%s action %s output %s for %s %s -> %s" status
    promoted.action_name promoted.relative_path
    (Manifest.target_kind_name promoted.target)
    (Manifest.target_display_name promoted.target)
    promoted.destination_path

let render_report promoted_outputs =
  match promoted_outputs with
  | [] -> "No promotable action outputs for requested targets.\n"
  | promoted_outputs ->
      String.concat "\n" (List.map render_promoted_output promoted_outputs) ^ "\n"
