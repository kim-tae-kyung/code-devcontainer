# Coding Agent Sandbox

A container image for AI-assisted software development, bundling the Anthropic Claude Code and OpenAI Codex CLIs with the tooling an agent needs. It is built on a Node.js/TypeScript base and is run primarily as a long-lived **Kubernetes pod** (or any local Docker/Podman container).

## Features

- **Base Image**: `mcr.microsoft.com/devcontainers/typescript-node:24` (digest-pinned)
- **Languages**: Node.js, Python 3, Go (latest)
- **AI Tools**:
  - **Claude Code** (Anthropic) — installed via the official native installer
  - `@openai/codex` — installed via npm
- **MCP Servers** (pre-configured for **both** Claude Code and Codex):
  - **Playwright** — headless Chromium browser automation for UI testing/debugging in containers
  - **context7** — on-demand, up-to-date library/framework documentation
- **Development Tools**: `git`, `gh`, `jq`, `ripgrep`, `vim`, `tree`, `tmux`, and common networking utilities.
- **LSP Support**: `gopls`, `pylsp`, `pyright`, `typescript-language-server`
- **Demo capture** (→ GIF): `asciinema` + `agg` in a fresh isolated tmux server, plus `sharp` for browser screenshots, wired up by an explicit-only `capture-demo` skill for both CLIs.
- **Documentation workflow**: the `docs-visual` skill is installed globally for Codex to research, write, audit, visualize, and validate technical documentation.

## Usage

### Kubernetes (primary)

Deploy as a persistent pod and connect via `kubectl exec`:

```bash
# Create pod (optional: POD_NAME, NAMESPACE, NODE_NAME, SERVICE_ACCOUNT)
./run-k8s-daemon-example.sh

# Connect
kubectl exec -it devcontainer-<timestamp> -- /bin/bash
```

### Local container (Docker/Podman)

```bash
docker run -it --rm -v "$PWD:/workspace" ghcr.io/kim-tae-kyung/code-devcontainer:latest /bin/bash
```

### Authentication

After starting the container, authenticate with each CLI:

```bash
# Claude Code (opens browser for OAuth)
claude

# Codex CLI (sign in with ChatGPT account or API key)
codex
```

### Browser Automation (Playwright MCP)

Headless Chromium is pre-installed for browser automation via the Playwright MCP server. Both Claude Code and Codex are pre-configured with it, enabling the agent to navigate pages, take screenshots, click elements, and read console logs — all from within the pod/container.

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
an **animated GIF** for docs, PRs, or issues. It never attaches to the tmux
session running the agent: every terminal recording creates a private tmux
socket and a fresh session, then removes that server when recording ends.

The skill is user-invocable only. Call it explicitly as `$capture-demo` in
Codex or `/capture-demo` in Claude Code; ordinary recording-related language
does not activate it.

```bash
# Command -> fresh isolated tmux session -> GIF (asciinema + agg)
~/.claude/skills/capture-demo/terminal_capture.sh -o demo.gif -c "npm test; sleep 1"

# Interactive fresh tmux session -> GIF; type exit to finish
~/.claude/skills/capture-demo/terminal_capture.sh -o demo.gif --interactive --duration 60

# Browser flow -> GIF: drive the Playwright MCP, save screenshots as frames/001.png,
# frames/002.png, ... then assemble (sharp, no ffmpeg):
node ~/.claude/skills/capture-demo/frames_to_gif.mjs frames/ --out demo.gif --delay 900 --width 1000
```

Existing outputs are not overwritten unless `--force` is supplied.

### Technical documentation

Codex automatically discovers `docs-visual` from `~/.agents/skills/docs-visual`.
Ask for a documentation audit or rewrite to let Codex select it implicitly, or
invoke it explicitly with `$docs-visual`.

## Security model

The agents are configured for autonomous, unattended use, on the assumption that the container is **disposable and network-isolated** and is itself the only security boundary:

- **Codex**: `approval_policy = "never"` + `sandbox_mode = "danger-full-access"` — no approval prompts, full filesystem/network access.
- **Playwright** launches Chromium with `--no-sandbox` (required for headless Chromium running as non-root in a container).

Do **not** run this image where host mounts, secrets, or trusted outbound network are reachable. In those environments, prefer Codex `approval_policy = "on-request"` + `sandbox_mode = "workspace-write"`. See OpenAI's controlled-containers guidance: <https://developers.openai.com/codex/agent-approvals-security>

## Configuration

Files baked into the image at build time:

- `claude-settings.json` → `~/.claude/settings.json` (Claude Code permissions/behavior)
- `codex-config.toml` → `~/.codex/config.toml` (Codex model, sandbox, MCP servers)
- `operating-principles.md` → `~/.claude/CLAUDE.md` **and** `~/.codex/AGENTS.md` (global agent instructions)
- `tmux.conf` → `~/.tmux.conf`
- `vimrc` → `~/.vimrc`
- `.claude/skills/` → `~/.claude/skills/` (agent skills, e.g. `capture-demo`)
- `.agents/skills/` → `~/.agents/skills/` (Codex skills, e.g. `capture-demo`, `docs-visual`)

Claude Code's MCP servers (Playwright, context7) are registered at user scope during the build via `claude mcp add` (stored in `~/.claude.json`). The working directory is `/workspace`. MCP tool definitions are deferred and discovered on demand — [tool search](https://code.claude.com/docs/en/mcp#scale-with-mcp-tool-search) is on by default, so adding servers costs almost no context at session start.

### Model & effort (Codex)

No model is pinned. Codex selects an available model for the task, while `model_reasoning_effort = "xhigh"` makes difficult, multi-step work the default priority. Choose a model or reasoning level for one task with `/model` or `/reasoning` ([Codex developer commands](https://learn.chatgpt.com/docs/developer-commands)).

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

Effort is set to `xhigh` twice, in `effortLevel` and in `env.CLAUDE_CODE_EFFORT_LEVEL`.

> **Known Issue** — the second one is load-bearing. On first run of Fable 5, Opus 4.8, or Opus 4.7, Claude Code applies *that model's* default effort (`high`) over the saved `effortLevel` and holds it across sessions until an explicit `/effort` or `--effort` ([Adjust effort level](https://code.claude.com/docs/en/model-config#adjust-effort-level)). In an unattended pod nobody is there to type it, so the environment variable — which overrides per session — is what keeps `xhigh` in force. Opus 5 has no such hold.

Auto memory is off (`autoMemoryEnabled: false`), matching Codex's `memories = false`. It is machine-local under `~/.claude/projects/<project>/memory/`, does not outlive the pod, and `cleanupPeriodDays: 3` sweeps that tree ([auto memory](https://code.claude.com/docs/en/memory#auto-memory)). Persistent instructions belong in `operating-principles.md`.

Claude Code is installed unpinned from the official installer, which satisfies the version floors: Fable 5 needs v2.1.170+, Sonnet 5 v2.1.197+, Opus 5 v2.1.219+.

### Terminal (tmux) integration

The image provides tmux 3.5+ with extended keys, CSI u, escape-sequence passthrough, true color, and OSC 52 clipboard forwarding. These settings preserve Shift+Enter and built-in agent notifications through the normal `Ghostty → kubectl exec -it → pod tmux → CLI` path.

Both CLIs render on the terminal's main screen — no alternate screen — so their output stays in tmux scrollback (`history-limit 100000`): Claude Code via `"tui": "default"`, Codex via `[tui] alternate_screen = "never"` (alt-screen bypasses tmux history; see [openai/codex#8555](https://github.com/openai/codex/pull/8555)).

Claude Code uses its native desktop-notification channel. Codex uses its built-in TUI notifications with the default `auto` method, which prefers OSC 9 and falls back to BEL. The pod's `tmux.conf` enables passthrough so those escape sequences return over the interactive Kubernetes TTY to the local terminal. Ghostty must have macOS notification permission and `desktop-notifications = true`.

Claude Remote Control is enabled for every interactive session in the baked-in settings, along with its native mobile push options. It requires a `claude.ai` login inside the running pod and outbound HTTPS access; credentials are deliberately not baked into the image. Remote Control makes outbound connections and does not require an inbound Kubernetes Service.

ChatGPT Remote does not attach directly to an arbitrary Codex CLI process reached through `kubectl exec`. For this workflow, Codex alerts use the built-in terminal notification path to Ghostty; connecting a Codex environment to ChatGPT Remote requires a supported desktop or SSH host.

## Build & Push

### Via GitHub Actions

Container images are built and pushed via GitHub Actions, also on a weekly schedule to pick up the latest base image and tools.

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
