---
name: capture-demo
description: >-
  Record a web flow (via the Playwright MCP) or a terminal/tmux work session and
  render it to an animated GIF for docs or GitHub issues. Use when the user wants
  a screen recording, demo GIF, screenshot animation, or visual reference to
  attach to a README, PR, or issue.
model: sonnet
---

# capture-demo

Produce an **animated GIF** demonstrating a browser flow or a terminal session.

**Why GIF only:** GitHub (issues, PRs, README) renders animated **GIF inline**;
animated WebP is not reliably rendered, and MP4/WebM need drag-drop video
attachments. For "attach a reference to an issue," GIF is the portable choice.
See <https://github.com/orgs/community/discussions/5470>.

Scripts live in this skill dir. `$DIR` below = the directory containing this file.

## Browser flow → GIF

Drive the already-registered **Playwright MCP**, saving a PNG per step, then
assemble with `frames_to_gif.mjs` (uses `sharp`, no ffmpeg).

1. Navigate/interact with the Playwright MCP tools (`browser_navigate`, clicks, etc.).
2. After each meaningful state, call `browser_take_screenshot` and save to a
   dedicated dir with zero-padded names: `frames/001.png`, `frames/002.png`, …
   (zero-pad so ordering is stable).
3. Assemble:

   ```bash
   node "$DIR/frames_to_gif.mjs" frames/ --out demo.gif --delay 900 --width 1000
   ```

   - `--delay` ms per frame (step demos read best ~700–1200ms).
   - `--width` optional downscale to shrink the file.
   - All frames must share dimensions — keep one viewport size across screenshots.

## Terminal / tmux session → GIF

`terminal_capture.sh` wraps `asciinema rec` + `agg`.

```bash
# Record a one-off command:
"$DIR/terminal_capture.sh" -o demo.gif -c "npm test; sleep 1"

# Record real work in a tmux session named "work":
"$DIR/terminal_capture.sh" -o demo.gif -s work --theme github-dark --font-size 20
```

Recording ends when the command exits or you detach tmux (`prefix d`).

Tuning (passed through to `agg`):
- `--font-size` bigger = sharper but larger file (default 14; 20–28 reads well).
- `--theme` e.g. `github-dark`, `monokai`, `dracula`, `nord`.
- `--speed` e.g. `2` to speed up long sessions.

## Keeping GIFs small
- Fewer frames / higher `--delay` for browser step demos.
- `--width` downscale (browser) — 800–1000px is plenty for an issue.
- `--speed` and a moderate `--font-size` (terminal).
