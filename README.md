# Coding Agent Sandbox

A container image for AI-assisted software development, bundling the Anthropic Claude Code and OpenAI Codex CLIs with the tooling an agent needs. It is built on a Node.js/TypeScript base and is run primarily as a long-lived **Kubernetes pod** (or any local Docker/Podman container).

## Features

- **Base Image**: `mcr.microsoft.com/devcontainers/typescript-node:24` (digest-pinned)
- **Languages**: Node.js, Python 3, Go (latest), Rust (stable, minimal profile)
- **AI Tools**:
  - **Claude Code** (Anthropic) — installed via the official native installer
  - `@openai/codex` — installed via npm
- **Browser & docs servers** (pre-configured for **both** Claude Code and Codex):
  - **Playwright** — headless Chromium browser automation for UI testing/debugging in containers (Claude Code uses the official `playwright` plugin; Codex runs the pinned local MCP server)
  - **context7** — on-demand, up-to-date library/framework documentation (Claude Code uses the official plugin backed by Upstash's hosted HTTP server; Codex runs the local `npx` server)
- **Development Tools**: `git`, `gh`, `jq`, `ripgrep`, `vim`, `tree`, and common networking utilities.
- **Terminal multiplexers**: tmux 3.5+ for the existing workflow, plus the latest stable Herdr release with Claude Code and Codex session integrations.
- **LSP Support**: `gopls`, `pylsp`, `pyright`, `typescript-language-server`, `rust-analyzer` — enabled by default in Claude Code via the official code-intelligence plugins (`gopls-lsp`, `pyright-lsp`, `typescript-lsp`, `rust-analyzer-lsp`), pre-installed at build time
- **Demo capture** (→ GIF): `asciinema` + `agg` in a fresh isolated tmux server, plus `sharp` for browser screenshots, wired up by an explicit-only `capture-demo` skill for both CLIs.
- **Documentation workflow**: the `docs-visual` skill is installed globally for Codex to research, write, audit, visualize, and validate technical documentation.
- **Codex from Claude Code**: two model-invocable Claude Code skills, `codex` (delegate a task, review a plan, or run Codex's native code review) and `codex-imagegen` (raster images through Codex's bundled `imagegen` skill), both driving `codex exec` non-interactively — no plugin and no MCP bridge.

## Usage

### Kubernetes (primary)

Deploy as a persistent pod and connect via `kubectl exec`:

```bash
# Create pod and copy available host credentials
# (optional: POD_NAME, NAMESPACE, NODE_NAME, SERVICE_ACCOUNT)
./run-k8s-daemon-example.sh

# Connect
kubectl exec -it devcontainer-<timestamp> -- /bin/bash
```

### Local container (Docker/Podman)

```bash
docker run -it --rm -v "$PWD:/workspace" ghcr.io/kim-tae-kyung/code-devcontainer:latest /bin/bash
```

### Authentication

The Kubernetes launcher copies existing `~/.ssh`, `~/.gitconfig`, GitHub CLI,
Claude Code, and Codex credentials into the pod. Missing files are skipped. If
credentials are unavailable, or when using another launch method, authenticate
with each CLI inside the container:

```bash
# GitHub CLI: https://cli.github.com/manual/gh_auth_login
gh auth login

# Claude Code (opens browser for OAuth)
claude

# Codex CLI (sign in with ChatGPT account or API key)
codex
```

### Terminal sessions (tmux and Herdr)

tmux remains available unchanged. Herdr is an opt-in alternative; start it from
a separate `kubectl exec` connection instead of nesting it inside tmux, so both
multiplexers can keep their default `Ctrl-b` prefix.

```bash
# Existing workflow
tmux

# Herdr alternative, from a fresh shell in the project you want to manage
cd /workspace/my-project
herdr
```

Herdr starts or reattaches to its background session. Press `Ctrl-b q` to
detach without stopping panes, run `herdr` again to reattach, and use
`herdr server stop` when you intend to terminate the session and its pane
processes. Direct installs track the stable channel and can be refreshed in a
running container with `herdr update`.

The image installs Herdr's official Claude Code and Codex integrations for
native agent-session restoration. It also installs the release-matched `herdr`
skill for both agents; the skill activates only when Herdr is explicitly
requested and the agent is running in a Herdr-managed pane (`HERDR_ENV=1`).

### Browser Automation (Playwright MCP)

Headless Chromium is pre-installed for browser automation via the Playwright MCP server. Both Claude Code (through the official `playwright` plugin) and Codex (through a pinned MCP registration) are pre-configured with it, enabling the agent to navigate pages, take screenshots, click elements, and read console logs — all from within the pod/container.

```bash
# Start your dev server
npm run dev  # e.g. Vite on localhost:5173

# In Claude Code or Codex, ask:
# "Navigate to http://localhost:5173 and take a screenshot"
# "Check for console errors on the page"
# "Click the submit button and verify the result"
```

### Capturing demos (GIF)

The `capture-demo` skill turns browser flows or isolated terminal sessions into
task-specific screenshots or an **animated GIF** for docs, PRs, or issues. A
browser capture starts with an evidence contract for the target artifact, waits
for stable application state, reproduces the documented interaction, and
verifies the final frame. Creation and destructive flows stop at the final
confirmation boundary unless the request explicitly authorizes submission.
Every terminal recording creates a private tmux socket and a fresh session,
then removes that server when recording ends.

The skill is user-invocable only. Call it explicitly as `$capture-demo` in
Codex or `/capture-demo` in Claude Code; ordinary recording-related language
does not activate it.

```bash
# Command -> fresh isolated tmux session -> GIF (asciinema + agg)
~/.claude/skills/capture-demo/terminal_capture.sh -o demo.gif -c "npm test; sleep 1"

# Interactive fresh tmux session -> GIF; type exit to finish
~/.claude/skills/capture-demo/terminal_capture.sh -o demo.gif --interactive --duration 60

# Browser flow -> GIF: capture context, interaction, and proved end state as
# frames/001.png, frames/002.png, ... then assemble (sharp, no ffmpeg):
node ~/.claude/skills/capture-demo/frames_to_gif.mjs frames/ --out demo.gif --delay 900 --width 1000
```

Generic page-open images are not accepted as evidence for distinct procedures.
Existing outputs are not overwritten unless `--force` is supplied.

### Delegating to Codex from Claude Code

Two user-level skills let a Claude Code session hand work to the Codex CLI in
the same pod through [`codex exec`](https://learn.chatgpt.com/docs/non-interactive-mode).
Claude invokes them from ordinary language ("ask codex", "codex한테 이 plan
리뷰 시켜줘", "imagegen으로 인포그래픽 만들어줘"); `/codex` and
`/codex-imagegen` also work.

- `codex` — delegate a task or question (told not to modify files unless the
  user asks Codex to edit), review a plan in plan mode (Codex reads the plan
  file by path and prints a report), or run Codex's native code review with
  `codex exec ... review --uncommitted`, `--base <branch>`, or
  `--commit <sha>`; a custom review prompt is its own target and cannot be
  combined with those flags. Codex's reply is returned verbatim, followed by
  a short assessment.
- `codex-imagegen` — generate or edit PNGs through Codex's bundled `imagegen`
  skill ([image generation](https://learn.chatgpt.com/docs/image-generation):
  built-in `image_gen` tool, `gpt-image-2`, ChatGPT login, no
  `OPENAI_API_KEY`). The skill names an absolute destination inside the
  project, Codex copies the result there from `$CODEX_HOME/generated_images/`,
  and the skill checks the PNG header and views the image before reporting
  the path and dimensions.

Every call passes `--ephemeral` (no Codex session files) and
`--skip-git-repo-check` (`/workspace` is often not a repository), and none
passes `-s`: Codex's Linux sandbox cannot start inside an unprivileged
container, so the calls run under the configured `danger-full-access` policy
described under [Security model](#security-model). Codex needs
its own login in the pod (`codex login status`); the Kubernetes launcher copies
`~/.codex/auth.json` from the host.

`claude-settings.json` allows `Bash(codex *)` and adds a `PreToolUse` hook that
pre-approves a single-line command starting with `codex ` (no `;`, `&`, `|`,
`>`, backticks, `$(`, `<(`, or `--dangerously`) so plan review runs inside plan mode without a
prompt; see `AGENTS.md`. Neither OpenAI's
[Codex plugin for Claude Code](https://github.com/openai/codex-plugin-cc) nor
`codex mcp-server` is used: the plugin would add a second review path with its
own job state, and the MCP server prints a deprecation notice in Codex CLI
0.153.

### Technical documentation

Codex discovers `docs-visual` from `~/.agents/skills/docs-visual`. Like
`capture-demo`, it is user-invocable only: call it explicitly as `$docs-visual`.
Asking for a documentation audit or rewrite in ordinary language does not
activate it, because the skill sets `allow_implicit_invocation: false`.

The skill adds only what the global operating principles do not already state:
pinned primary evidence for repository behavior, and the **Known Issue** callout
format.

## Security model

The agents are configured for autonomous, unattended use, on the assumption that the container is **disposable and network-isolated** and is itself the only security boundary:

- **Codex**: `approval_policy = "never"` + `sandbox_mode = "danger-full-access"` — no approval prompts, full filesystem/network access.
- **Playwright** launches Chromium with the sandbox disabled (required for headless Chromium running as non-root in a container) — Codex passes `--no-sandbox` on the server command line; Claude Code sets `PLAYWRIGHT_MCP_NO_SANDBOX` via its settings `env`.

Do **not** run this image where host mounts, secrets, or trusted outbound network are reachable. In those environments, prefer Codex `approval_policy = "on-request"` + `sandbox_mode = "workspace-write"`. See OpenAI's controlled-containers guidance: <https://developers.openai.com/codex/agent-approvals-security>

## Configuration

Files baked into the image at build time:

- `claude-settings.json` → `~/.claude/settings.json` (Claude Code permissions/behavior)
- `codex-config.toml` → `~/.codex/config.toml` (Codex model, sandbox, MCP servers)
- `operating-principles.md` → `~/.claude/CLAUDE.md` **and** `~/.codex/AGENTS.md` (global agent instructions)
- `tmux.conf` → `~/.tmux.conf`
- `vimrc` → `~/.vimrc`
- `.claude/skills/` → `~/.claude/skills/` (Claude Code skills: `capture-demo`, `codex`, `codex-imagegen`)
- `.agents/skills/` → `~/.agents/skills/` (Codex skills, e.g. `capture-demo`, `docs-visual`)

The build also installs Herdr's generated Claude Code and Codex hooks, and
writes the release-matched `herdr` skill to both user-level skill directories.

Claude Code gets both Playwright and context7 through official marketplace plugins installed at build time — no `claude mcp add` registration remains. The playwright plugin launches `@playwright/mcp@latest` with no flags; the flags the agents need in a container (`--headless --browser=chromium --no-sandbox`) are supplied to Claude Code as `PLAYWRIGHT_MCP_*` env vars in `claude-settings.json`. Codex keeps a local MCP registration pinned via `PLAYWRIGHT_MCP_VERSION`, which `codex-config.toml` mirrors and Renovate raises, because the image installs the Chromium revision that pinned version's `playwright` core requires — deriving the browser from the pin keeps that pair consistent across rebuilds. Because the plugin resolves `@latest` per session, Claude Code can briefly outrun the baked Chromium right after an upstream release, until the image is rebuilt and re-pulled. See `AGENTS.md`. The working directory is `/workspace`. MCP tool definitions are deferred and discovered on demand — [tool search](https://code.claude.com/docs/en/mcp#scale-with-mcp-tool-search) is on by default, so adding servers costs almost no context at session start.

### Model & effort (Codex)

No model is pinned. Codex selects an available model for the task. Reasoning effort is left at the model default for ordinary turns and raised to `xhigh` only inside plan mode via `plan_mode_reasoning_effort`, so the depth is spent where it pays off instead of on every routine edit. Choose a model or reasoning level for one task with `/model` or `/reasoning` ([Codex developer commands](https://learn.chatgpt.com/docs/developer-commands)).

GPT‑5.6 provides three Codex model tiers ([Codex model guidance](https://learn.chatgpt.com/docs/models)):

- **Sol** (`gpt-5.6`) — complex, open-ended, or high-value work that needs analysis, judgment, and polish.
- **Terra** (`gpt-5.6-terra`) — everyday work that benefits from strong reasoning and tool use without Sol's full depth.
- **Luna** (`gpt-5.6-luna`) — clear, repeatable, or high-volume work with explicit success criteria.

Use **Max** only when a single task needs more reasoning than `xhigh`. Use **Ultra** only when a complex task divides into meaningful parallel work, because Ultra adds subagents rather than only increasing single-agent reasoning ([Max and Ultra](https://learn.chatgpt.com/docs/models#know-when-to-use-max-or-ultra)).

Fast mode is off by default; enable it per session only when lower latency justifies higher credit consumption ([Codex Fast mode](https://learn.chatgpt.com/docs/agent-configuration/speed#fast-mode)). Memories and transcript persistence are off because the pod is disposable; persistent instructions belong in `operating-principles.md`.

Codex CLI is installed unpinned from npm. GPT‑5.6 requires Codex CLI 0.144.0 or newer ([GPT‑5.6 availability](https://help.openai.com/en/articles/20001354-gpt-56-in-chatgpt)), and the image build rejects configuration keys unsupported by the installed CLI.

### Model & effort (Claude Code)

No model is pinned, so the account default applies. Choose per task with `/model` ([alias table](https://code.claude.com/docs/en/model-config#model-aliases): `fable`, `opus`, `sonnet`, `haiku`, `best`):

- **Sonnet 5** (`sonnet`) — routine edits and well-scoped tasks.
- **Opus 5** (`opus`) — ambiguity, unfamiliar domains, subtle bugs.
- **Fable 5** (`fable`) — the multi-day unattended sessions this pod exists for. Describe the outcome, not the steps; skip verification reminders.

See [Choosing a Claude model and effort level](https://claude.com/blog/claude-model-and-effort-level-in-claude-code): a wrong answer despite full context means pick a larger model; a skipped file or abandoned refactor means raise effort.

No effort level is pinned either, so each model's default (`high`) applies. Raise it per task with `/effort` ([Adjust effort level](https://code.claude.com/docs/en/model-config#adjust-effort-level)).

> **Why it is not pinned** — Claude Code has no counterpart to Codex's `plan_mode_reasoning_effort`. Effort here is either global (`effortLevel` / `env.CLAUDE_CODE_EFFORT_LEVEL`) or per session/turn (`/effort`); it cannot be scoped to a permission mode, and no hook can set it. Pinning `xhigh` to deepen planning would raise every routine edit too, so the setting was removed. Plan mode does carry a *model* override for the rest of the session — pick one with `/model` while in plan mode — but there is no effort equivalent.

Auto memory is off (`autoMemoryEnabled: false`), matching Codex's `memories = false`. It is machine-local under `~/.claude/projects/<project>/memory/`, does not outlive the pod, and `cleanupPeriodDays: 3` sweeps that tree ([auto memory](https://code.claude.com/docs/en/memory#auto-memory)). Persistent instructions belong in `operating-principles.md`.

Claude Code is installed unpinned from the official installer, which satisfies the version floors: Fable 5 needs v2.1.170+, Sonnet 5 v2.1.197+, Opus 5 v2.1.219+.

### Terminal integration (tmux and Herdr)

The image provides tmux 3.5+ with extended keys, CSI u, escape-sequence passthrough, true color, and OSC 52 clipboard forwarding. These settings preserve Shift+Enter and built-in agent notifications through the normal `Ghostty → kubectl exec -it → pod tmux → CLI` path.

Both CLIs render on the terminal's main screen — no alternate screen — so their output stays in tmux scrollback (`history-limit 100000`): Claude Code via `"tui": "default"`, Codex via `[tui] alternate_screen = "never"` (alt-screen bypasses tmux history; see [openai/codex#8555](https://github.com/openai/codex/pull/8555)).

The pod explicitly selects Claude Code's `"ghostty"` notification channel and Codex's OSC 9 TUI notifications instead of relying on terminal auto-detection across the remote boundary. Claude Code emits native task-complete and input-needed notifications; Codex enables all supported TUI notification events and emits them regardless of terminal focus ([Claude terminal notifications](https://code.claude.com/docs/en/terminal-config#get-a-terminal-bell-or-notification), [Codex notifications](https://learn.chatgpt.com/docs/config-file/config-advanced#notifications)).

The pod's `tmux.conf` enables escape-sequence passthrough so notifications and progress updates return over the interactive Kubernetes TTY to Ghostty ([Claude tmux configuration](https://code.claude.com/docs/en/terminal-config#configure-tmux)). On the host, Ghostty must have macOS notification permission and `desktop-notifications = true` ([Ghostty option reference](https://ghostty.org/docs/config/reference#desktop-notifications)).

Herdr runs alongside tmux without changing `tmux.conf` or the container entrypoint.
Launch it directly from a separate interactive connection; its local background
server then owns the workspaces, tabs, panes, and agent terminals for that Herdr
session. No Kubernetes Service or inbound port is required.

Claude Remote Control is enabled for every interactive session in the baked-in settings, along with its native mobile push options. It requires a `claude.ai` login inside the running pod and outbound HTTPS access; credentials are deliberately not baked into the image. Remote Control makes outbound connections and does not require an inbound Kubernetes Service.

ChatGPT Remote does not attach directly to an arbitrary Codex CLI process reached through `kubectl exec`. For this workflow, Codex alerts use the built-in terminal notification path to Ghostty; connecting a Codex environment to ChatGPT Remote requires a supported desktop or SSH host.

## Build & Push

### Continuous integration

`ci.yml` runs on every pull request and on pushes to `main`. It validates `claude-settings.json` against the [published settings schema](https://json.schemastore.org/claude-code-settings.json) and additionally compares key sets, because the schema allows additional properties and would otherwise accept keys Claude Code does not implement. It also parses `codex-config.toml`. Pull requests additionally build `linux/amd64`, which runs the Dockerfile smoke test.

Renovate runs weekly on Monday and automerges minor, patch, and digest updates. It delegates the merge to GitHub via [`platformAutomerge`](https://docs.renovatebot.com/configuration-options/#platformautomerge) so a PR lands as soon as it is mergeable, instead of waiting a full week for the next Renovate run to merge it. The active [`main` repository ruleset](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets) requires `validate-config` and `build`, so GitHub merges Renovate PRs only after both CI jobs pass against the current branch tip. The ruleset lists the Repository admin role in its [bypass list](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/creating-rulesets-for-a-repository#granting-bypass-permissions-for-your-ruleset), so the maintainer can push to `main` directly; Renovate's PRs stay behind the required checks.

### Via GitHub Actions

Container images are built and pushed via GitHub Actions every Monday at 06:00 KST, picking up the latest base image and tools along with whatever Renovate merged earlier that morning. Each architecture builds on its own native runner — `linux/amd64` on `ubuntu-latest`, `linux/arm64` on `ubuntu-24.04-arm` — and a merge job joins the two digests into the `:latest` manifest, then prunes the GHCR package back to it. Emulating arm64 under QEMU is not an option here; see `AGENTS.md`. To build off-schedule:

1. Go to the **Actions** tab in the repository
2. Select **Build and Push Container Image** workflow
3. Click **Run workflow**

### Local Build (Podman)

Build and push multi-architecture images manually:

```bash
# Build for linux/amd64 and linux/arm64
podman build --no-cache --force-rm \
  --platform linux/amd64,linux/arm64 \
  --manifest ghcr.io/kim-tae-kyung/code-devcontainer:latest .

# Push to registry
podman manifest push --rm ghcr.io/kim-tae-kyung/code-devcontainer:latest
```
