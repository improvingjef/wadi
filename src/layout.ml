let artifact_root workspace_root = Filename.concat workspace_root "_oasis"

let default_profile = Manifest.default_profile_name

let build_root_for_profile workspace_root profile =
  Filename.concat (artifact_root workspace_root) ("build/" ^ profile)

let build_root workspace_root = build_root_for_profile workspace_root default_profile

let target_root_for_profile workspace_root profile kind =
  Filename.concat (build_root_for_profile workspace_root profile) kind

let target_root workspace_root kind =
  target_root_for_profile workspace_root default_profile kind

let library_out_dir_for_profile workspace_root profile name =
  Filename.concat (target_root_for_profile workspace_root profile "lib") name

let library_out_dir workspace_root name =
  library_out_dir_for_profile workspace_root default_profile name

let executable_out_dir_for_profile workspace_root profile name =
  Filename.concat (target_root_for_profile workspace_root profile "exe") name

let executable_out_dir workspace_root name =
  executable_out_dir_for_profile workspace_root default_profile name

let test_out_dir_for_profile workspace_root profile name =
  Filename.concat (target_root_for_profile workspace_root profile "test") name

let test_out_dir workspace_root name =
  test_out_dir_for_profile workspace_root default_profile name

let target_out_dir ?(profile = default_profile) workspace_root = function
  | Manifest.Library library ->
      library_out_dir_for_profile workspace_root profile library.name
  | Manifest.Executable executable ->
      executable_out_dir_for_profile workspace_root profile executable.name
  | Manifest.Test test -> test_out_dir_for_profile workspace_root profile test.name

let library_archive_for_backend ?(profile = default_profile) workspace_root backend
    name =
  Filename.concat (library_out_dir_for_profile workspace_root profile name)
    ("lib" ^ name ^ Toolchain.library_archive_extension backend)

let library_archive workspace_root name =
  library_archive_for_backend workspace_root Toolchain.Native name

let executable_binary ?(profile = default_profile) workspace_root name =
  Filename.concat (executable_out_dir_for_profile workspace_root profile name) name

let test_binary ?(profile = default_profile) workspace_root name =
  Filename.concat (test_out_dir_for_profile workspace_root profile name) name

let stamp_path out_dir = Filename.concat out_dir ".oasis-stamp"

let explain_path out_dir = Explain.report_path out_dir
