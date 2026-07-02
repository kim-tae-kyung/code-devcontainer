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
- **Development Tools**: `git`, `gh`, `jq`, `ripgrep`, `vim`, `tree`, `tmux`, `postgresql-client`, and common networking utilities.
- **LSP Support**: `gopls`, `pylsp`, `pyright`, `typescript-language-server`

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

Claude Code's MCP servers (Playwright, context7) are registered at user scope during the build via `claude mcp add` (stored in `~/.claude.json`). The working directory is `/workspace`.

### Terminal (tmux) integration

Both CLIs render on the terminal's main screen — no alternate screen — so their output stays in tmux scrollback (`history-limit 100000`): Claude Code via `"tui": "default"`, Codex via `[tui] alternate_screen = "never"` (alt-screen bypasses tmux history; see [openai/codex#8555](https://github.com/openai/codex/pull/8555)). When a turn finishes or input is needed, each CLI rings the terminal bell — Codex via `[tui] notifications` ([config reference](https://developers.openai.com/codex/config-reference)), Claude Code via `Stop`/`Notification` [hooks](https://code.claude.com/docs/en/hooks) — and tmux flags the window (`monitor-bell`), so agent turns running in other windows are visible at a glance.

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
