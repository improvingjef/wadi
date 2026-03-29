type target_plan = {
  name : string;
  ordered_modules : string list;
}

type workspace_plan = {
  common_modules : string list;
  executable : target_plan;
  test : target_plan;
}

let ( let* ) = Result.bind

let collect_results items f =
  let rec loop acc = function
    | [] -> Ok (List.rev acc)
    | item :: rest ->
        let* value = f item in
        loop (value :: acc) rest
  in
  loop [] items

let find_single_target label select workspace =
  match List.filter_map select workspace.Manifest.targets with
  | [ target ] -> Ok target
  | [] ->
      Error
        (Printf.sprintf
           "bootstrap manifest requires exactly one %s target, found none" label)
  | targets ->
      Error
        (Printf.sprintf
           "bootstrap manifest requires exactly one %s target, found %d" label
           (List.length targets))

let index_targets workspace =
  let table = Hashtbl.create (List.length workspace.Manifest.targets) in
  List.iter
    (fun target -> Hashtbl.replace table (Manifest.target_name target) target)
    workspace.Manifest.targets;
  table

let rec dependency_packages index seen name =
  if Hashtbl.mem seen name then Ok []
  else (
    Hashtbl.add seen name ();
    match Hashtbl.find_opt index name with
    | None ->
        Error
          (Printf.sprintf
             "bootstrap manifest refers to unknown dependency '%s'" name)
    | Some (Manifest.Library library) ->
        let* packages = collect_results library.deps (dependency_packages index seen) in
        Ok
          (String_util.dedup_preserve
             (library.packages @ List.concat packages))
    | Some target ->
        Error
          (Printf.sprintf
             "bootstrap manifest dependency '%s' resolved to %s; only libraries \
              can contribute bootstrap packages"
             name (Manifest.target_kind_name target)))

let effective_packages index target =
  let* packages =
    collect_results (Manifest.target_deps target)
      (dependency_packages index (Hashtbl.create 8))
  in
  Ok
    (String_util.dedup_preserve
       (Manifest.target_packages target @ List.concat packages))

let ordered_modules ~workspace_root ~target_kind ~target_name ~dir ~modules
    ~packages =
  let* package_resolution = Toolchain.resolve_packages packages in
  let* sources = Builder.source_descriptors ~workspace_root ~dir modules in
  Builder.infer_module_order ~verbose:false ~target_kind ~target_name
    package_resolution sources

let plan ~workspace_root workspace =
  let* _ = Builder.resolve_build_order workspace [] in
  let index = index_targets workspace in
  let* library =
    find_single_target "library"
      (function
        | Manifest.Library library -> Some library
        | Manifest.Executable _ | Manifest.Test _ -> None)
      workspace
  in
  let* executable =
    find_single_target "executable"
      (function
        | Manifest.Executable executable -> Some executable
        | Manifest.Library _ | Manifest.Test _ -> None)
      workspace
  in
  let* test =
    find_single_target "test"
      (function
        | Manifest.Test test -> Some test
        | Manifest.Library _ | Manifest.Executable _ -> None)
      workspace
  in
  let library_target = Manifest.Library library in
  let executable_target = Manifest.Executable executable in
  let test_target = Manifest.Test test in
  let* common_modules =
    let* packages = effective_packages index library_target in
    ordered_modules ~workspace_root ~target_kind:"library"
      ~target_name:library.name ~dir:library.dir ~modules:library.modules
      ~packages
  in
  let* executable_modules =
    let* packages = effective_packages index executable_target in
    let* ordered =
      ordered_modules ~workspace_root ~target_kind:"executable"
        ~target_name:executable.name ~dir:executable.dir
        ~modules:executable.modules ~packages
    in
    Ok (ordered @ [ executable.main ])
  in
  let* test_modules =
    let* packages = effective_packages index test_target in
    let* ordered =
      ordered_modules ~workspace_root ~target_kind:"test" ~target_name:test.name
        ~dir:test.dir ~modules:test.modules ~packages
    in
    Ok (ordered @ [ test.main ])
  in
  Ok
    {
      common_modules;
      executable = { name = executable.name; ordered_modules = executable_modules };
      test = { name = test.name; ordered_modules = test_modules };
    }

let object_path stem = Printf.sprintf "$(OBJ_DIR)/%s.cmx" stem

let object_list modules = String.concat " " (List.map object_path modules)

let last = function
  | [] -> None
  | items -> Some (List.hd (List.rev items))

let chain_rules modules predecessor =
  let rec loop previous acc = function
    | [] -> List.rev acc
    | module_name :: rest ->
        let acc =
          match previous with
          | None -> acc
          | Some dependency ->
              (Printf.sprintf "%s: %s" (object_path module_name)
                 (object_path dependency))
              :: acc
        in
        loop (Some module_name) acc rest
  in
  loop predecessor [] modules

let render_makefile_from_plan plan =
  let common_objects = object_list plan.common_modules in
  let executable_objects = object_list plan.executable.ordered_modules in
  let test_objects = object_list plan.test.ordered_modules in
  let common_tail = last plan.common_modules in
  let lines =
    [
      "# Generated by scripts/generate_bootstrap_makefile.ml from oasis.toml.";
      "# Edit oasis.toml instead of this file.";
      ("COMMON_OBJS := " ^ common_objects);
      ("APP_OBJS := $(COMMON_OBJS)"
      ^ if executable_objects = "" then "" else " " ^ executable_objects);
      ("TEST_OBJS := $(COMMON_OBJS)"
      ^ if test_objects = "" then "" else " " ^ test_objects);
      "";
    ]
    @ chain_rules plan.common_modules None
    @ chain_rules plan.executable.ordered_modules common_tail
    @ chain_rules plan.test.ordered_modules common_tail
    @ [
        "";
        Printf.sprintf "$(BIN_DIR)/%s: $(APP_OBJS) | $(BIN_DIR)"
          plan.executable.name;
        "\t$(OCAMLOPT) $(OCAMLFLAGS) $(UNIX_FLAGS) -I $(OBJ_DIR) -o $@ $(UNIX_ARCHIVE) $(APP_OBJS)";
        "";
        Printf.sprintf "$(BIN_DIR)/%s: $(TEST_OBJS) | $(BIN_DIR)" plan.test.name;
        "\t$(OCAMLOPT) $(OCAMLFLAGS) $(UNIX_FLAGS) -I $(OBJ_DIR) -o $@ $(UNIX_ARCHIVE) $(TEST_OBJS)";
      ]
  in
  String.concat "\n" lines ^ "\n"

let render_makefile ~manifest_path =
  let* workspace = Manifest.load manifest_path in
  let workspace_root = Fs.realpath (Filename.dirname manifest_path) in
  let* workspace_plan = plan ~workspace_root workspace in
  Ok (render_makefile_from_plan workspace_plan)
