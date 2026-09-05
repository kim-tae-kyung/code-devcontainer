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
user's requested task scope.

Herdr installs its session hooks after the baked settings. The smoke test
checks that its Claude and Codex integrations are current and that Claude's
`SessionStart` hook exists. The settings contain no custom approval hooks.

The Claude `codex` and `codex-imagegen` skills use `codex exec` with
`--ephemeral` and `--skip-git-repo-check`. Keep read-only intent explicit for
reviews, use proper shell quoting, and inherit the configured sandbox policy
rather than adding `-s` or bypass flags
([non-interactive execution](https://learn.chatgpt.com/docs/non-interactive-mode)).
`codex exec review` takes one target: `--uncommitted`, `--base`, `--commit`, or
a custom prompt. Do not combine a target flag with a custom prompt
([CLI reference](https://learn.chatgpt.com/docs/cli/reference)).

The build validates Codex configuration with its installed CLI. Bundled skills
are not asserted before a real session has initialized them. No Codex plugin
or MCP bridge is installed for Claude delegation.
