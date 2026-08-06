---
name: capture-demo
description: Create verified, task-specific screenshots and animated GIF demos from Playwright browser flows or isolated terminal sessions. Use only when the user explicitly invokes $capture-demo to request a demo GIF, screen recording, screenshot animation, or visual reference for documentation, a PR, or an issue.
---

# Capture Demo

Create local screenshots or an animated GIF and return their paths. Do not
upload or attach them unless the user separately asks for that external action.

Resolve the shared runtime first:

```bash
RUNTIME="${CAPTURE_DEMO_RUNTIME_DIR:-$HOME/.claude/skills/capture-demo}"
test -d "$RUNTIME"
```

If the requested steps, target URL, command, or output path are ambiguous,
resolve only the missing detail before recording. Avoid capturing credentials,
tokens, personal data, or unrelated terminal content.

## Browser flow

### Define the evidence

Before opening the browser, inspect the target artifact and write a short
capture manifest for each output:

- purpose and destination path;
- start route and prerequisites;
- exact interactions and expected visible end state;
- realistic, internally consistent example values;
- mutation boundary: the last safe action the capture may perform.

Each procedural artifact must prove its own task. A generic page-open capture
cannot serve as evidence for several different actions. Context images may be
shared only when every procedure also has unique, action-specific evidence.

### Record the flow

1. Discover and use the configured Playwright MCP tools. Create a temporary
   frame directory outside the repository unless the user asks to keep it.
2. Use a fixed viewport for the whole capture. Start from a fresh authenticated
   state when authentication is relevant. Wait for loading indicators to clear
   and for the DOM to stop changing before every frame.
3. Reproduce the documented interaction exactly:
   - For a menu action, open the correct menu, hover the exact item with a
     locator, assert that the menu remains open and the item is visibly hovered,
     then capture that state. Continue into the relevant dialog, drawer, or tab
     when the artifact explains it.
   - For creation, enter realistic values, capture meaningful intermediate
     steps, reach the final review or confirmation state with the submit control
     enabled, and stop before submission unless the user authorized creation.
   - For edit, delete, stop, or other mutations, stop at the final confirmation
     boundary unless the user authorized the mutation.
   - For detail instructions, select the exact tab, section, or control being
     explained; do not substitute a generic detail-page screenshot.
4. Assert expected labels, values, selection state, enabled controls, and route
   before capture. Reject frames containing loading overlays, transient errors,
   unrelated notifications, or the wrong locale.
5. For pre-submit documentation sessions, install a browser request guard after
   login that aborts `POST`, `PUT`, `PATCH`, and `DELETE` requests. Use an
   explicit allowlist only when the user authorized a required mutation.
6. Save settled, meaningful states as `001.png`, `002.png`, and so on. A GIF
   should normally show context, the interaction, and the proved end state;
   use only two frames when the task is genuinely a before/after transition.
7. Inspect the first, representative middle, and final frames for correctness,
   stable layout, visible pointer/focus intent, and sensitive information.
8. Assemble the frames:

   ```bash
   node "$RUNTIME/frames_to_gif.mjs" "$FRAMES_DIR" \
     --out "$OUTPUT" --delay 900 --width 1000
   ```

9. If the result is unnecessarily large, reduce frame count or width and
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
dimensions, and frame count. For a documentation set, also verify that every
procedure has its required unique action evidence and review duplicate file
hashes for accidental reuse. Remove temporary browser frames after successful
verification; keep them only when debugging a failed render.
