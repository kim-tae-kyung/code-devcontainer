# Mermaid validation

## Contents

- Scope the render
- Run the fixed validator
- Supply a browser portably
- Inspect syntax, layout, and meaning
- Report the result

## Scope the render

Validate Mermaid whenever this task adds or changes Mermaid source. Select the
smallest scope that proves the change:

- For a focused edit, pass only Markdown files with added or changed Mermaid
  blocks.
- For a new documentation set, full visual audit, shared Mermaid
  theme/configuration change, release gate, or explicit user request, pass the
  complete owning Markdown tree.
- For unchanged Mermaid outside the task scope, rely on the repository's
  existing gate. Do not rerender the whole repository merely because Mermaid
  exists somewhere in it.
- When the selected scope has zero Mermaid blocks, record zero and do not
  install or launch a renderer.

A successful fixed-version render is the syntax/parser check. Do not add a
second Mermaid parser unless the repository already requires one.

## Run the fixed validator

Use the bundled runner. It extracts selected Mermaid blocks, invokes one
`@mermaid-js/mermaid-cli@11.16.0` process with one render job, produces PNGs,
writes a source manifest, and creates one contact sheet. It keeps generated
files outside the repository by default and prevents Puppeteer from downloading
another browser.

With an existing Chromium-family executable:

```bash
docs_visual_skill=/absolute/path/to/docs-visual
browser_executable=/absolute/path/to/chromium-or-headless-shell
python3 "$docs_visual_skill/scripts/render_mermaid.py" \
  docs/changed-file.md docs/another-changed-file.md \
  --browser-executable "$browser_executable"
```

With an existing Puppeteer configuration containing an absolute
`executablePath`:

```bash
docs_visual_skill=/absolute/path/to/docs-visual
python3 "$docs_visual_skill/scripts/render_mermaid.py" \
  docs \
  --puppeteer-config /absolute/path/to/puppeteer-config.json
```

Pass `--mermaid-config` when the repository owns a Mermaid JSON configuration.
Pass an explicit `--output-dir` only when the temporary artifacts need a stable
location. Do not add Mermaid CLI, Puppeteer, or browser packages to the target
repository merely for validation.

The runner intentionally uses:

- `@mermaid-js/mermaid-cli@11.16.0`;
- one CLI invocation for all selected blocks;
- `--jobs 1`;
- PNG only, because one render is sufficient for syntax and visual review;
- a contact sheet for triage plus original PNGs for detailed inspection.

Do not render both SVG and PNG unless the deliverable itself requires both.

## Supply a browser portably

The runner is architecture-independent. Give it either:

- an existing Chromium-family executable through `--browser-executable`; or
- an existing Puppeteer JSON file through `--puppeteer-config`.

Prefer a repository/CI-provided browser or configuration when one exists.
Otherwise check only the conventional executables already on `PATH`:
`chromium`, `chromium-browser`, `google-chrome`, `google-chrome-stable`, and
`headless_shell`.

Do not encode architecture-, distribution-, or package-manager-specific browser
installation in this skill. Do not add browser or Puppeteer packages to the
target repository, install system packages, search through arbitrary Mermaid
versions, or invent a new installation path during documentation work. If no
usable browser is already available, report a renderer-environment blocker and
the unrendered Mermaid scope.

Reuse the same browser executable or configuration for every selected Mermaid
block in the task. Do not use a browser for unchanged out-of-scope Mermaid.

## Inspect syntax, layout, and meaning

Rendering proves syntax and renderer compatibility, not semantic correctness.

1. Confirm the runner reports `Rendered N/N` for the selected scope and version
   `11.16.0`.
2. Open `contact-sheet.png` first. Check every panel for clipping, overlapping
   nodes, missing labels, implausible edge routing, and accidental
   disconnections.
3. Open suspicious or text-dense numbered PNGs at original detail. The manifest
   maps each image to its source file and Mermaid fence line.
4. Compare arrow direction, labels, actor boundaries, ownership, states,
   request/response pairs, retry owner, and failure branches to the pinned
   source evidence and adjacent prose.
5. Correct the Mermaid source and rerun the same selected scope. Do not accept
   a diagram merely because it rendered.

For permanent source links used by the diagram or its prose, inspect the pinned
checkout directly:

- verify that the linked path exists at the pinned revision;
- verify that the cited line range contains the claimed symbol or behavior;
- distinguish a stale path/range from a network-blocked URL;
- do not silently replace the requested revision with a newer checkout.

## Report the result

Report:

- selected scope and why it was focused or complete;
- fixed CLI version;
- browser path mode: existing executable or existing Puppeteer config;
- rendered count as `N/N`;
- contact-sheet review and any original-detail checks;
- semantic corrections made;
- any environment failure separately from Mermaid syntax failures.

Do not claim all Mermaid is valid when only changed blocks were selected. Say
exactly what was rendered.
