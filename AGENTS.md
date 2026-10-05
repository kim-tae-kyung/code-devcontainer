# Repository Notes

Maintenance context for this build repository. Nothing here ships in the image;
the image carries `operating-principles.md`.

## Commit hand-made changes straight to `main`

Work done by the maintainer or an agent in this repository goes directly to
`main`: commit and push there, no feature branch and no pull request. Pull
requests are for Renovate, whose automerge waits on the CI build job. That job
runs only on `pull_request` events, so a direct push to `main` gets the
settings and TOML checks but not the image smoke test; run the smoke test
locally (`podman build --format docker --platform linux/arm64 .`) when a change
touches the Dockerfile. Podman's default OCI format ignores the Dockerfile's
`SHELL` instruction, so its Bash-only `RUN` steps fail without `--format docker`.

## No backward compatibility

Every build produces a new image, and Pods run from it are disposable: replace
a Pod rather than upgrade it. Change behavior in place. Do not add migrations,
compatibility shims, fallbacks for older CLI releases, or notes about existing
Pods. When a tool changes its interface, update this repository to match and let
the smoke test fail loudly on anything it relies on.

## Keep the Playwright MCP pin aligned

Two files name the server version: `PLAYWRIGHT_MCP_VERSION` in the Dockerfile
and the `mcp_servers.playwright` args in `codex-config.toml`. The Dockerfile
registers Claude Code's user-scoped server from the same build arg. Both
registrations pass `--headless --browser=chromium --no-sandbox`
([Playwright MCP options](https://github.com/microsoft/playwright-mcp#configuration),
[Claude MCP scopes](https://code.claude.com/docs/en/mcp#user-scope)).

When opening this repository, check the latest release and both pins:

```bash
npm view @playwright/mcp version
rg -n 'PLAYWRIGHT_MCP_VERSION=|@playwright/mcp@' Dockerfile codex-config.toml
python3 scripts/check_playwright_pin.py
```

During implementation, raise both pins if a newer release exists. For a
review-only request, report an available update without editing files.
Renovate also updates both pins. The image derives Chromium from the pinned
server's Playwright dependency; Playwright needs its matching browser binaries
([browser installation](https://playwright.dev/docs/browsers)).

CI compares the source pin and Codex registration. The image build compares
both installed registrations with the build arg after the integration
installers run, and also exercises Chromium. `headless_shell` on `PATH` points to
the installed browser so documentation renderers can find it.

Release builds use separate native `ubuntu-latest` and `ubuntu-24.04-arm`
runners, then combine their digests. Preserve that arrangement and use a native
architecture for local builds. The Chromium launch smoke test is part of each
image build; the PR build covers amd64, while arm64 is checked locally for
hand-made changes and in the release workflow. The release workflow uses
`no-cache: true` to refresh unpinned tools
([Docker cache invalidation](https://docs.docker.com/build/cache/invalidation/#run-instructions)).
A push to `main` does not publish an image; publication uses the scheduled or
manually dispatched release workflow.

## Agent permissions and delegation

This image is for trusted IaaS development with operator-provided cluster
access. Codex uses `approval_policy = "never"` and
`sandbox_mode = "danger-full-access"`; Claude Code uses
`permissions.defaultMode = "bypassPermissions"`
([Codex permissions](https://developers.openai.com/codex/agent-approvals-security),
[Claude permission modes](https://code.claude.com/docs/en/permission-modes#skip-all-checks-with-bypasspermissions-mode)).
The image runs the CLIs as `node`. Keep authorization and review-only behavior
in the shared operating principles; CLI permission bypass does not enlarge the
user's requested task scope. `bash_aliases` adds the Claude bypass flag. Codex
needs no flag because its config already grants full access.

Interactive Codex attaches to its shared app-server daemon by default.
`scripts/pod-init` starts that daemon with remote control enabled, from an
environment cleared of `HERDR_*`, so the daemon carries no pane identity. Use
the CLI's own behavior. Do not put a wrapper, alias, or PATH shim in front of
`codex` or `claude`: a wrapper has to parse the CLI's arguments and breaks
when a release adds a subcommand. The smoke test asserts the native behavior
this relies on (`daemon_auto_start`).

Herdr installs its session hooks after the baked settings. The smoke test
checks that its Claude and Codex integrations are current and that Claude's
`SessionStart` hook exists. The settings contain no custom approval hooks.

The official Herdr skill tracks `master` independently of the binary version.
Keep its remote `ADD` so upstream changes invalidate cached skill layers, and
install the same downloaded file into both agents' user-level skill directories.
Do not replace it with the release-matched `herdr --skill` output. Version skew
is intentional; the installed CLI remains the authority for supported commands
([official skill](https://github.com/herdrdev/herdr/blob/master/skills/herdr/SKILL.md)).

The Claude `codex` and `codex-imagegen` skills use `codex exec` with
`--ephemeral` and `--skip-git-repo-check`. Keep read-only intent explicit for
reviews, use proper shell quoting, and inherit the configured sandbox policy
rather than adding `-s` or bypass flags
([non-interactive execution](https://learn.chatgpt.com/docs/non-interactive-mode)).
Every call gets an explicit stdin (`< /dev/null` or a `- < file` prompt) and
keeps stderr in a log file rather than `/dev/null`: when stdin is not a TTY,
`codex exec` reads it to EOF to append to the prompt, and the Bash tool's
stdin socket never closes, so an unredirected call hangs before starting.
`codex exec review` takes one target: `--uncommitted`, `--base`, `--commit`, or
a custom prompt. Do not combine a target flag with a custom prompt
([CLI reference](https://learn.chatgpt.com/docs/cli/reference)).

The build validates Codex configuration with its installed CLI. Bundled skills
are not asserted before a real session has initialized them. No Codex plugin
or MCP bridge is installed for Claude delegation.
