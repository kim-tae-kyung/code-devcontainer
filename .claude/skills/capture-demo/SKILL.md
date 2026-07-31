---
name: capture-demo
description: >-
  Create verified animated GIF demos from Playwright browser flows or isolated
  terminal sessions for documentation, PRs, and issues.
disable-model-invocation: true
---

# Capture Demo

Create a local animated GIF and return its path. Do not upload or attach it
unless the user separately requests that action. Scripts live in this skill
directory; use `${CLAUDE_SKILL_DIR}` as `RUNTIME`.

```bash
RUNTIME="$CLAUDE_SKILL_DIR"
```

Avoid capturing credentials, tokens, personal data, or unrelated content.

## Browser flow

1. Use the configured Playwright MCP and keep one viewport for the entire flow.
2. Save settled, meaningful states to a temporary directory as `001.png`,
   `002.png`, and so on.
3. Inspect representative frames, then assemble at least two frames:

   ```bash
   node "$RUNTIME/frames_to_gif.mjs" "$FRAMES_DIR" \
     --out "$OUTPUT" --delay 900 --width 1000
   ```

4. Reduce frame count or width if the GIF is unnecessarily large. Remove
   temporary frames after verifying the result.

## Terminal flow

Never attach to or reuse the tmux session containing Claude Code. Every
recording uses a private tmux socket and a fresh session that the runtime
destroys afterward.

Record a reproducible command:

```bash
"$RUNTIME/terminal_capture.sh" --out "$OUTPUT" \
  --command "npm test" --cols 100 --rows 30
```

For typing, prompts, or a TUI, run an interactive recording in a PTY, send input
through that PTY, and finish with `exit`:

```bash
"$RUNTIME/terminal_capture.sh" --out "$OUTPUT" \
  --interactive --cols 100 --rows 30 --duration 60
```

Use `--theme github-dark --font-size 20` by default. Do not overwrite an
existing output unless the user explicitly requests replacement.

## Handoff

Verify that the GIF exists and is animated. Report its path, byte size,
dimensions, and frame count.
