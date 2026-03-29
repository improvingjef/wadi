let artifact_root workspace_root = Filename.concat workspace_root "_oasis"

let build_root workspace_root =
  Filename.concat (artifact_root workspace_root) "build/default"

let target_root workspace_root kind =
  Filename.concat (build_root workspace_root) kind

let library_out_dir workspace_root name =
  Filename.concat (target_root workspace_root "lib") name

let executable_out_dir workspace_root name =
  Filename.concat (target_root workspace_root "exe") name

let test_out_dir workspace_root name =
  Filename.concat (target_root workspace_root "test") name

let target_out_dir workspace_root = function
  | Manifest.Library library -> library_out_dir workspace_root library.name
  | Manifest.Executable executable ->
      executable_out_dir workspace_root executable.name
  | Manifest.Test test -> test_out_dir workspace_root test.name

let library_archive_for_backend workspace_root backend name =
  Filename.concat (library_out_dir workspace_root name)
    ("lib" ^ name ^ Toolchain.library_archive_extension backend)

let library_archive workspace_root name =
  library_archive_for_backend workspace_root Toolchain.Native name

let executable_binary workspace_root name =
  Filename.concat (executable_out_dir workspace_root name) name

let test_binary workspace_root name =
  Filename.concat (test_out_dir workspace_root name) name

let stamp_path out_dir = Filename.concat out_dir ".oasis-stamp"
