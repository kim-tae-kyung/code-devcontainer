# Coding Agent in VS Devcontainer

This repository provides a ready-to-use development environment within a Visual Studio Code Dev Container. It is specifically designed for AI-assisted software development, bundling essential tools and CLIs for a streamlined coding experience.

The environment is built upon a Node.js and TypeScript base and includes the Google Gemini CLI and Anthropic Claude CLI.

## Features

- **Base Image**: `mcr.microsoft.com/devcontainers/typescript-node:24`
- **Languages**: Node.js, Python 3, Go (latest)
- **AI Tools**:
  - `@google/gemini-cli`
  - `@anthropic-ai/claude-code`
- **Browser Automation**: Headless Chromium via Playwright MCP (for UI testing/debugging in containers)
- **Development Tools**: `git`, `gh`, `jq`, `ripgrep`, `fzf`, `vim`, `tree`, `tmux`, and common networking utilities.
- **LSP Support**: `gopls`, `pylsp`, `pyright`, `typescript-language-server`
- **VS Code Integration**:
  - Pre-installed extensions: ESLint, Prettier, Go, Python, Pylance, Black Formatter, YAML.
  - Language-specific formatters for Python (Black) and Go.
  - Settings for `formatOnSave` enabled.

## Usage

### With VS Code Dev Containers

1. Clone this repository.
2. Open the repository folder in Visual Studio Code.
3. When prompted, click "Reopen in Container" to build and launch the dev container.

### With Kubernetes

Deploy as a persistent pod and connect via `kubectl exec`:

```bash
# Create pod (optional: POD_NAME, NAMESPACE, NODE_NAME, SERVICE_ACCOUNT)
./run-k8s-daemon-example.sh

# Connect
kubectl exec -it devcontainer-<timestamp> -- /bin/bash
```

### Authentication

After starting the container, authenticate with each CLI:

```bash
# Claude Code (opens browser for OAuth)
claude

# Gemini CLI (opens browser for OAuth)
gemini
```

### Browser Automation (Playwright MCP)

Headless Chromium is pre-installed for browser automation via the Playwright MCP server. This enables Claude Code to navigate pages, take screenshots, click elements, and read console logs — all within a headless K8s pod or container.

```bash
# Start your dev server
npm run dev  # e.g. Vite on localhost:5173

# In Claude Code, ask:
# "Navigate to http://localhost:5173 and take a screenshot"
# "Check for console errors on the page"
# "Click the submit button and verify the result"
```

Configuration files:
- `claude-settings.json` → `~/.claude/settings.json` (permissions)
- `claude-mcp.json` → `~/.claude.json` (MCP server config)

## Build & Push

### Via GitHub Actions

Container images are built and pushed via GitHub Actions.

1. Go to **Actions** tab in the repository
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

## Configuration

- **`devcontainer.json`**: Dev container setup configuration.
- **Forwarded Ports**:
  - `8080`: Golang Backend Server
  - `5173`: Vite Dev Server
- **Workspace**: Project folder is mounted at `/workspace`.
