type sexp =
  | Atom of string
  | List of sexp list

type raw_target_kind =
  | Library
  | Executable
  | Test

type raw_target = {
  kind : raw_target_kind;
  name : string;
  public_name : string option;
  wrapped : bool;
  dir : string;
  main : string option;
  modules : string list option;
  libraries : string list;
  actions : string list;
  preprocess : string list;
  ppx : string list;
}

type raw_action = {
  name : string;
  dir : string;
  argv : string list;
  cwd : string option;
  deps : string list;
  outputs : string list;
}

type raw_preprocessor = {
  name : string;
  argv : string list;
  cwd : string option;
  deps : string list;
}

type raw_ppx_tool = {
  name : string;
  argv : string list;
  deps : string list;
}

type migration = {
  manifest : string;
  warnings : string list;
}

type migration_acc = {
  targets : raw_target list;
  actions : raw_action list;
  preprocessors : raw_preprocessor list;
  ppx_tools : raw_ppx_tool list;
  warnings : string list;
  next_generated_id : int;
}

let ( let* ) = Result.bind

let parse_error path message = Error (Printf.sprintf "%s: %s" path message)

let rec skip_space text index =
  if index >= String.length text then index
  else
    match text.[index] with
    | ' ' | '\t' | '\r' | '\n' -> skip_space text (index + 1)
    | ';' -> skip_comment text (index + 1)
    | _ -> index

and skip_comment text index =
  if index >= String.length text then index
  else if text.[index] = '\n' then skip_space text (index + 1)
  else skip_comment text (index + 1)

let parse_string path text index =
  let buffer = Buffer.create 32 in
  let rec loop index =
    if index >= String.length text then
      parse_error path "unterminated string literal"
    else
      match text.[index] with
      | '"' -> Ok (Buffer.contents buffer, index + 1)
      | '\\' ->
          if index + 1 >= String.length text then
            parse_error path "unterminated escape sequence"
          else
            let escaped =
              match text.[index + 1] with
              | '"' -> '"'
              | '\\' -> '\\'
              | 'n' -> '\n'
              | 't' -> '\t'
              | ch -> ch
            in
            Buffer.add_char buffer escaped;
            loop (index + 2)
      | ch ->
          Buffer.add_char buffer ch;
          loop (index + 1)
  in
  loop index

let parse_atom text index =
  let rec loop stop =
    if stop >= String.length text then stop
    else
      match text.[stop] with
      | ' ' | '\t' | '\r' | '\n' | '(' | ')' | ';' -> stop
      | _ -> loop (stop + 1)
  in
  let stop = loop index in
  (String.sub text index (stop - index), stop)

let rec parse_one path text index =
  let index = skip_space text index in
  if index >= String.length text then
    parse_error path "unexpected end of file while parsing s-expression"
  else
    match text.[index] with
    | '(' -> parse_list path text (index + 1) []
    | ')' -> parse_error path "unexpected ')'"
    | '"' ->
        let* value, next_index = parse_string path text (index + 1) in
        Ok (Atom value, next_index)
    | _ ->
        let atom, next_index = parse_atom text index in
        Ok (Atom atom, next_index)

and parse_list path text index acc =
  let index = skip_space text index in
  if index >= String.length text then parse_error path "unterminated list"
  else if text.[index] = ')' then Ok (List (List.rev acc), index + 1)
  else
    let* value, next_index = parse_one path text index in
    parse_list path text next_index (value :: acc)

let parse_many path text =
  let rec loop index acc =
    let index = skip_space text index in
    if index >= String.length text then Ok (List.rev acc)
    else
      let* value, next_index = parse_one path text index in
      loop next_index (value :: acc)
  in
  loop 0 []

let field_name = function
  | List (Atom name :: _) -> Some name
  | _ -> None

let field_map fields =
  let table = Hashtbl.create (List.length fields) in
  List.iter
    (fun field ->
      match field_name field with
      | Some name -> Hashtbl.replace table name field
      | None -> ())
    fields;
  table

let field_atoms name fields =
  match Hashtbl.find_opt fields name with
  | None -> Ok None
  | Some (List (_ :: values)) ->
      let rec loop acc = function
        | [] -> Ok (Some (List.rev acc))
        | Atom value :: rest -> loop (value :: acc) rest
        | List _ :: _ ->
            Error
              (Printf.sprintf
                 "field '%s' uses a dune form this migrator does not understand"
                 name)
      in
      loop [] values
  | Some _ -> Error (Printf.sprintf "field '%s' is malformed" name)

let required_atom_field name fields =
  let* values = field_atoms name fields in
  match values with
  | Some [ value ] -> Ok value
  | Some _ ->
      Error
        (Printf.sprintf "field '%s' must contain exactly one atom/string" name)
  | None -> Error (Printf.sprintf "missing required field '%s'" name)

let optional_atom_field name fields =
  let* values = field_atoms name fields in
  match values with
  | Some [ value ] -> Ok (Some value)
  | Some _ ->
      Error
        (Printf.sprintf "field '%s' must contain exactly one atom/string" name)
  | None -> Ok None

let parse_bool_field name = function
  | "true" -> Ok true
  | "false" -> Ok false
  | value ->
      Error
        (Printf.sprintf
           "field '%s' must be true or false, not %S" name value)

let optional_bool_field name fields =
  let* value = optional_atom_field name fields in
  match value with
  | None -> Ok None
  | Some value ->
      let* parsed = parse_bool_field name value in
      Ok (Some parsed)

let optional_atom_list_field name fields =
  let* values = field_atoms name fields in
  Ok (Option.value ~default:[] values)

let field_values name fields =
  match Hashtbl.find_opt fields name with
  | None -> Ok None
  | Some (List (_ :: values)) -> Ok (Some values)
  | Some _ -> Error (Printf.sprintf "field '%s' is malformed" name)

let required_single_value_field name fields =
  let* values = field_values name fields in
  match values with
  | Some [ value ] -> Ok value
  | Some _ ->
      Error
        (Printf.sprintf "field '%s' must contain exactly one form" name)
  | None -> Error (Printf.sprintf "missing required field '%s'" name)

let optional_single_value_field name fields =
  let* values = field_values name fields in
  match values with
  | Some [ value ] -> Ok (Some value)
  | Some _ ->
      Error
        (Printf.sprintf "field '%s' must contain exactly one form" name)
  | None -> Ok None

let atoms_of_values field_name values =
  let rec loop acc = function
    | [] -> Ok (List.rev acc)
    | Atom value :: rest -> loop (value :: acc) rest
    | List _ :: _ ->
        Error
          (Printf.sprintf
             "field '%s' uses a dune form this migrator does not understand"
             field_name)
  in
  loop [] values

let atoms_of_single_list field_name = function
  | List (Atom name :: values) when name = field_name -> atoms_of_values field_name values
  | List [] ->
      Error
        (Printf.sprintf
           "field '%s' uses a dune form this migrator does not understand"
           field_name)
  | List (List _ :: _) ->
      Error
        (Printf.sprintf
           "field '%s' uses a dune form this migrator does not understand"
           field_name)
  | List (Atom _ :: _) ->
      Error
        (Printf.sprintf
           "field '%s' uses a dune form this migrator does not understand"
           field_name)
  | Atom _ ->
      Error
        (Printf.sprintf
           "field '%s' uses a dune form this migrator does not understand"
           field_name)

let warn acc message =
  { acc with warnings = acc.warnings @ [ message ] }

let with_targets acc targets = { acc with targets = acc.targets @ targets }

let with_action acc action = { acc with actions = acc.actions @ [ action ] }

let with_preprocessor acc tool =
  { acc with preprocessors = acc.preprocessors @ [ tool ] }

let with_ppx_tool acc tool = { acc with ppx_tools = acc.ppx_tools @ [ tool ] }

let generated_name acc prefix =
  let name = Printf.sprintf "%s_%d" prefix acc.next_generated_id in
  (name, { acc with next_generated_id = acc.next_generated_id + 1 })

let normalize_relative value =
  let rec strip value =
    if String_util.starts_with ~prefix:"./" value then
      strip (String.sub value 2 (String.length value - 2))
    else value
  in
  strip value

let ocamlfind_cmd () =
  match Sys.getenv_opt "OCAMLFIND" with
  | Some value when String.trim value <> "" -> value
  | Some _ | None -> "ocamlfind"

let rebase_dune_relative_path dir value =
  let value = normalize_relative value in
  if value = "." then dir
  else if dir = "." then value
  else Filename.concat dir value

let rebase_command_prog dir prog =
  if Filename.is_relative prog && String.contains prog '/' then
    rebase_dune_relative_path dir prog
  else prog

let rec shell_join args =
  String.concat " " (List.map String_util.shell_quote args)

let collect_results items f =
  let rec loop acc = function
    | [] -> Ok (List.rev acc)
    | item :: rest ->
        let* value = f item in
        loop (value :: acc) rest
  in
  loop [] items

type parsed_command = {
  argv : string list;
  cwd : string option;
}

type inferred_deps = {
  deps : string list;
  opaque : bool;
}

type explicit_dep_refs = {
  deps : string list;
  aliases : string list;
  opaque : bool;
}

let parse_run_like ~dir args =
  let* argv = atoms_of_values "run" args in
  match argv with
  | [] -> Error "dune run action is missing a program"
  | prog :: rest -> Ok { argv = rebase_command_prog dir prog :: rest; cwd = None }

let shell_fragment_of_command (command : parsed_command) =
  match command.cwd with
  | None -> shell_join command.argv
  | Some cwd ->
      "cd " ^ String_util.shell_quote cwd ^ " && " ^ shell_join command.argv

let rec parse_command_form ~dir = function
  | List (Atom "run" :: args) -> parse_run_like ~dir args
  | List [ Atom "bash"; Atom script ] ->
      Ok { argv = [ "sh"; "-c"; script ]; cwd = None }
  | List [ Atom "system"; Atom command ] ->
      Ok { argv = [ "sh"; "-c"; command ]; cwd = None }
  | List [ Atom "copy"; Atom src; Atom dst ]
  | List [ Atom "copy#"; Atom src; Atom dst ] ->
      Ok
        {
          argv =
            [
              "cp";
              rebase_dune_relative_path dir src;
              rebase_dune_relative_path dir dst;
            ];
          cwd = None;
        }
  | List [ Atom "diff"; Atom left; Atom right ] ->
      Ok
        {
          argv =
            [
              "diff";
              "-u";
              rebase_dune_relative_path dir left;
              rebase_dune_relative_path dir right;
            ];
          cwd = None;
        }
  | List [ Atom "with-stdin-from"; Atom path; nested ] ->
      let* command = parse_command_form ~dir nested in
      let input_path = rebase_dune_relative_path dir path in
      Ok
        {
          argv =
            [
              "sh";
              "-c";
              shell_fragment_of_command command ^ " < "
              ^ String_util.shell_quote input_path;
            ];
          cwd = None;
        }
  | List [ Atom "chdir"; Atom cwd; nested ] ->
      let* command = parse_command_form ~dir nested in
      Ok
        {
          command with
          cwd = Some (rebase_dune_relative_path dir cwd);
        }
  | List (Atom "progn" :: forms) ->
      let* commands = collect_results forms (parse_command_form ~dir) in
      if commands = [] then Error "dune progn action is empty"
      else
        Ok
          {
            argv =
              [
                "sh";
                "-c";
                String.concat " && "
                  (List.map shell_fragment_of_command commands);
              ];
            cwd = None;
          }
  | _ -> Error "unsupported dune action form"

let parse_rule_command ~dir ~outputs = function
  | List [ Atom "with-stdout-to"; Atom output; nested ] ->
      let* command = parse_command_form ~dir nested in
      let* output =
        if output = "%{target}" || output = "%{targets}" then
          match outputs with
          | [ output ] -> Ok output
          | _ ->
              Error
                "dune with-stdout-to %{target(s)} form requires exactly one output"
        else Ok output
      in
      Ok
        {
          argv =
            [
              "sh";
              "-c";
              shell_join command.argv ^ " > " ^ String_util.shell_quote output;
            ];
          cwd =
            (match command.cwd with
            | Some _ as cwd -> cwd
            | None -> Some dir);
        }
  | form -> parse_command_form ~dir form

let inferred_none : inferred_deps = { deps = []; opaque = false }

let explicit_dep_refs_none : explicit_dep_refs =
  { deps = []; aliases = []; opaque = false }

let merge_inferred (left : inferred_deps) (right : inferred_deps) : inferred_deps =
  {
    deps = String_util.dedup_preserve (left.deps @ right.deps);
    opaque = left.opaque || right.opaque;
  }

let merge_explicit_dep_refs (left : explicit_dep_refs)
    (right : explicit_dep_refs) : explicit_dep_refs =
  {
    deps = String_util.dedup_preserve (left.deps @ right.deps);
    aliases = String_util.dedup_preserve (left.aliases @ right.aliases);
    opaque = left.opaque || right.opaque;
  }

let inferred_dep_candidate ~workspace_root ~dir ~outputs value =
  if value = "" || value = "." || String_util.starts_with ~prefix:"%{" value then
    None
  else
    let rebased = rebase_dune_relative_path dir value in
    let absolute = Filename.concat workspace_root rebased in
    if List.mem rebased outputs then None
    else if Fs.exists absolute && not (Fs.is_directory absolute) then Some rebased
    else None

let inferred_run_deps ~workspace_root ~dir ~outputs args : inferred_deps =
  match args with
  | [] -> { deps = []; opaque = false }
  | _prog :: rest ->
      let rec loop deps opaque = function
        | [] -> { deps = String_util.dedup_preserve (List.rev deps); opaque }
        | Atom value :: tail ->
            let deps =
              match inferred_dep_candidate ~workspace_root ~dir ~outputs value with
              | Some dep -> dep :: deps
              | None -> deps
            in
            loop deps opaque tail
        | List _ :: tail -> loop deps true tail
      in
      loop [] false rest

let rec infer_action_deps ~workspace_root ~dir ~outputs : sexp -> inferred_deps =
  function
  | List (Atom "run" :: args) -> inferred_run_deps ~workspace_root ~dir ~outputs args
  | List [ Atom "copy"; Atom src; Atom _dst ]
  | List [ Atom "copy#"; Atom src; Atom _dst ] ->
      {
        deps =
          (match inferred_dep_candidate ~workspace_root ~dir ~outputs src with
          | Some dep -> [ dep ]
          | None -> []);
        opaque = false;
      }
  | List [ Atom "diff"; Atom left; Atom right ] ->
      let deps =
        List.filter_map
          (inferred_dep_candidate ~workspace_root ~dir ~outputs)
          [ left; right ]
      in
      ({ inferred_none with deps } : inferred_deps)
  | List [ Atom "with-stdin-from"; Atom path; nested ] ->
      merge_inferred
        (({
            inferred_none with
            deps =
              (match
                 inferred_dep_candidate ~workspace_root ~dir ~outputs path
               with
              | Some dep -> [ dep ]
              | None -> []);
          }
           : inferred_deps))
        (infer_action_deps ~workspace_root ~dir ~outputs nested)
  | List [ Atom "bash"; Atom _ ] | List [ Atom "system"; Atom _ ] ->
      { deps = []; opaque = true }
  | List [ Atom "chdir"; Atom cwd; nested ] ->
      infer_action_deps ~workspace_root
        ~dir:(rebase_dune_relative_path dir cwd)
        ~outputs nested
  | List (Atom "progn" :: forms) ->
      List.fold_left
        (fun inferred form ->
          merge_inferred inferred
            (infer_action_deps ~workspace_root ~dir ~outputs form))
        inferred_none forms
  | List [ Atom "with-stdout-to"; Atom output; nested ] ->
      let outputs =
        if output = "%{target}" || output = "%{targets}" then outputs
        else String_util.dedup_preserve (rebase_dune_relative_path dir output :: outputs)
      in
      infer_action_deps ~workspace_root ~dir ~outputs nested
  | List [] | Atom _ -> { deps = []; opaque = true }
  | List forms ->
      List.fold_left
        (fun inferred form ->
          merge_inferred inferred
            (infer_action_deps ~workspace_root ~dir ~outputs form))
        inferred_none forms

let rec explicit_dep_refs_from_form ~dir : sexp -> explicit_dep_refs = function
  | Atom value ->
      if value = "" || value = "." then explicit_dep_refs_none
      else if String_util.starts_with ~prefix:"%{" value then
        { explicit_dep_refs_none with opaque = true }
      else
        {
          explicit_dep_refs_none with
          deps = [ rebase_dune_relative_path dir value ];
        }
  | List [ Atom "alias"; Atom alias_name ]
  | List [ Atom "alias_rec"; Atom alias_name ] ->
      { explicit_dep_refs_none with aliases = [ alias_name ] }
  | List [ Atom "file"; Atom path ] ->
      {
        explicit_dep_refs_none with
        deps = [ rebase_dune_relative_path dir path ];
      }
  | List [] -> explicit_dep_refs_none
  | List (Atom _ :: _) -> { explicit_dep_refs_none with opaque = true }
  | List forms ->
      List.fold_left
        (fun refs form ->
          merge_explicit_dep_refs refs (explicit_dep_refs_from_form ~dir form))
        explicit_dep_refs_none forms

let explicit_rule_deps ~dir fields =
  let* values = field_values "deps" fields in
  Ok
    (match values with
    | None -> explicit_dep_refs_none
    | Some values ->
        List.fold_left
          (fun refs value ->
            merge_explicit_dep_refs refs (explicit_dep_refs_from_form ~dir value))
          explicit_dep_refs_none values)

let resolved_ppx_argv packages =
  let ocamlfind = ocamlfind_cmd () in
  let outcome = Process.run_capture ocamlfind ("printppx" :: packages) in
  if outcome.status = 0 then
    let command = String.trim outcome.output in
    if command = "" then Error "ocamlfind printppx returned an empty command"
    else Ok [ "sh"; "-c"; command ]
  else
    Error
      (Printf.sprintf "failed to resolve dune pps %s via ocamlfind printppx\n%s"
         (String.concat ", " packages) outcome.output)

let target_declared_module_stems (target : raw_target) =
  match target.kind with
  | Library ->
      Option.value ~default:[] target.modules
  | Executable | Test ->
      (match target.modules with
      | Some modules -> modules
      | None -> [])
      @
      match target.main with
      | Some main -> [ main ]
      | None -> []

let action_matches_target (target : raw_target) outputs =
  let module_stems = target_declared_module_stems target in
  List.exists
    (fun output ->
      let basename = Filename.basename output in
      (Filename.check_suffix basename ".ml" || Filename.check_suffix basename ".mli")
      &&
      let stem = Filename.remove_extension basename in
      List.mem stem module_stems)
    outputs

let attach_action_to_targets action_name dir outputs targets =
  let attached = ref false in
  let targets =
    List.map
      (fun (target : raw_target) ->
        if target.dir = dir && action_matches_target target outputs then (
          attached := true;
          {
            target with
            actions =
              String_util.dedup_preserve (target.actions @ [ action_name ]);
          })
        else target)
      targets
  in
  (targets, !attached)

let auto_attach_generated_actions (acc : migration_acc) =
  let targets, warnings =
    List.fold_left
      (fun (targets, warnings) (action : raw_action) ->
        let targets, attached =
          attach_action_to_targets action.name action.dir action.outputs targets
        in
        let warnings =
          if attached then warnings
          else
            warnings
            @
            [
              Printf.sprintf
                "generated action '%s' from dune rule in %s but could not attach it automatically; add it to a matching target's actions list"
                action.name action.dir;
            ]
        in
        (targets, warnings))
      (acc.targets, acc.warnings) acc.actions
  in
  { acc with targets; warnings }

let empty_acc =
  {
    targets = [];
    actions = [];
    preprocessors = [];
    ppx_tools = [];
    warnings = [];
    next_generated_id = 1;
  }

let source_stems_in_dir dir =
  let path = if dir = "." then "." else dir in
  if not (Fs.exists path) || not (Fs.is_directory path) then []
  else
    Sys.readdir path
    |> Array.to_list
    |> List.filter_map (fun entry ->
           if String_util.ends_with ~suffix:".ml" entry
              || String_util.ends_with ~suffix:".mli" entry
           then Some (Filename.remove_extension entry)
           else None)
    |> List.sort_uniq String.compare

let relative_dir workspace_root dune_path =
  let dune_dir = Filename.dirname dune_path in
  if dune_dir = workspace_root then "."
  else
    let prefix = workspace_root ^ "/" in
    if String_util.starts_with ~prefix dune_dir then
      String.sub dune_dir (String.length prefix)
        (String.length dune_dir - String.length prefix)
    else dune_dir

let rebased_field_paths dir paths =
  List.map (rebase_dune_relative_path dir) paths

let parse_target_tools ~workspace_root ~dune_path ~dir acc fields =
  let* acc, preprocess_names, ppx_names =
    match optional_single_value_field "preprocess" fields with
    | Error message -> Error message
    | Ok None -> Ok (acc, [], [])
    | Ok (Some (Atom "no_preprocessing")) -> Ok (acc, [], [])
    | Ok (Some (List (Atom "pps" :: packages))) ->
        let* packages = atoms_of_values "preprocess" packages in
        let name, acc = generated_name acc "dune_ppx" in
        let acc, ppx =
          match resolved_ppx_argv packages with
          | Ok argv -> (with_ppx_tool acc { name; argv; deps = [] }, [ name ])
          | Error message ->
              ( warn acc
                  (Printf.sprintf
                     "%s; skipping generated ppx '%s' from %s"
                     message name dune_path),
                [] )
        in
        Ok (acc, [], ppx)
    | Ok (Some (List (Atom "staged_pps" :: packages))) ->
        let* packages = atoms_of_values "preprocess" packages in
        let name, acc = generated_name acc "dune_ppx" in
        let acc =
          warn acc
            (Printf.sprintf
               "resolved dune staged_pps in %s to a plain oasis ppx tool; review if dune-specific staging mattered"
               dune_path)
        in
        let acc, ppx =
          match resolved_ppx_argv packages with
          | Ok argv -> (with_ppx_tool acc { name; argv; deps = [] }, [ name ])
          | Error message ->
              ( warn acc
                  (Printf.sprintf
                     "%s; skipping generated ppx '%s' from %s"
                     message name dune_path),
                [] )
        in
        Ok (acc, [], ppx)
    | Ok (Some (List (Atom "action" :: [ form ]))) ->
        let* command = parse_command_form ~dir form in
        let name, acc = generated_name acc "dune_preprocess" in
        let cwd =
          match command.cwd with
          | Some _ as cwd -> cwd
          | None -> Some dir
        in
        let inferred =
          infer_action_deps ~workspace_root ~dir ~outputs:[] form
        in
        let acc =
          if inferred.opaque then
            warn acc
              (Printf.sprintf
                 "generated preprocess '%s' from dune action in %s; review deps = [...] because the action hides some file inputs behind shell or unsupported forms"
                 name dune_path)
          else acc
        in
        let acc =
          with_preprocessor acc
            { name; argv = command.argv; cwd; deps = inferred.deps }
        in
        Ok (acc, [ name ], [])
    | Ok (Some _) ->
        Ok
          ( warn acc
              (Printf.sprintf
                 "ignored unsupported dune preprocess form in %s; migrate it manually"
                 dune_path),
            [],
            [] )
  in
  let* acc, pps_names =
    match field_atoms "pps" fields with
    | Error message -> Error message
    | Ok None -> Ok (acc, [])
    | Ok (Some packages) ->
        let name, acc = generated_name acc "dune_ppx" in
        let acc, ppx =
          match resolved_ppx_argv packages with
          | Ok argv -> (with_ppx_tool acc { name; argv; deps = [] }, [ name ])
          | Error message ->
              ( warn acc
                  (Printf.sprintf
                     "%s; skipping generated ppx '%s' from %s"
                     message name dune_path),
                [] )
        in
        Ok (acc, ppx)
  in
  Ok
    ( acc,
      String_util.dedup_preserve preprocess_names,
      String_util.dedup_preserve (ppx_names @ pps_names) )

let parse_rule ~workspace_root ~dune_path acc fields =
  let dir = relative_dir workspace_root dune_path in
  let* target = optional_atom_field "target" fields in
  let* targets = optional_atom_list_field "targets" fields in
  let* explicit_deps = explicit_rule_deps ~dir fields in
  let outputs =
    match target with
    | Some target -> [ target ]
    | None -> targets
  in
  if outputs = [] then
    Ok
      (warn acc
         (Printf.sprintf
            "ignored dune rule without target(s) in %s; migrate it manually"
            dune_path))
  else
    let* action_form = optional_single_value_field "action" fields in
    match action_form with
    | None ->
        Ok
         (warn acc
             (Printf.sprintf
                "ignored dune rule without an action in %s; migrate it manually"
                dune_path))
    | Some form -> (
        match parse_rule_command ~dir ~outputs form with
        | Error _ ->
            Ok
              (warn acc
                 (Printf.sprintf
                    "ignored unsupported dune rule action in %s; migrate it manually"
                    dune_path))
        | Ok command ->
            let name, acc = generated_name acc "dune_action" in
            let inferred =
              infer_action_deps ~workspace_root ~dir
                ~outputs:(rebased_field_paths dir outputs)
                form
            in
            let deps =
              String_util.dedup_preserve
                (explicit_deps.deps @ inferred.deps)
            in
            let acc =
              if explicit_deps.aliases = [] then acc
              else
                warn acc
                  (Printf.sprintf
                     "generated action '%s' from dune rule in %s references alias deps (%s); oasis migrated only the concrete file deps"
                     name dune_path
                     (String.concat ", " explicit_deps.aliases))
            in
            let acc =
              if (inferred.opaque || explicit_deps.opaque) && deps = [] then
                warn acc
                  (Printf.sprintf
                     "generated action '%s' from dune rule in %s may read auxiliary files; review deps = [...]"
                     name dune_path)
              else acc
            in
            let action =
              {
                name;
                dir;
                argv = command.argv;
                cwd =
                  (match command.cwd with
                  | Some _ as cwd -> cwd
                  | None -> Some dir);
                deps;
                outputs;
              }
            in
            Ok (with_action acc action))

let parse_library ~workspace_root ~dune_path acc fields =
  let name = required_atom_field "name" fields in
  let* name = name in
  let* public_name = optional_atom_field "public_name" fields in
  let* wrapped = optional_bool_field "wrapped" fields in
  let dir = relative_dir workspace_root dune_path in
  let inferred_modules = source_stems_in_dir (Filename.dirname dune_path) in
  let* modules = field_atoms "modules" fields in
  let modules =
    match modules with
    | Some modules -> modules
    | None -> inferred_modules
  in
  let* libraries = optional_atom_list_field "libraries" fields in
  let* acc, preprocess, ppx =
    parse_target_tools ~workspace_root ~dune_path ~dir acc fields
  in
  Ok
    ( acc,
      [
        {
          kind = Library;
          name;
          public_name;
          wrapped = Option.value ~default:true wrapped;
          dir;
          main = None;
          modules = Some modules;
          libraries;
          actions = [];
          preprocess;
          ppx;
        };
      ] )

let pair_public_names names public_names =
  let rec loop acc names public_names =
    match (names, public_names) with
    | [], _ -> List.rev acc
    | name :: rest, public_name :: public_rest ->
        loop ((name, Some public_name) :: acc) rest public_rest
    | name :: rest, [] -> loop ((name, None) :: acc) rest []
  in
  loop [] names public_names

let parse_runnable_group kind_label raw_kind ~workspace_root ~dune_path acc fields
    ~names_field ~public_names_field =
  let dir = relative_dir workspace_root dune_path in
  let dune_dir = Filename.dirname dune_path in
  let inferred_modules = source_stems_in_dir dune_dir in
  let* names = optional_atom_list_field names_field fields in
  let* fallback_name = optional_atom_field "name" fields in
  let names =
    match (names, fallback_name) with
    | [], Some name -> [ name ]
    | names, _ -> names
  in
  if names = [] then
    Error (Printf.sprintf "%s stanza is missing a name" kind_label)
  else
    let* public_names = optional_atom_list_field public_names_field fields in
    let* public_name = optional_atom_field "public_name" fields in
    let public_names =
      match (public_names, public_name) with
      | [], Some value -> [ value ]
      | values, _ -> values
    in
    let* modules = field_atoms "modules" fields in
    let helper_modules =
      let modules =
        match modules with
        | Some modules -> modules
        | None -> inferred_modules
      in
      List.filter (fun module_name -> not (List.mem module_name names)) modules
    in
    let* libraries = optional_atom_list_field "libraries" fields in
    let* acc, preprocess, ppx =
      parse_target_tools ~workspace_root ~dune_path ~dir acc fields
    in
    Ok
      ( acc,
        pair_public_names names public_names
        |> List.map (fun (name, public_name) ->
               {
                 kind = raw_kind;
                 name;
                 public_name;
                 wrapped = false;
                 dir;
                 main = Some name;
                 modules = Some helper_modules;
                 libraries;
                 actions = [];
                 preprocess;
                 ppx;
               }) )

let parse_stanza ~workspace_root ~dune_path acc = function
  | List (Atom "library" :: fields) ->
      let* acc, targets =
        parse_library ~workspace_root ~dune_path acc (field_map fields)
      in
      Ok (with_targets acc targets)
  | List (Atom "executable" :: fields) ->
      let* acc, targets =
        parse_runnable_group "executable" Executable ~workspace_root ~dune_path
          acc (field_map fields) ~names_field:"names"
          ~public_names_field:"public_names"
      in
      Ok (with_targets acc targets)
  | List (Atom "executables" :: fields) ->
      let* acc, targets =
        parse_runnable_group "executables" Executable ~workspace_root ~dune_path
          acc (field_map fields) ~names_field:"names"
          ~public_names_field:"public_names"
      in
      Ok (with_targets acc targets)
  | List (Atom "test" :: fields) ->
      let* acc, targets =
        parse_runnable_group "test" Test ~workspace_root ~dune_path acc
          (field_map fields) ~names_field:"names"
          ~public_names_field:"public_names"
      in
      Ok (with_targets acc targets)
  | List (Atom "tests" :: fields) ->
      let* acc, targets =
        parse_runnable_group "tests" Test ~workspace_root ~dune_path acc
          (field_map fields) ~names_field:"names"
          ~public_names_field:"public_names"
      in
      Ok (with_targets acc targets)
  | List (Atom "rule" :: fields) ->
      parse_rule ~workspace_root ~dune_path acc (field_map fields)
  | List (Atom stanza_name :: _) ->
      Ok
        (warn acc
           (Printf.sprintf
              "ignored unsupported dune stanza '%s' in %s; migrate it manually"
              stanza_name dune_path))
  | _ -> Ok (warn acc (Printf.sprintf "ignored malformed dune form in %s" dune_path))

let rec scan_workspace root_dir relative_dir acc =
  let dir =
    if relative_dir = "." then root_dir else Filename.concat root_dir relative_dir
  in
  let entries = Sys.readdir dir |> Array.to_list |> List.sort String.compare in
  List.fold_left
    (fun result entry ->
      let* files = result in
      let next_relative =
        if relative_dir = "." then entry else Filename.concat relative_dir entry
      in
      let path = Filename.concat root_dir next_relative in
      if Fs.is_directory path then
        if
          List.mem entry [ ".git"; "_build"; "_bootstrap"; "_oasis" ]
          || String_util.starts_with ~prefix:"." entry
        then Ok files
        else scan_workspace root_dir next_relative files
      else if entry = "dune" then Ok (path :: files)
      else Ok files)
    (Ok acc) entries

let dune_project_name workspace_root =
  let dune_project = Filename.concat workspace_root "dune-project" in
  if not (Fs.exists dune_project) then Ok None
  else
    let* sexps = parse_many dune_project (Fs.read_file dune_project) in
    let rec find_name = function
      | [] -> None
      | List (Atom "name" :: Atom name :: _) :: _ -> Some name
      | List (Atom "package" :: fields) :: rest -> (
          match fields with
          | List (Atom "name" :: Atom name :: _) :: _ -> Some name
          | _ -> find_name rest)
      | _ :: rest -> find_name rest
    in
    Ok (find_name sexps)

let index_workspace_libraries targets =
  let table = Hashtbl.create 16 in
  List.iter
    (fun target ->
      if target.kind = Library then (
        Hashtbl.replace table target.name target.name;
        match target.public_name with
        | Some public_name -> Hashtbl.replace table public_name target.name
        | None -> ()))
    targets;
  table

let finalize_target_modules targets =
  let alias_index = index_workspace_libraries targets in
  List.map
    (fun (target : raw_target) ->
      match target.kind with
      | Library -> target
      | Executable | Test ->
          let workspace_library_deps =
            List.filter_map
              (fun library_name -> Hashtbl.find_opt alias_index library_name)
              target.libraries
            |> String_util.dedup_preserve
          in
          let modules =
            Option.map
              (List.filter (fun module_name ->
                   not (List.mem module_name workspace_library_deps)))
              target.modules
          in
          { target with modules })
    targets

let toml_string value = "\"" ^ String_util.json_escape value ^ "\""

let toml_array values =
  "[" ^ String.concat ", " (List.map toml_string values) ^ "]"

let render_target alias_index (target : raw_target) =
  let deps, packages =
    List.fold_left
      (fun (deps, packages) library_name ->
        match Hashtbl.find_opt alias_index library_name with
        | Some dependency when dependency <> target.name ->
            (deps @ [ dependency ], packages)
        | _ -> (deps, packages @ [ library_name ]))
      ([], []) target.libraries
  in
  let deps = String_util.dedup_preserve deps in
  let packages = String_util.dedup_preserve packages in
  let section_name =
    match target.kind with
    | Library -> "library"
    | Executable -> "executable"
    | Test -> "test"
  in
  let body =
    match target.kind with
    | Library ->
        [
          Printf.sprintf "[%s.%s]" section_name target.name;
          (match target.public_name with
          | Some public_name -> "public_name = " ^ toml_string public_name
          | None -> "");
          (if target.wrapped then "wrapped = true" else "");
          "dir = " ^ toml_string target.dir;
          "modules = "
          ^
          toml_array
            (match target.modules with
            | Some modules -> modules
            | None -> []);
        ]
    | Executable | Test ->
        [
          Printf.sprintf "[%s.%s]" section_name target.name;
          (match target.public_name with
          | Some public_name -> "public_name = " ^ toml_string public_name
          | None -> "");
          "dir = " ^ toml_string target.dir;
          "main = "
          ^
          toml_string
            (match target.main with
            | Some main -> main
            | None -> target.name);
        ]
        @
        (match target.modules with
        | Some [] | None -> []
        | Some modules -> [ "modules = " ^ toml_array modules ])
  in
  List.filter (fun line -> line <> "") body
  @
  (match target.actions with
  | [] -> []
  | actions -> [ "actions = " ^ toml_array actions ])
  @
  (match target.preprocess with
  | [] -> []
  | preprocess -> [ "preprocess = " ^ toml_array preprocess ])
  @
  (match target.ppx with
  | [] -> []
  | ppx -> [ "ppx = " ^ toml_array ppx ])
  @
  (match deps with
  | [] -> []
  | deps -> [ "deps = " ^ toml_array deps ])
  @
  (match packages with
  | [] -> []
  | packages -> [ "packages = " ^ toml_array packages ])

let render_action (action : raw_action) =
  [
    Printf.sprintf "[action.%s]" action.name;
    "argv = " ^ toml_array action.argv;
    "outputs = " ^ toml_array action.outputs;
  ]
  @
  (match action.deps with
  | [] -> []
  | deps -> [ "deps = " ^ toml_array deps ])
  @
  match action.cwd with
  | Some cwd -> [ "cwd = " ^ toml_string cwd ]
  | None -> []

let render_preprocessor (tool : raw_preprocessor) =
  [
    Printf.sprintf "[preprocess.%s]" tool.name;
    "argv = " ^ toml_array tool.argv;
  ]
  @
  (match tool.cwd with
  | Some cwd -> [ "cwd = " ^ toml_string cwd ]
  | None -> [])
  @
  match tool.deps with
  | [] -> []
  | deps -> [ "deps = " ^ toml_array deps ]

let render_ppx_tool (tool : raw_ppx_tool) =
  [ Printf.sprintf "[ppx.%s]" tool.name; "argv = " ^ toml_array tool.argv ]
  @
  match tool.deps with
  | [] -> []
  | deps -> [ "deps = " ^ toml_array deps ]

let generate_manifest ~workspace_root:_ ~workspace_name acc =
  let acc = auto_attach_generated_actions acc in
  let acc = { acc with targets = finalize_target_modules acc.targets } in
  if acc.targets = [] then Error "no migratable dune stanzas were found"
  else
    let alias_index = index_workspace_libraries acc.targets in
    let warning_block =
      match String_util.dedup_preserve acc.warnings with
      | [] -> []
      | warnings ->
          [ "# Migration warnings:" ]
          @ List.map (fun warning -> "# - " ^ warning) warnings
          @ [ "" ]
    in
    let header =
      [
        "# Generated by `oasis migrate`.";
        "# Review comments and warnings before deleting your dune files.";
        "";
      ]
      @ warning_block
      @
      match workspace_name with
      | Some name -> [ "workspace = " ^ toml_string name; "version = 1"; "" ]
      | None -> [ "version = 1"; "" ]
    in
    let body =
      List.concat_map
        (fun action -> render_action action @ [ "" ])
        acc.actions
      @ List.concat_map
          (fun tool -> render_preprocessor tool @ [ "" ])
          acc.preprocessors
      @ List.concat_map
          (fun tool -> render_ppx_tool tool @ [ "" ])
          acc.ppx_tools
      @
      List.concat_map
        (fun target -> render_target alias_index target @ [ "" ])
        acc.targets
    in
    Ok
      {
        manifest = String.concat "\n" (header @ body);
        warnings = String_util.dedup_preserve acc.warnings;
      }

let run ~workspace_root =
  let workspace_root = Fs.realpath workspace_root in
  let* dune_files = scan_workspace workspace_root "." [] in
  if dune_files = [] then
    Error
      (Printf.sprintf "no dune files were found under workspace %s" workspace_root)
  else
    let* workspace_name = dune_project_name workspace_root in
    let rec collect acc = function
      | [] -> generate_manifest ~workspace_root ~workspace_name acc
      | dune_path :: rest ->
          let* sexps = parse_many dune_path (Fs.read_file dune_path) in
          let* acc =
            List.fold_left
              (fun result sexp ->
                let* acc = result in
                parse_stanza ~workspace_root ~dune_path acc sexp)
              (Ok acc) sexps
          in
          collect acc rest
    in
    collect empty_acc (List.rev dune_files)
