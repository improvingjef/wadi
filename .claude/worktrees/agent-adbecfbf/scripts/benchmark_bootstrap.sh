#!/bin/sh
set -eu

workspace="."
json_mode=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --workspace)
      if [ "$#" -lt 2 ]; then
        echo "benchmark-bootstrap: --workspace requires a directory" >&2
        exit 2
      fi
      workspace="$2"
      shift 2
      ;;
    --json)
      json_mode=1
      shift
      ;;
    --help)
      cat <<'EOF'
usage: benchmark_bootstrap.sh [--workspace DIR] [--json]
EOF
      exit 0
      ;;
    *)
      echo "benchmark-bootstrap: unknown option '$1'" >&2
      exit 2
      ;;
  esac
done

workspace=$(cd "$workspace" && pwd)
make_cmd=${MAKE:-make}

measure_phase() {
  phase_name="$1"
  shift
  log_file=$(mktemp "${TMPDIR:-/tmp}/wadi-bootstrap-log.XXXXXX")
  time_file=$(mktemp "${TMPDIR:-/tmp}/wadi-bootstrap-time.XXXXXX")
  if (
    cd "$workspace"
    /usr/bin/time -p -o "$time_file" "$make_cmd" "$@"
  ) >"$log_file" 2>&1; then
    :
  else
    cat "$log_file" >&2
    rm -f "$log_file" "$time_file"
    return 1
  fi
  seconds=$(awk '$1 == "real" { print $2 }' "$time_file")
  if [ -z "$seconds" ]; then
    echo "benchmark-bootstrap: failed to parse timing output for $phase_name" >&2
    rm -f "$log_file" "$time_file"
    return 1
  fi
  rm -f "$log_file" "$time_file"
  printf '%s|%s\n' "$phase_name" "$seconds"
}

results_tmp=$(mktemp "${TMPDIR:-/tmp}/wadi-bootstrap-results.XXXXXX")
trap 'rm -f "$results_tmp"' EXIT HUP INT TERM

(
  cd "$workspace"
  "$make_cmd" clean >/dev/null 2>&1
)
measure_phase cold_app _bootstrap/bin/wadi >>"$results_tmp"
(
  cd "$workspace"
  "$make_cmd" clean >/dev/null 2>&1
)
measure_phase cold_full _bootstrap/bin/wadi _bootstrap/bin/test_runner >>"$results_tmp"
measure_phase warm_app _bootstrap/bin/wadi >>"$results_tmp"

if [ "$json_mode" -eq 1 ]; then
  printf '{\n'
  printf '  "workspace": "%s",\n' "$workspace"
  printf '  "results": [\n'
  awk -F'|' '
    BEGIN { count = 0 }
    {
      rows[count++] = $0
    }
    END {
      for (row_index = 0; row_index < count; row_index++) {
        split(rows[row_index], parts, /\|/)
        printf "    {\"name\": \"%s\", \"seconds\": %s}", parts[1], parts[2]
        if (row_index + 1 < count) {
          printf ","
        }
        printf "\n"
      }
    }
  ' "$results_tmp"
  printf '  ]\n'
  printf '}\n'
else
  printf 'Bootstrap benchmark for %s\n' "$workspace"
  awk -F'|' '{ printf "%-10s %ss\n", $1 ":", $2 }' "$results_tmp"
fi
