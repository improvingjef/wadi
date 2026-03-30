type t = {
  package_name : string;
  formula_class : string;
  release_version : string;
  release_tag_prefix : string;
  synopsis : string;
  description : string;
  maintainer_name : string;
  maintainer_email : string;
  authors : string;
  license : string;
  repository_url : string;
  bug_reports_url : string;
  dev_repo : string;
  homebrew_tap : string;
  homebrew_tap_remote_url : string;
}

let metadata_relative_path = Filename.concat "release" "metadata.sh"
let metadata_path ?(root_dir = ".") () = Filename.concat root_dir metadata_relative_path
let ( let* ) = Result.bind
let error path line message = Error (Printf.sprintf "%s:%d: %s" path line message)

let strip_trailing_whitespace text =
  let rec loop index =
    if index < 0 then ""
    else
      match text.[index] with
      | ' ' | '\t' | '\r' | '\n' -> loop (index - 1)
      | _ -> String.sub text 0 (index + 1)
  in
  loop (String.length text - 1)

let parse_quoted path line quote text =
  let length = String.length text in
  let buffer = Buffer.create length in
  let rec loop index escaped =
    if index >= length then error path line "unterminated quoted shell value"
    else
      let ch = text.[index] in
      if escaped then (
        Buffer.add_char buffer ch;
        loop (index + 1) false)
      else if ch = quote then
        let trailing = String.sub text (index + 1) (length - index - 1) |> String.trim in
        if trailing <> "" then
          error path line "unexpected trailing content after quoted shell value"
        else Ok (Buffer.contents buffer)
      else if quote = '"' && ch = '\\' then loop (index + 1) true
      else (
        Buffer.add_char buffer ch;
        loop (index + 1) false)
  in
  loop 1 false

let parse_value path line text =
  let text = String.trim text in
  if text = "" then Ok ""
  else
    match text.[0] with
    | '\'' -> parse_quoted path line '\'' text
    | '"' -> parse_quoted path line '"' text
    | _ -> Ok (strip_trailing_whitespace text)

let load path =
  if not (Fs.exists path) then Error ("release metadata not found: " ^ path)
  else
    let table = Hashtbl.create 32 in
    let lines = Fs.read_lines path in
    let* () =
      let rec loop line_number = function
        | [] -> Ok ()
        | raw_line :: rest -> (
            let line = String.trim raw_line in
            let next = loop (line_number + 1) rest in
            if
              line = ""
              || String_util.starts_with ~prefix:"#!" line
              || String_util.starts_with ~prefix:"#" line
            then next
            else
              match String_util.split_once ~on:'=' line with
              | Some (name, value)
                when String_util.starts_with ~prefix:"WADI_" (String.trim name) ->
                  let* parsed = parse_value path line_number value in
                  Hashtbl.replace table (String.trim name) parsed;
                  next
              | _ -> next)
      in
      loop 1 lines
    in
    let required name =
      match Hashtbl.find_opt table name with
      | Some value -> Ok value
      | None -> Error (Printf.sprintf "%s: missing required metadata %s" path name)
    in
    let optional ?(default = "") name =
      match Hashtbl.find_opt table name with Some value -> value | None -> default
    in
    let* package_name = required "WADI_PACKAGE_NAME" in
    let* formula_class = required "WADI_FORMULA_CLASS" in
    let* release_version = required "WADI_RELEASE_VERSION" in
    let* release_tag_prefix = required "WADI_RELEASE_TAG_PREFIX" in
    let* synopsis = required "WADI_SYNOPSIS" in
    let* description = required "WADI_DESCRIPTION" in
    let* maintainer_name = required "WADI_MAINTAINER_NAME" in
    let* maintainer_email = required "WADI_MAINTAINER_EMAIL" in
    let* authors = required "WADI_AUTHORS" in
    let* license = required "WADI_LICENSE" in
    let* repository_url = required "WADI_REPOSITORY_URL" in
    let* bug_reports_url = required "WADI_BUG_REPORTS_URL" in
    let* dev_repo = required "WADI_DEV_REPO" in
    let* homebrew_tap = required "WADI_HOMEBREW_TAP" in
    Ok
      {
        package_name;
        formula_class;
        release_version;
        release_tag_prefix;
        synopsis;
        description;
        maintainer_name;
        maintainer_email;
        authors;
        license;
        repository_url;
        bug_reports_url;
        dev_repo;
        homebrew_tap;
        homebrew_tap_remote_url = optional "WADI_HOMEBREW_TAP_REMOTE_URL";
      }

let load_for_root ?(root_dir = ".") () = load (metadata_path ~root_dir ())
let release_tag metadata = metadata.release_tag_prefix ^ metadata.release_version
let source_dir_name metadata = metadata.package_name ^ "-" ^ metadata.release_version
let source_archive_name metadata = source_dir_name metadata ^ "-source.tar.gz"
let asset_index_name (_metadata : t) = "release-assets.json"

let binary_dir_name metadata ~os_name ~arch_name =
  Printf.sprintf "%s-%s-%s-%s" metadata.package_name metadata.release_version arch_name
    os_name

let binary_archive_name metadata ~os_name ~arch_name =
  binary_dir_name metadata ~os_name ~arch_name ^ ".tar.gz"

let download_base_url metadata =
  Printf.sprintf "%s/releases/download/%s" metadata.repository_url (release_tag metadata)

let asset_url metadata asset_name = download_base_url metadata ^ "/" ^ asset_name
let source_archive_url metadata = asset_url metadata (source_archive_name metadata)

let homebrew_tap_owner metadata =
  match String_util.split_once ~on:'/' metadata.homebrew_tap with
  | Some (owner, _) -> owner
  | None -> metadata.homebrew_tap

let homebrew_tap_name metadata =
  match String_util.split_once ~on:'/' metadata.homebrew_tap with
  | Some (_, name) -> name
  | None -> metadata.homebrew_tap

let homebrew_tap_repository_name metadata = "homebrew-" ^ homebrew_tap_name metadata

let homebrew_tap_repository metadata =
  homebrew_tap_owner metadata ^ "/" ^ homebrew_tap_repository_name metadata

let homebrew_tap_repository_url metadata =
  "https://github.com/" ^ homebrew_tap_repository metadata

let homebrew_tap_clone_url metadata =
  if String.trim metadata.homebrew_tap_remote_url <> "" then
    metadata.homebrew_tap_remote_url
  else homebrew_tap_repository_url metadata
