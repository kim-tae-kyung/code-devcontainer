# Coding Agent in VS Devcontainer

This repository provides a ready-to-use development environment within a Visual Studio Code Dev Container. It is specifically designed for AI-assisted software development, bundling essential tools and CLIs for a streamlined coding experience.

The environment is built upon a Node.js and TypeScript base and includes the Google Gemini CLI and Anthropic Claude CLI.

## Features

- **Base Image**: `mcr.microsoft.com/devcontainers/typescript-node:24`
- **Languages**: Node.js, Python 3, Go (latest)
- **AI Tools**:
  - `@google/gemini-cli`
  - `@anthropic-ai/claude-code`
- **Development Tools**: `git`, `gh`, `jq`, `ripgrep`, `fzf`, `vim`, `tree`, `tmux`, and common networking utilities.
- **LSP Support**: `gopls`, `pylsp`, `pyright`, `typescript-language-server`
- **VS Code Integration**:
  - Pre-installed extensions: ESLint, Prettier, Go, Python, Pylance, Black Formatter, YAML.
  - Language-specific formatters for Python (Black) and Go.
  - Settings for `formatOnSave` enabled.

## Usage

### With VS Code Dev Containers (Recommended)

1. Clone this repository.
2. Open the repository folder in Visual Studio Code.
3. When prompted, click "Reopen in Container" to build and launch the dev container.

### Authentication

After starting the container, authenticate with each CLI:

```bash
# Claude Code (opens browser for OAuth)
claude

# Gemini CLI (opens browser for OAuth)
gemini
```

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
