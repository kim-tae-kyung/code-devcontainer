#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/capture-demo-smoke.XXXXXX")"
trap 'rm -rf -- "$work_dir"' EXIT

(
  cd "$script_dir"
  node --input-type=module - "$work_dir" <<'NODE'
import sharp from "sharp";
import { join } from "node:path";
const dir = process.argv[2];
await sharp({ create: { width: 320, height: 180, channels: 3, background: "#1f2937" } })
  .png().toFile(join(dir, "001.png"));
await sharp({ create: { width: 320, height: 180, channels: 3, background: "#2563eb" } })
  .png().toFile(join(dir, "002.png"));
NODE
)

node "$script_dir/frames_to_gif.mjs" "$work_dir" \
  --out "$work_dir/browser.gif" --delay 100 --width 240
node "$script_dir/verify_gif.mjs" "$work_dir/browser.gif" --min-frames 2

"$script_dir/terminal_capture.sh" --out "$work_dir/terminal.gif" \
  --command 'printf "\033[2J\033[Hcapture-demo smoke\n"; sleep 0.5; printf "done\n"; sleep 0.5' \
  --cols 80 --rows 24 --duration 10
node "$script_dir/verify_gif.mjs" "$work_dir/terminal.gif" --min-frames 2

echo "capture-demo smoke test passed"
