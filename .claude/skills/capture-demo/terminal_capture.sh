#!/usr/bin/env bash
# Record a command or interactive shell in a fresh, isolated tmux server.
# Usage:
#   terminal_capture.sh -o demo.gif -c "npm test"
#   terminal_capture.sh -o demo.gif --interactive --duration 60
# Options:
#   -o, --out FILE          output GIF (default: demo.gif)
#   -c, --command CMD       command to run in the new tmux session
#   -i, --interactive       record a login shell; finish by entering exit
#       --cols N            terminal columns (default: 100)
#       --rows N            terminal rows (default: 30)
#       --duration SEC      stop after this many seconds and render what was captured
#       --theme THEME       agg theme (default: github-dark)
#       --font-size N       agg font size (default: 20)
#       --speed X           playback speed multiplier (default: 1)
#       --idle-time-limit X cap an inactive period in seconds (default: 1)
#       --force             replace an existing output
set -euo pipefail

usage() {
  sed -n '2,17p' "$0"
}

die() {
  echo "error: $*" >&2
  exit 1
}

require_value() {
  [[ $# -ge 2 && -n "$2" ]] || die "$1 requires a value"
}

is_positive_integer() {
  [[ "$1" =~ ^[0-9]+$ ]] && (( 10#$1 > 0 ))
}

is_positive_number() {
  [[ "$1" =~ ^([0-9]+([.][0-9]+)?|[.][0-9]+)$ ]] &&
    awk -v value="$1" 'BEGIN { exit !(value > 0) }'
}

out="demo.gif"
command_text=""
interactive=false
cols="100"
rows="30"
duration=""
theme="github-dark"
font_size="20"
speed="1"
idle_time_limit="1"
force=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--out)
      require_value "$1" "${2-}"; out="$2"; shift 2 ;;
    -c|--command)
      require_value "$1" "${2-}"; command_text="$2"; shift 2 ;;
    -i|--interactive)
      interactive=true; shift ;;
    --cols)
      require_value "$1" "${2-}"; cols="$2"; shift 2 ;;
    --rows)
      require_value "$1" "${2-}"; rows="$2"; shift 2 ;;
    --duration)
      require_value "$1" "${2-}"; duration="$2"; shift 2 ;;
    --theme)
      require_value "$1" "${2-}"; theme="$2"; shift 2 ;;
    --font-size)
      require_value "$1" "${2-}"; font_size="$2"; shift 2 ;;
    --speed)
      require_value "$1" "${2-}"; speed="$2"; shift 2 ;;
    --idle-time-limit)
      require_value "$1" "${2-}"; idle_time_limit="$2"; shift 2 ;;
    --force)
      force=true; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      die "unknown argument: $1" ;;
  esac
done

if [[ -n "$command_text" && "$interactive" == true ]]; then
  die "use either --command or --interactive, not both"
fi
if [[ -z "$command_text" && "$interactive" == false ]]; then
  die "provide --command CMD or --interactive"
fi

is_positive_integer "$cols" || die "--cols must be a positive integer"
is_positive_integer "$rows" || die "--rows must be a positive integer"
is_positive_integer "$font_size" || die "--font-size must be a positive integer"
is_positive_number "$speed" || die "--speed must be a positive number"
is_positive_number "$idle_time_limit" || die "--idle-time-limit must be a positive number"
if [[ -n "$duration" ]]; then
  is_positive_number "$duration" || die "--duration must be a positive number"
fi

for dependency in asciinema agg tmux node awk infocmp; do
  command -v "$dependency" >/dev/null 2>&1 || die "required command not found: $dependency"
done
if [[ -n "$duration" ]]; then
  command -v timeout >/dev/null 2>&1 || die "--duration requires GNU timeout"
fi

[[ ! -d "$out" ]] || die "output is a directory: $out"
output_dir_input="$(dirname -- "$out")"
[[ -d "$output_dir_input" ]] || die "output directory does not exist: $output_dir_input"
output_dir="$(cd -- "$output_dir_input" && pwd -P)"
output_name="$(basename -- "$out")"
[[ -n "$output_name" && "$output_name" != "." && "$output_name" != "/" ]] ||
  die "invalid output path: $out"
output_path="${output_dir}/${output_name}"
if [[ -e "$output_path" || -L "$output_path" ]]; then
  [[ "$force" == true ]] || die "output already exists: $output_path; pass --force to replace it"
fi

work_dir=""
socket_path=""
temp_gif=""

cleanup() {
  local status=$?
  if [[ -n "$socket_path" ]]; then
    tmux -S "$socket_path" kill-server >/dev/null 2>&1 || true
  fi
  if [[ -n "$temp_gif" && -f "$temp_gif" ]]; then
    rm -f -- "$temp_gif"
  fi
  if [[ -n "$work_dir" && -d "$work_dir" ]]; then
    rm -rf -- "$work_dir"
  fi
  return "$status"
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/capture-demo.XXXXXX")"
socket_path="${work_dir}/tmux.sock"
cast_path="${work_dir}/recording.cast"
session_runner="${work_dir}/session-runner.sh"
attach_runner="${work_dir}/attach-runner.sh"
command_file="${work_dir}/command.sh"
session_name="capture-demo"
start_channel="capture-demo-start"

if [[ -n "$command_text" ]]; then
  printf '%s\n' "$command_text" >"$command_file"
  mode="command"
else
  mode="interactive"
fi

cat >"$session_runner" <<'RUNNER'
#!/usr/bin/env bash
set -euo pipefail
tmux -S "$CAPTURE_DEMO_SOCKET" wait-for "$CAPTURE_DEMO_START_CHANNEL"
if [[ "$CAPTURE_DEMO_MODE" == "command" ]]; then
  exec bash -l "$CAPTURE_DEMO_COMMAND_FILE"
fi
exec "$CAPTURE_DEMO_SHELL" -l
RUNNER

cat >"$attach_runner" <<'RUNNER'
#!/usr/bin/env bash
set -euo pipefail
export TERM="$CAPTURE_DEMO_CLIENT_TERM"
stty cols "$CAPTURE_DEMO_COLS" rows "$CAPTURE_DEMO_ROWS"
exec env -u TMUX tmux -S "$CAPTURE_DEMO_SOCKET" \
  attach-session -t "$CAPTURE_DEMO_SESSION"
RUNNER

chmod 0700 "$session_runner" "$attach_runner"
if [[ -f "$command_file" ]]; then
  chmod 0700 "$command_file"
fi
printf -v session_command '%q' "$session_runner"

tmux -S "$socket_path" new-session -d \
  -s "$session_name" -x "$cols" -y "$rows" \
  -e "CAPTURE_DEMO_SOCKET=$socket_path" \
  -e "CAPTURE_DEMO_START_CHANNEL=$start_channel" \
  -e "CAPTURE_DEMO_MODE=$mode" \
  -e "CAPTURE_DEMO_COMMAND_FILE=$command_file" \
  -e "CAPTURE_DEMO_SHELL=${SHELL:-/bin/bash}" \
  "$session_command"

# Release the command only after the recorder becomes a real tmux client. A
# server-side hook avoids polling races and behaves the same with or without an
# outer TTY. The short delay lets the recorder receive the initial terminal
# state before command output begins.
tmux -S "$socket_path" set-hook -g client-attached \
  "run-shell -b 'sleep 0.2; tmux wait-for -S $start_channel'"

export CAPTURE_DEMO_ATTACH_SCRIPT="$attach_runner"
export CAPTURE_DEMO_COLS="$cols"
export CAPTURE_DEMO_ROWS="$rows"
export CAPTURE_DEMO_SOCKET="$socket_path"
export CAPTURE_DEMO_SESSION="$session_name"
client_term="${TERM:-xterm-256color}"
if [[ "$client_term" == "dumb" ]] || ! infocmp "$client_term" >/dev/null 2>&1; then
  client_term="xterm-256color"
fi
export CAPTURE_DEMO_CLIENT_TERM="$client_term"
export TERM="$client_term"
export SHELL="${SHELL:-/bin/bash}"

record_status=0
set +e
if [[ -n "$duration" ]]; then
  timeout --foreground --signal=INT --kill-after=5s "${duration}s" \
    asciinema rec "$cast_path" --overwrite \
      -c 'exec "$CAPTURE_DEMO_ATTACH_SCRIPT"'
  record_status=$?
else
  asciinema rec "$cast_path" --overwrite \
    -c 'exec "$CAPTURE_DEMO_ATTACH_SCRIPT"'
  record_status=$?
fi
set -e

if (( record_status == 124 )); then
  echo "recording reached --duration ${duration}s; rendering captured output" >&2
  record_status=0
fi

tmux -S "$socket_path" kill-server >/dev/null 2>&1 || true
socket_path=""

node - "$cast_path" "$cols" "$rows" <<'NODE'
const fs = require("fs");
const [file, cols, rows] = process.argv.slice(2);
const lines = fs.readFileSync(file, "utf8").split(/\r?\n/);
if (!lines[0]) throw new Error("recording has no asciicast header");
const header = JSON.parse(lines[0]);
let changed = false;
if (header.version === 2) {
  if (!header.width || !header.height) {
    header.width = Number(cols);
    header.height = Number(rows);
    changed = true;
  }
} else if (header.version === 3) {
  header.term ??= {};
  if (!header.term.cols || !header.term.rows) {
    header.term.cols = Number(cols);
    header.term.rows = Number(rows);
    changed = true;
  }
} else {
  throw new Error(`unsupported asciicast version: ${header.version}`);
}
const events = lines.slice(1).filter((line) => {
  const trimmed = line.trim();
  return trimmed && !trimmed.startsWith("#");
});
if (events.length === 0) throw new Error("recording contains no terminal events");
if (changed) {
  lines[0] = JSON.stringify(header);
  fs.writeFileSync(file, lines.join("\n"));
}
NODE

temp_gif="$(mktemp "${output_dir}/.capture-demo-gif.XXXXXX")"
agg_args=(
  --theme "$theme"
  --font-size "$font_size"
  --speed "$speed"
  --idle-time-limit "$idle_time_limit"
)
agg "${agg_args[@]}" "$cast_path" "$temp_gif"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
node "$script_dir/verify_gif.mjs" "$temp_gif" --min-frames 2

if [[ -e "$output_path" || -L "$output_path" ]]; then
  [[ "$force" == true ]] || die "output appeared during rendering: $output_path"
fi
if [[ "$force" == true ]]; then
  mv -f -- "$temp_gif" "$output_path"
else
  ln -- "$temp_gif" "$output_path"
  rm -f -- "$temp_gif"
fi
temp_gif=""

node "$script_dir/verify_gif.mjs" "$output_path" --min-frames 2
echo "wrote $output_path"

if (( record_status != 0 )); then
  echo "recorded process exited with status $record_status" >&2
  exit "$record_status"
fi
