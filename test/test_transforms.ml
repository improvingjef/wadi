open Test_support

type replacement = Literal of string | First_line_of_file of string

let write_executable workspace relative_path contents =
  let path = Filename.concat workspace relative_path in
  Fs.write_file path contents;
  Unix.chmod path 0o755;
  path

let compile_ppx workspace relative_path contents output_relative_path =
  let source_path = Filename.concat workspace relative_path in
  Fs.write_file source_path contents;
  let output_path = Filename.concat workspace output_relative_path in
  let outcome =
    Process.run_capture "ocamlfind"
      [
        "ocamlopt";
        "-package";
        "compiler-libs.common";
        "-linkpkg";
        "-o";
        output_path;
        source_path;
      ]
  in
  assert_int_equal 0 outcome.status
    "expected the helper ppx binary to compile successfully";
  output_path

let replacement_function = function
  | Literal text -> Printf.sprintf "let replacement () = %S\n" text
  | First_line_of_file path ->
      Printf.sprintf
        {|
let replacement () =
  let channel = open_in %S in
  Fun.protect
    ~finally:(fun () -> close_in_noerr channel)
    (fun () -> input_line channel)
|}
        path

let marker_rewriter_source ~marker replacement =
  Printf.sprintf
    {|
open Ast_helper
open Ast_mapper
open Parsetree

%s

let rewrite_marker marker value =
  let marker_length = String.length marker in
  let value_length = String.length value in
  let rec find index =
    if index + marker_length > value_length then None
    else if String.sub value index marker_length = marker then Some index
    else find (index + 1)
  in
  match find 0 with
  | None -> None
  | Some index ->
      Some
        (String.sub value 0 index ^ replacement ()
       ^ String.sub value (index + marker_length)
           (value_length - index - marker_length))

let expr mapper expression =
  match expression.pexp_desc with
  | Pexp_constant
      {
        pconst_desc = Pconst_string (value, _, delimiter);
        pconst_loc = loc;
      }
    -> (
      match rewrite_marker %S value with
      | Some rewritten ->
          Exp.constant
            {
              pconst_desc = Pconst_string (rewritten, loc, delimiter);
              pconst_loc = loc;
            }
      | None -> default_mapper.expr mapper expression )
  | _ -> default_mapper.expr mapper expression

let () =
  run_main (fun _argv -> { default_mapper with expr })
|}
    (replacement_function replacement)
    marker

let compile_string_marker_ppx workspace ~relative_path ~output_relative_path ~marker
    replacement =
  compile_ppx workspace relative_path
    (marker_rewriter_source ~marker replacement)
    output_relative_path

let write_token_preprocessor workspace relative_path ~token ~replacement =
  write_executable workspace relative_path
    (Printf.sprintf "#!/bin/sh\nset -eu\nsed 's/%s/%s/g'\n" token replacement)
