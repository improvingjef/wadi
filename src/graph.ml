type target_plan = {
  target : Manifest.target;
  direct_workspace_deps : string list;
  effective_packages : string list;
  actions : string list;
  preprocessors : string list;
  ppx_tools : string list;
  module_order : string list;
}

type report = {
  workspace_name : string option;
  profile : string;
  requested_targets : string list;
  target_plans : target_plan list;
}

let ( let* ) = Result.bind

let resolve_profile workspace profile =
  match profile with
  | Some profile when String.trim profile <> "" -> profile
  | Some _ | None -> Manifest.default_profile workspace

let render_names label names =
  label ^ ": " ^ match names with [] -> "none" | names -> String.concat ", " names

let package_names resolution = resolution.Toolchain.packages

let plan ~workspace_root ?(requested_targets = []) ?(backend_request = Toolchain.Auto)
    ?profile workspace =
  let workspace_root = Fs.realpath workspace_root in
  let manifest_path = Filename.concat workspace_root Manifest.default_filename in
  let session = Toolchain.create_session () in
  let profile = resolve_profile workspace profile in
  let* backend = Toolchain.resolve_backend ~session backend_request in
  let* compiler_version = Toolchain.compiler_version ~session backend in
  let* order = Builder.resolve_build_order workspace requested_targets in
  let index = Builder.index_targets workspace in
  let library_outputs = Hashtbl.create 8 in
  let rec loop acc = function
    | [] ->
        Ok
          {
            workspace_name = workspace.Manifest.name;
            profile;
            requested_targets;
            target_plans = List.rev acc;
          }
    | Manifest.Library library :: rest ->
        let* description =
          Builder.describe_library ~mode:Builder.Plan_only ~session ~workspace_root
            ~verbose:false ~manifest_path ~backend_request ~backend ~compiler_version
            ~profile workspace library library_outputs
        in
        let graph_dep_dirs =
          String_util.dedup_preserve
            (List.concat_map
               (fun dep_name ->
                 match Hashtbl.find_opt library_outputs dep_name with
                 | Some output -> output.out_dir :: output.transitive_include_dirs
                 | None -> [])
               library.Manifest.deps)
        in
        Hashtbl.replace library_outputs library.name
          {
            Builder.archive = description.archive;
            out_dir = description.out_dir;
            fingerprint = description.fingerprint;
            packages = description.effective_packages;
            transitive_include_dirs = graph_dep_dirs;
          };
        loop
          ({
             target = Manifest.Library library;
             direct_workspace_deps = library.deps;
             effective_packages = package_names description.package_resolution;
             actions = List.map Manifest.action_display_name description.pipeline.actions;
             preprocessors =
               List.map Manifest.command_tool_display_name
                 description.pipeline.preprocessors;
             ppx_tools =
               List.map Manifest.ppx_tool_display_name description.pipeline.ppx_tools;
             module_order = description.ordered_modules;
           }
          :: acc)
          rest
    | Manifest.Executable executable :: rest ->
        let* description =
          Builder.describe_runnable ~mode:Builder.Plan_only ~session ~workspace_root
            ~verbose:false ~manifest_path ~backend_request ~backend ~compiler_version
            ~profile ~kind:Builder.Executable_kind workspace executable order index
            library_outputs
        in
        loop
          ({
             target = Manifest.Executable executable;
             direct_workspace_deps = executable.deps;
             effective_packages = package_names description.package_resolution;
             actions = List.map Manifest.action_display_name description.pipeline.actions;
             preprocessors =
               List.map Manifest.command_tool_display_name
                 description.pipeline.preprocessors;
             ppx_tools =
               List.map Manifest.ppx_tool_display_name description.pipeline.ppx_tools;
             module_order = description.source_order;
           }
          :: acc)
          rest
    | Manifest.Test test :: rest ->
        let* description =
          Builder.describe_runnable ~mode:Builder.Plan_only ~session ~workspace_root
            ~verbose:false ~manifest_path ~backend_request ~backend ~compiler_version
            ~profile ~kind:Builder.Test_kind workspace test order index library_outputs
        in
        loop
          ({
             target = Manifest.Test test;
             direct_workspace_deps = test.deps;
             effective_packages = package_names description.package_resolution;
             actions = List.map Manifest.action_display_name description.pipeline.actions;
             preprocessors =
               List.map Manifest.command_tool_display_name
                 description.pipeline.preprocessors;
             ppx_tools =
               List.map Manifest.ppx_tool_display_name description.pipeline.ppx_tools;
             module_order = description.source_order;
           }
          :: acc)
          rest
  in
  loop [] order

let render_target_plan index (plan : target_plan) =
  String.concat "\n"
    [
      Printf.sprintf "%d. %s %s" index
        (Manifest.target_kind_name plan.target)
        (Manifest.target_display_name plan.target);
      "   " ^ render_names "depends-on" plan.direct_workspace_deps;
      "   " ^ render_names "packages" plan.effective_packages;
      "   " ^ render_names "actions" plan.actions;
      "   " ^ render_names "preprocessors" plan.preprocessors;
      "   " ^ render_names "ppx" plan.ppx_tools;
      "   " ^ render_names "module-order" plan.module_order;
    ]

let render_report (report : report) =
  let header =
    [
      ("Workspace: "
      ^ match report.workspace_name with Some name -> name | None -> "unnamed");
      "Profile: " ^ report.profile;
      ("Requested-targets: "
      ^
      if report.requested_targets = [] then "all"
      else String.concat ", " report.requested_targets);
      "Build-order:";
    ]
  in
  String.concat "\n"
    (header
    @ List.mapi
        (fun index plan -> render_target_plan (index + 1) plan)
        report.target_plans
    @ [ "" ])
