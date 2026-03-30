let split_once ~on text =
  match String.index_opt text on with
  | None -> None
  | Some index ->
      let left = String.sub text 0 index in
      let right = String.sub text (index + 1) (String.length text - index - 1) in
      Some (left, right)

let starts_with ~prefix text =
  let prefix_length = String.length prefix in
  String.length text >= prefix_length && String.sub text 0 prefix_length = prefix

let ends_with ~suffix text =
  let suffix_length = String.length suffix in
  let text_length = String.length text in
  text_length >= suffix_length
  && String.sub text (text_length - suffix_length) suffix_length = suffix

let split_dot text =
  String.split_on_char '.' text |> List.map String.trim
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

let split_whitespace text =
  let length = String.length text in
  let is_whitespace = function ' ' | '\t' | '\n' | '\r' -> true | _ -> false in
  let rec skip index =
    if index < length && is_whitespace text.[index] then skip (index + 1) else index
  in
  let rec take index =
    if index < length && not (is_whitespace text.[index]) then take (index + 1) else index
  in
  let rec loop index acc =
    let start = skip index in
    if start >= length then List.rev acc
    else
      let stop = take start in
      let word = String.sub text start (stop - start) in
      loop stop (word :: acc)
  in
  loop 0 []

let split_lines text =
  text |> String.split_on_char '\n' |> List.filter (fun line -> line <> "")

let json_escape text =
  let buffer = Buffer.create (String.length text + 16) in
  String.iter
    (function
      | '"' -> Buffer.add_string buffer "\\\""
      | '\\' -> Buffer.add_string buffer "\\\\"
      | '\b' -> Buffer.add_string buffer "\\b"
      | '\012' -> Buffer.add_string buffer "\\f"
      | '\n' -> Buffer.add_string buffer "\\n"
      | '\r' -> Buffer.add_string buffer "\\r"
      | '\t' -> Buffer.add_string buffer "\\t"
      | ch ->
          let code = Char.code ch in
          if code < 0x20 then Buffer.add_string buffer (Printf.sprintf "\\u%04x" code)
          else Buffer.add_char buffer ch)
    text;
  Buffer.contents buffer
