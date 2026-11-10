# Repository Notes

Maintenance context for this build repository. Nothing here ships in the image;
the image carries `operating-principles.md`.

## Commit hand-made changes straight to `main`

Work done by the maintainer or an agent in this repository goes directly to
`main`: commit and push there, no feature branch and no pull request. Pull
requests are for Renovate, whose automerge waits on the CI build job. That job
runs on `pull_request` and manual dispatch events, so a direct push to `main` gets the
settings and TOML checks but not the image smoke test; run the smoke test
locally (`podman build --format docker --platform linux/arm64 .`) when a change
touches the Dockerfile. Podman's default OCI format ignores the Dockerfile's
`SHELL` instruction, so its Bash-only `RUN` steps fail without `--format docker`.
When the Neovim step fails with `403`, the address has used up GitHub's
unauthenticated API limit: add `--secret id=github_token,env=GH_TOKEN` with
`GH_TOKEN="$(gh auth token)"`.

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
```

During implementation, raise both pins if a newer release exists. For a
review-only request, report an available update without editing files.
Renovate also updates both pins. The image derives Chromium from the pinned
server's Playwright dependency; Playwright needs its matching browser binaries
([browser installation](https://playwright.dev/docs/browsers)).

CI checks that the two pins match. The image build launches the Chromium it
installed for the pin. It installs the full build only (`--no-shell`): the
server runs headless through the `chromium` channel, so the launch check passes
`--channel=chromium` too
([new headless mode](https://playwright.dev/docs/browsers#chromium-new-headless-mode)).

`npx` reads the package metadata from the registry or the npm cache on every
start, including for a cached exact version. The pre-warm step therefore clears
the downloaded tarballs, caches the metadata with a second run, and ends with
`npx --offline` so a build fails if the server would need the registry to start.
Other install steps clear the npm and Go caches in the same `RUN`.

Release builds use separate native `ubuntu-26.04` and `ubuntu-26.04-arm`
runners, then combine their digests. Preserve that arrangement and use a native
architecture for local builds. The Chromium launch smoke test is part of each
image build; the PR build covers amd64, while manual CI runs cover both
architectures. Check arm64 locally for hand-made Dockerfile changes as well.
The release workflow uses
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
needs no permission flag because its config already grants full access.

The `mcp__playwright` allow rule spares auto mode a classifier call per browser
action. It does not lift plan mode's hold on MCP tools without `readOnlyHint`,
such as `browser_navigate`: that check runs before allow rules and hooks, so
only a session with bypass permissions available plans without those prompts
(observed in Claude Code 2.1.319; the
[plan mode docs](https://code.claude.com/docs/en/permission-modes#analyze-before-you-edit-with-plan-mode)
cover shell commands and edits, not MCP tools). Keep the bypass launch rather
than adding rules or hooks for plan-mode Playwright prompts.

`bash_aliases` runs interactive Codex with `--no-daemon`. Codex's shared
app-server daemon runs hooks without the pane's `HERDR_*` identity, so Herdr
cannot record or resume Codex sessions through it
([herdr#4649](https://github.com/herdrdev/herdr/issues/4649)). Codex Remote
Control depends on that daemon and is intentionally not set up. Drop the flag
when a Herdr or Codex release keeps the pane identity with the daemon. Use the
CLI's own behavior otherwise: an alias may only prepend a flag, and no wrapper
or PATH shim in front of `codex` or `claude` may parse arguments, because it
breaks when a release adds a subcommand.

The image installs the Herdr binary in `/opt/herdr`. `scripts/herdr`, installed
as `/usr/local/bin/herdr`, waits for the terminal size that `kubectl exec`
applies after starting the command, then runs the binary with `"$@"` without
parsing arguments. Herdr rejects a zero-sized terminal at startup
([herdr#3777](https://github.com/herdrdev/herdr/issues/3777)). When a Herdr
release tolerates that state, install it on `PATH` again and remove the script
and its build check.

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
The Pod does not let `bwrap` create user namespaces, so Codex's `read-only`
and `workspace-write` sandboxes fail every command
([OS-level sandbox](https://learn.chatgpt.com/docs/agent-approvals-security#os-level-sandbox)).
Calls pick foreground or `run_in_background` and the Bash `timeout` by
workload, and wait for the completion notification. Never cap Codex with
`timeout`, detach it with shell job control, or poll for it. The settings set
`BASH_MAX_TIMEOUT_MS` to two hours so foreground calls are not limited to
the 10-minute default
([environment variables](https://code.claude.com/docs/en/env-vars#variables)).
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
