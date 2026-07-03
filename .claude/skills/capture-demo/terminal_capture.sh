#!/usr/bin/env bash
# Record a terminal/tmux session and render it to an animated GIF (asciinema + agg).
# Usage:
#   terminal_capture.sh -o demo.gif -c "seq 1 5; sleep 1"     # record a command
#   terminal_capture.sh -o demo.gif -s mywork                 # attach & record tmux session "mywork"
# Options:
#   -o, --out FILE        output gif (default: demo.gif)
#   -c, --command CMD     command to record (mutually exclusive with -s)
#   -s, --session NAME    tmux session to attach and record
#       --cols N          terminal columns (default: tty width or 80)
#       --rows N          terminal rows (default: tty height or 24)
#       --theme THEME     agg theme (e.g. github-dark, monokai, dracula)
#       --font-size N     agg font size (bigger = sharper, larger file; default agg=14)
#       --speed X         agg playback speed multiplier (e.g. 2 = 2x faster)
# GIF is the only output on purpose: it is the sole animated format GitHub renders inline.
set -euo pipefail

out="demo.gif"; cmd=""; session=""; cols=""; rows=""; theme=""; font_size=""; speed=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--out) out="$2"; shift 2 ;;
    -c|--command) cmd="$2"; shift 2 ;;
    -s|--session) session="$2"; shift 2 ;;
    --cols) cols="$2"; shift 2 ;;
    --rows) rows="$2"; shift 2 ;;
    --theme) theme="$2"; shift 2 ;;
    --font-size) font_size="$2"; shift 2 ;;
    --speed) speed="$2"; shift 2 ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -n "$session" && -n "$cmd" ]]; then
  echo "error: use either -s or -c, not both" >&2; exit 1
fi
if [[ -n "$session" ]]; then
  rec_cmd="tmux attach -t $session"
elif [[ -n "$cmd" ]]; then
  rec_cmd="$cmd"
else
  echo "error: provide -c <command> or -s <tmux-session>" >&2; exit 1
fi

# Fallback size when recording without a real terminal (e.g. an agent invoking
# this non-interactively): asciinema then records width/height 0, which agg rejects.
cols="${cols:-$(tput cols 2>/dev/null || true)}"; cols="${cols:-80}"
rows="${rows:-$(tput lines 2>/dev/null || true)}"; rows="${rows:-24}"

cast="$(mktemp --suffix=.cast)"
trap 'rm -f "$cast"' EXIT

asciinema rec "$cast" --overwrite -c "$rec_cmd"

# Patch a 0x0 header (no real tty) up to the target size so agg can render it.
# A genuine recorded size (e.g. from a tmux pane) is left untouched.
node -e '
const fs = require("fs"), [file, c, r] = process.argv.slice(1);
const lines = fs.readFileSync(file, "utf8").split("\n");
const h = JSON.parse(lines[0]);
if (!h.width || !h.height) {
  h.width = +c; h.height = +r;
  lines[0] = JSON.stringify(h);
  fs.writeFileSync(file, lines.join("\n"));
}
' "$cast" "$cols" "$rows"

agg_args=()
[[ -n "$theme" ]] && agg_args+=(--theme "$theme")
[[ -n "$font_size" ]] && agg_args+=(--font-size "$font_size")
[[ -n "$speed" ]] && agg_args+=(--speed "$speed")

agg "${agg_args[@]}" "$cast" "$out"
echo "wrote $out"
