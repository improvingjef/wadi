type target_report = {
  target : Manifest.target;
  direct_workspace_deps : string list;
  closure_packages : string list;
  package_resolution : Toolchain.package_resolution;
}

type report = {
  workspace_name : string option;
  requested_targets : string list;
  ocamlfind : Toolchain.resolved_command;
  package_roots : (string list, string) result;
  targets : target_report list;
}

let ( let* ) = Result.bind

let index_targets workspace =
  let table = Hashtbl.create (List.length workspace.Manifest.targets) in
  List.iter
    (fun target ->
      Hashtbl.replace table (Manifest.target_name target) target)
    workspace.Manifest.targets;
  table

let resolve_targets workspace requested_targets =
  let requested_targets = String_util.dedup_preserve requested_targets in
  if requested_targets = [] then Ok workspace.Manifest.targets
  else
    let index = index_targets workspace in
    let rec loop acc = function
      | [] -> Ok (List.rev acc)
      | name :: rest -> (
          match Hashtbl.find_opt index name with
          | Some target -> loop (target :: acc) rest
          | None -> Error (Printf.sprintf "unknown target '%s'" name))
    in
    loop [] requested_targets

let effective_packages index target =
  let seen = Hashtbl.create 8 in
  let rec collect_library dependent_name name =
    if Hashtbl.mem seen name then Ok []
    else (
      Hashtbl.replace seen name ();
      match Hashtbl.find_opt index name with
      | Some (Manifest.Library library) ->
          let* dependency_packages =
            collect_many library.name library.Manifest.deps
          in
          Ok
            (String_util.dedup_preserve
               (library.packages @ dependency_packages))
      | Some dependency_target ->
          Error
            (Printf.sprintf
               "target '%s' depends on %s '%s'; only libraries may be dependencies"
               dependent_name
               (Manifest.target_kind_name dependency_target) name)
      | None ->
          Error
            (Printf.sprintf "target '%s' depends on unknown target '%s'"
               dependent_name name))
  and collect_many dependent_name names =
    let rec loop acc = function
      | [] -> Ok (List.rev acc |> List.concat |> String_util.dedup_preserve)
      | name :: rest ->
          let* packages = collect_library dependent_name name in
          loop (packages :: acc) rest
    in
    loop [] names
  in
  let direct_packages = Manifest.target_packages target in
  let* dependency_packages =
    collect_many (Manifest.target_name target) (Manifest.target_deps target)
  in
  Ok (String_util.dedup_preserve (direct_packages @ dependency_packages))

let report_for_targets ~session workspace requested_targets =
  let* targets = resolve_targets workspace requested_targets in
  let index = index_targets workspace in
  let rec loop acc = function
    | [] ->
        Ok
          {
            workspace_name = workspace.Manifest.name;
            requested_targets;
            ocamlfind = Toolchain.resolved_ocamlfind_report ~session ();
            package_roots = Toolchain.package_search_roots ~session ();
            targets = List.rev acc;
          }
    | target :: rest ->
        let* closure_packages = effective_packages index target in
        let* package_resolution =
          Toolchain.resolve_packages ~session closure_packages
          |> Result.map_error (fun message ->
                 Printf.sprintf "%s '%s' requires %s"
                   (Manifest.target_kind_name target)
                   (Manifest.target_name target) message)
        in
        loop
          ({
             target;
             direct_workspace_deps = Manifest.target_deps target;
             closure_packages;
             package_resolution;
           }
          :: acc)
          rest
  in
  loop [] targets

let joined_names = function
  | [] -> "none"
  | names -> String.concat ", " names

let render_package_roots = function
  | Ok [] -> [ "Package-roots:"; "- none" ]
  | Ok roots -> "Package-roots:" :: List.map (fun root -> "- " ^ root) roots
  | Error message -> [ "Package-roots-error: " ^ String.trim message ]

let render_target_report (report : target_report) =
  let package_lines =
    match report.package_resolution.Toolchain.package_paths with
    | [] -> [ "- none" ]
    | package_paths ->
        List.map
          (fun (package_name, package_path) ->
            Printf.sprintf "- %s -> %s" package_name package_path)
          package_paths
  in
  [
    Printf.sprintf "Target: %s"
      (Manifest.target_display_name report.target);
    "Kind: " ^ Manifest.target_kind_name report.target;
    "Workspace-deps: " ^ joined_names report.direct_workspace_deps;
    "External-packages: " ^ joined_names report.closure_packages;
    "Resolved-packages:";
  ]
  @ package_lines

let render_report (report : report) =
  String.concat "\n"
    ([
       ("Workspace: "
       ^
       match report.workspace_name with
       | Some name -> name
       | None -> "unnamed");
       ("Requested-targets: "
       ^
       if report.requested_targets = [] then "all"
       else String.concat ", " report.requested_targets);
       Toolchain.render_command_report "ocamlfind" report.ocamlfind;
     ]
    @ render_package_roots report.package_roots
    @ List.concat_map
        (fun target_report -> "" :: render_target_report target_report)
        report.targets
    @ [ "" ])
