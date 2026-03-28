let split_once ~on text =
  match String.index_opt text on with
  | None -> None
  | Some index ->
      let left = String.sub text 0 index in
      let right =
        String.sub text (index + 1) (String.length text - index - 1)
      in
      Some (left, right)

let starts_with ~prefix text =
  let prefix_length = String.length prefix in
  String.length text >= prefix_length
  && String.sub text 0 prefix_length = prefix

let ends_with ~suffix text =
  let suffix_length = String.length suffix in
  let text_length = String.length text in
  text_length >= suffix_length
  && String.sub text (text_length - suffix_length) suffix_length = suffix

let split_dot text =
  String.split_on_char '.' text
  |> List.map String.trim
  |> List.filter (fun item -> item <> "")

let join_dot parts = String.concat "." parts

let strip_comment line =
  let length = String.length line in
  let rec scan index in_string escaped =
    if index >= length then line
    else
      let ch = line.[index] in
      if escaped then scan (index + 1) in_string false
      else
        match ch with
        | '\\' when in_string -> scan (index + 1) in_string true
        | '"' -> scan (index + 1) (not in_string) false
        | '#' when not in_string -> String.sub line 0 index
        | _ -> scan (index + 1) in_string false
  in
  scan 0 false false

let shell_quote = Filename.quote

let dedup_preserve items =
  let seen = Hashtbl.create (List.length items) in
  List.filter
    (fun item ->
      if Hashtbl.mem seen item then false
      else (
        Hashtbl.add seen item ();
        true))
    items
