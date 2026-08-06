---
name: capture-demo
description: >-
  Create verified, task-specific screenshots and animated GIF demos from
  Playwright browser flows or isolated terminal sessions for documentation,
  PRs, and issues.
disable-model-invocation: true
---

# Capture Demo

Create local screenshots or an animated GIF and return their paths. Do not
upload or attach them unless the user separately requests that action. Scripts
live in this skill directory; use `${CLAUDE_SKILL_DIR}` as `RUNTIME`.

```bash
RUNTIME="$CLAUDE_SKILL_DIR"
```

Avoid capturing credentials, tokens, personal data, or unrelated content.

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

1. Use the configured Playwright MCP and a fixed viewport for the entire flow.
   Start fresh when authentication is relevant. Wait for loading indicators to
   clear and for the DOM to stop changing before every frame.
2. Reproduce the documented interaction exactly:
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
3. Assert expected labels, values, selection state, enabled controls, and route
   before capture. Reject frames containing loading overlays, transient errors,
   unrelated notifications, or the wrong locale.
4. For pre-submit documentation sessions, load the required read-only state,
   then install a browser request guard that aborts mutating `POST`, `PUT`,
   `PATCH`, and `DELETE` requests. If the UI uses `POST` for reads, allowlist
   only verified read-only calls by URL and payload. Never allowlist a mutation
   unless the user authorized it.
5. Save settled, meaningful states to a temporary directory as `001.png`,
   `002.png`, and so on. A GIF should normally show context, the interaction,
   and the proved end state; use only two frames when it is genuinely a
   before/after transition.
6. Inspect the first, representative middle, and final frames for correctness,
   stable layout, visible pointer/focus intent, and sensitive information, then
   assemble them:

   ```bash
   node "$RUNTIME/frames_to_gif.mjs" "$FRAMES_DIR" \
     --out "$OUTPUT" --delay 900 --width 1000
   ```

7. Reduce frame count or width if the GIF is unnecessarily large. Remove
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
dimensions, and frame count. For a documentation set, also verify that every
procedure has its required unique action evidence and review duplicate file
hashes for accidental reuse.
