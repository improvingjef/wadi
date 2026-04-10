let () =
  let lexbuf = Lexing.from_string "hello world" in
  let first = Lexer.token lexbuf in
  let second = Lexer.token lexbuf in
  Printf.printf "%s %s\n" first second
