let completion_paths ~output_dir ~package_name =
  let completions_dir = Filename.concat output_dir "completions" in
  let bash_path = Filename.concat completions_dir (package_name ^ ".bash") in
  let zsh_path = Filename.concat completions_dir ("_" ^ package_name) in
  let fish_path = Filename.concat completions_dir (package_name ^ ".fish") in
  (bash_path, zsh_path, fish_path)

let package_paths ~output_dir ~package_name =
  let package_dir = Filename.concat output_dir "package" in
  let share_dir = Filename.concat package_dir "share" in
  let doc_path =
    Filename.concat share_dir
      (Filename.concat "doc" (Filename.concat package_name "cli.md"))
  in
  let bash_path =
    Filename.concat share_dir
      (Filename.concat "bash-completion" (Filename.concat "completions" package_name))
  in
  let zsh_path =
    Filename.concat share_dir
      (Filename.concat "zsh" (Filename.concat "site-functions" ("_" ^ package_name)))
  in
  let fish_path =
    Filename.concat share_dir
      (Filename.concat "fish"
         (Filename.concat "vendor_completions.d" (package_name ^ ".fish")))
  in
  (doc_path, bash_path, zsh_path, fish_path)

let write ~output_dir ~package_name ~docs ~bash ~zsh ~fish =
  let docs_path = Filename.concat output_dir (Filename.concat "docs" "cli.md") in
  let bash_completion_path, zsh_completion_path, fish_completion_path =
    completion_paths ~output_dir ~package_name
  in
  let packaged_docs_path, packaged_bash_path, packaged_zsh_path, packaged_fish_path =
    package_paths ~output_dir ~package_name
  in
  Fs.write_file docs_path docs;
  Fs.write_file bash_completion_path bash;
  Fs.write_file zsh_completion_path zsh;
  Fs.write_file fish_completion_path fish;
  Fs.write_file packaged_docs_path docs;
  Fs.write_file packaged_bash_path bash;
  Fs.write_file packaged_zsh_path zsh;
  Fs.write_file packaged_fish_path fish
