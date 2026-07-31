---
name: capture-demo
description: Create verified animated GIF demos from Playwright browser flows or isolated terminal sessions. Use only when the user explicitly invokes $capture-demo to request a demo GIF, screen recording, screenshot animation, or visual reference for documentation, a PR, or an issue.
---

# Capture Demo

Create a local animated GIF and return its path. Do not upload or attach it
unless the user separately asks for that external action.

Resolve the shared runtime first:

```bash
RUNTIME="${CAPTURE_DEMO_RUNTIME_DIR:-$HOME/.claude/skills/capture-demo}"
test -d "$RUNTIME"
```

If the requested steps, target URL, command, or output path are ambiguous,
resolve only the missing detail before recording. Avoid capturing credentials,
tokens, personal data, or unrelated terminal content.

## Browser flow

1. Discover and use the configured Playwright MCP tools.
2. Create a temporary frame directory outside the repository unless the user
   asks to keep the frames.
3. Set one viewport and keep it unchanged. Wait for each state to settle, then
   save only meaningful states as `001.png`, `002.png`, and so on.
4. Inspect representative frames for correctness and sensitive information.
5. Assemble at least two frames:

   ```bash
   node "$RUNTIME/frames_to_gif.mjs" "$FRAMES_DIR" \
     --out "$OUTPUT" --delay 900 --width 1000
   ```

6. If the result is unnecessarily large, reduce frame count or width and
   rebuild it. Do not overwrite an existing file unless the user explicitly
   requested replacement.

## Terminal flow

Never attach to, resize, inspect, or reuse the tmux server/session that contains
the current Codex process. The runtime always creates a private tmux socket and
a fresh session, records it, and destroys that server afterward.

For a reproducible command:

```bash
"$RUNTIME/terminal_capture.sh" --out "$OUTPUT" \
  --command "npm test" --cols 100 --rows 30
```

For typing, prompts, or a full-screen TUI, launch an interactive recording in a
PTY, retain the process handle, send input through that PTY, and finish by
sending `exit`:

```bash
"$RUNTIME/terminal_capture.sh" --out "$OUTPUT" \
  --interactive --cols 100 --rows 30 --duration 60
```

Use `--theme github-dark --font-size 20` unless the user requests another
appearance. Use `--speed` or `--idle-time-limit` to shorten pauses. Increase
`--duration` when a longer interactive flow is intentional.

## Handoff

Verify that the GIF exists and is animated. Report its path, byte size,
dimensions, and frame count. Remove temporary browser frames after successful
verification; keep them only when debugging a failed render.
