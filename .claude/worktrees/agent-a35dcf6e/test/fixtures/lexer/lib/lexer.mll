{
  let keyword_table = Hashtbl.create 3
  let () =
    List.iter (fun (k, v) -> Hashtbl.add keyword_table k v)
      [ ("hello", "HELLO"); ("world", "WORLD"); ("test", "TEST") ]
}

rule token = parse
  | [' ' '\t' '\n']+ { token lexbuf }
  | ['a'-'z']+ as word {
      match Hashtbl.find_opt keyword_table word with
      | Some upper -> upper
      | None -> String.uppercase_ascii word
    }
  | eof { "" }
  | _ as c { String.make 1 c }
