# Repository Notes

Maintenance context for this build repository. Nothing here ships in the image;
the image carries `operating-principles.md`.

## Commit hand-made changes straight to `main`

Work done by the maintainer or an agent in this repository goes directly to
`main`: commit and push there, no feature branch and no pull request. Pull
requests are for Renovate, whose automerge waits on the CI build job. That job
runs only on `pull_request` events, so a direct push to `main` gets the
settings and TOML checks but not the image smoke test; run the smoke test
locally (`podman build --platform linux/arm64 .`) when a change touches the
Dockerfile.

## Check the Playwright MCP pin while you are here

`@playwright/mcp` loads only the Chromium revision its `playwright` core was
built against, and the image bakes one revision. Two places name the server
version and must stay equal:

- `PLAYWRIGHT_MCP_VERSION` in the `Dockerfile`, which also derives the Chromium
  install from that version's `playwright` core
- the `mcp_servers.playwright` args in `codex-config.toml`

Renovate raises both together. When you open this repository for any task, spend
a moment confirming the pin is still current and the two agree:

```bash
npm view @playwright/mcp version                               # newest release
grep -n 'PLAYWRIGHT_MCP_VERSION=' Dockerfile
grep -n '@playwright/mcp@' codex-config.toml
```

If a newer release exists, raise both and let CI rebuild — the Chromium install
follows the pin, so nothing else needs changing. If the two files disagree, the
pod runs one server version against a browser built for another, and browser
automation fails with `Executable doesn't exist at .../chromium_headless_shell-<rev>`.

The pin couples the baked Chromium to **Codex**, whose server it names directly.
The build launches Chromium once and fails if it cannot, so for Codex a mismatch
cannot reach a published image. **Claude Code is not covered by that guarantee**:
it gets Playwright via the official `playwright` plugin, whose bundled command is
`npx @playwright/mcp@latest` — re-resolved each session, with the container
flags supplied as `PLAYWRIGHT_MCP_*` env vars in `claude-settings.json`. Right
after an upstream release, an already-published image can run a newer server
against the older baked Chromium, and Claude Code browser automation fails with
the same `Executable doesn't exist` error until the Renovate bump rebuilds the
image and the pod pulls it. There is no runtime self-heal (current releases have
no `browser_install` tool); keeping the pin current is what keeps that window
short.

The build's Chromium launch check runs on `linux/amd64` in CI; `linux/arm64` is
only exercised by the release build, after automerge — so a Playwright bump can
be merged before anything has run it on arm64.

The release build gives each architecture its own native runner
(`ubuntu-latest` and `ubuntu-24.04-arm`) and joins the two digests into one
manifest. Do not fold it back into a single QEMU job: the launch check starts
the headless shell, whose GPU process cannot start under emulation
(`GPU process launch failed: error_code=1002`), and it fails there regardless of
whether the pin is correct.

`@upstash/context7-mcp` (Codex only; Claude Code gets context7 via the official
plugin, which talks to Upstash's hosted HTTP server) tracks `@latest` and needs
no such check: it fetches documentation over HTTP and is not coupled to anything
in the image.

## Why a `PreToolUse` hook pre-approves Playwright

`claude-settings.json` carries a `PreToolUse` hook that returns
`permissionDecision: "allow"` for every `mcp__plugin_playwright_playwright__*`
tool. It exists because `permissions.allow` alone does not stop plan mode from
prompting on Playwright calls.

Plan mode gates tool calls until you approve the plan, "except in sessions with
bypass permissions available"
([permission modes](https://docs.claude.com/en/docs/claude-code/permission-modes#analyze-before-you-edit-with-plan-mode)).
Observed behavior beyond that: the gate applies to MCP tools that do not
advertise a read-only annotation, and the allow-rule lookup runs after the mode
check, so a `mcp__<server>` allow rule cannot lift it. Playwright's
`browser_click`, `browser_type` and `browser_navigate` all land on the wrong
side of that.

A `PreToolUse` hook runs before the permission prompt, and an `allow` decision
skips that prompt
([permissions](https://docs.claude.com/en/docs/claude-code/permissions#extend-permissions-with-hooks)).
Deny and ask rules still override a hook, but this file sets none, so the hook
holds in every permission mode and does not depend on how a session was
launched. That matters wherever `--dangerously-skip-permissions` is not on the
table: Claude Code refuses it under root or `sudo`, and an administrator can
block the mode outright with `permissions.disableBypassPermissionsMode` in
managed settings
([bypassPermissions mode](https://docs.claude.com/en/docs/claude-code/permission-modes#skip-all-checks-with-bypasspermissions-mode)).
`permissions.defaultMode` cannot stand in for it either: Claude Code accepts a
`bypassPermissions` default only when the session also passes
`--dangerously-skip-permissions` or `--allow-dangerously-skip-permissions`.

The hook pre-approves the whole server, `browser_evaluate` and
`browser_run_code_unsafe` included, which matches how the container already runs
Chromium — headless, `--no-sandbox`.

`herdr integration install claude` rewrites the same settings file to add its own
`SessionStart` hook, and it runs after the `COPY`. The build's smoke test asserts
both hooks survive; if a Herdr release starts replacing the `hooks` object
instead of merging into it, that assertion is what fails.

## Why a `PreToolUse` hook pre-approves `codex`

The `Bash` hook in `claude-settings.json` returns `permissionDecision: "allow"`
for a command that starts with `codex ` and contains none of `;`, `&`, `|`,
`>`, a backtick, `$(`, `<(`, `--dangerously`, or a newline (a backslash
continuation is a newline).
It exists for the same reason as the Playwright hook: the `codex` skill reviews
plans *during* plan mode, and there `permissions.allow` does not skip the
prompt or classifier for commands outside the built-in read-only set
([plan mode](https://code.claude.com/docs/en/permission-modes#analyze-before-you-edit-with-plan-mode)).

Invariants the two skills depend on:

- Every `codex` command is one line with the prompt in single quotes, and
  the prompt itself avoids the excluded characters. Plan review passes the
  plan file's absolute path inside the prompt instead of piping the file in:
  a pipe makes a compound command, which neither the hook regex nor
  `Bash(codex *)` covers
  ([compound commands](https://code.claude.com/docs/en/permissions#compound-commands)).
  An input redirect (`codex exec ... - < /tmp/prompt.md`) is the one shell
  operator the regex allows, for prompts that need excluded characters.
- The skills read Codex's final message from stdout instead of `-o <file>`,
  so a plan-mode review writes nothing; progress goes to stderr.
- The hook prints nothing and exits 0 for every other command, so it never
  changes behavior outside the `codex` prefix. Exit code 2 would block; do
  not use it here.
- Prompts that quote `;`, `&`, or `|` are not blocked, only not fast-pathed:
  they fall through to the normal permission flow. This is a deliberate
  trade-off against parsing shell text in a hook.
- The skills never pass `-s`. Codex 0.153 implements `read-only` and
  `workspace-write` on Linux with bubblewrap, which fails inside an
  unprivileged container (`bwrap: Can't mount devpts on /newroot/dev/pts:
  Permission denied`), so every sandboxed command errors before it runs. The
  deprecated `use_legacy_landlock` feature still works there but is slated
  for removal. The pod's `sandbox_mode = "danger-full-access"` is the
  intended policy (see the README security model); the prompts state
  read-only intent instead. Global `codex exec` flags go before the `review`
  subcommand; `codex exec review -s ...` is rejected.
- `codex exec review` takes exactly one target: `--uncommitted`, `--base`,
  `--commit`, or a custom prompt. Combining a flag with a prompt is a usage
  error, so the skill never does that.

No Codex plugin or MCP bridge is installed: `codex mcp-server` prints a
deprecation notice in Codex CLI 0.153, and the skills need only `codex exec`.
Codex materializes its bundled skills (including `imagegen`) into
`~/.codex/skills/.system/` on the first real session start, not from offline
commands such as `codex features list`, so the smoke test cannot assert their
presence.
