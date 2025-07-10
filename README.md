# Coding Agent in VS Devcontainer

This repository provides a ready-to-use development environment within a Visual Studio Code Dev Container. It is specifically designed for AI-assisted software development, bundling essential tools and CLIs for a streamlined coding experience.

The environment is built upon a Node.js and TypeScript base and includes the Google Gemini CLI and Anthropic Claude CLI.

## Features

- **Base Image**: `mcr.microsoft.com/devcontainers/typescript-node:22`
- **Languages**: Node.js, Go (version `1.24.4`)
- **AI Tools**:
  - `@google/gemini-cli`
  - `@anthropic-ai/claude-code`
- **Development Tools**: `git`, `gh`, `jq`, `ripgrep`, `fzf`, `vim`, `tree`, and common networking utilities.
- **VS Code Integration**:
  - Pre-installed extensions: ESLint, Prettier, Go.
  - Settings for `formatOnSave` enabled.
- **CI/CD**: A GitHub Actions workflow automatically builds and publishes the container image to the GitHub Container Registry (`ghcr.io`) on every push to the `main` branch.

## Usage

### With VS Code Dev Containers (Recommended)

1. Clone this repository.
2. Open the repository folder in Visual Studio Code.
3. When prompted, click "Reopen in Container" to build and launch the dev container.

### Manual Image Build

You can build the Docker image manually using the following command. This is useful for testing or custom deployments.

```bash
podman build --no-cache --force-rm --platform linux/amd64,linux/arm64 --tag ghcr.io/kim-tae-kyung/code-devcontainer .
```

## Configuration

- **`devcontainer.json`**: This file defines the dev container setup. You can customize VS Code settings, extensions, and environment variables here.
- **Configuration Persistence**: The local `~/.claude` and `~/.gemini` directories are mounted into the container at `/home/node/.claude` and `/home/node/.gemini` respectively. This allows your Claude and Gemini CLI configurations and credentials to persist across container sessions.
- **Forwarded Ports**: The following ports are forwarded from the container to your local machine:
  - `8080`: Golang Backend Server
  - `5173`: Vite Dev Server
- **Workspace**: The project folder is mounted into the `/workspace` directory in the container.
- **Gemini CLI Configuration (`~/.gemini/settings.json`)**: This file allows you to customize the behavior of the Gemini CLI. The `devcontainer.json` ensures this file persists across container sessions. An example configuration is shown below:

```json
{
  "theme": "Default",
  "selectedAuthType": "oauth-personal",
  "contextFileName": "CLAUDE.md",
  "mcpServers": {
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp"]
    }
  }
}
```
