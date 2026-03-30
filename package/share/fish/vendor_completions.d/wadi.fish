function __wadi_complete
  set -l previous (commandline -opc)
  if test (count $previous) -gt 0
    set previous $previous[2..-1]
  else
    set previous
  end
  set -l current (commandline -ct)
  set -l response (wadi completion --query --describe --current "$current" -- $previous 2>/dev/null)
  set -l tab (printf '\t')
  if test (count $response) -eq 0
    return
  end
  set -l header (string split $tab -- $response[1])
  if test (count $header) -lt 3
    return
  end
  if test "$header[1]" != '__wadi_completion' -o "$header[2]" != '1'
    return
  end
  if test "$header[3]" = directories
    __fish_complete_directories "$current"
    return
  end
  if test "$header[3]" = files
    __fish_complete_path "$current"
    return
  end
  for line in $response[2..-1]
    set -l fields (string split $tab -- $line)
    if test (count $fields) -lt 2 -o "$fields[1]" != candidate
      continue
    end
    if test (count $fields) -ge 3
      printf '%s\t%s\n' "$fields[2]" "$fields[3]"
    else
      printf '%s\n' "$fields[2]"
    end
  end
end
complete -c wadi -f -a '(__wadi_complete)'
