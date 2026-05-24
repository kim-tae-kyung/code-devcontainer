FROM --platform=$TARGETPLATFORM mcr.microsoft.com/devcontainers/typescript-node:24@sha256:e36c918ec9c679c18451231e277ea9122c00a097fb6e4a23c8c3d35bf08bbc3a

ARG TARGETPLATFORM
ARG TARGETARCH
ARG TZ="Asia/Seoul"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Base image does not declare HOME in ENV; set it explicitly so ${HOME} expands
# in subsequent ENV/COPY/RUN instructions during build.
ENV HOME=/home/node

ENV TZ=${TZ} \
    DEBIAN_FRONTEND=noninteractive \
    EDITOR=vim \
    LANG=en_US.UTF-8 \
    GOPATH=${HOME}/go \
    PATH=/usr/local/go/bin:${HOME}/go/bin:${HOME}/.local/bin:${PATH} \
    PLAYWRIGHT_BROWSERS_PATH=${HOME}/.cache/ms-playwright

LABEL org.opencontainers.image.source="https://github.com/kim-tae-kyung/code-devcontainer"
LABEL org.opencontainers.image.description="Development container with Claude Code and Codex CLI"

# Switch to non-root user early
USER node

# Install system packages
RUN sudo apt-get update && \
  sudo apt-get -y install --no-install-recommends \
    git gh jq ripgrep curl \
    iproute2 dnsutils iputils-ping net-tools \
    vim tree tmux \
    postgresql-client \
    python3 python3-pip python3-venv && \
  sudo apt-get clean && \
  sudo rm -rf /var/lib/apt/lists/*

# Install Go
RUN GO_VERSION_STR=$(curl -sSL "https://go.dev/VERSION?m=text" | head -n 1) && \
  GO_VERSION=${GO_VERSION_STR#go} && \
  echo "Installing Go version: ${GO_VERSION}" && \
  curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${TARGETARCH}.tar.gz" -o /tmp/go.tar.gz && \
  sudo tar -C /usr/local -xzf /tmp/go.tar.gz && \
  rm /tmp/go.tar.gz

# Install Chromium for headless browser testing via Playwright MCP
RUN npx playwright install --with-deps chromium && \
  sudo apt-get clean && \
  sudo rm -rf /var/lib/apt/lists/*

# Ensure Go PATH persists in tmux login shells (which reset PATH via /etc/profile)
RUN echo "export PATH=\"/usr/local/go/bin:${HOME}/go/bin:${HOME}/.local/bin:\$PATH\"" | sudo tee /etc/profile.d/golang.sh

# Create workspace
RUN sudo install -d -o node -g node /workspace

# Install LSPs and formatters
RUN go install golang.org/x/tools/gopls@latest
RUN go install github.com/mikefarah/yq/v4@latest
RUN npm install -g pyright typescript typescript-language-server
RUN pip3 install --user --break-system-packages 'python-lsp-server[all]' black isort

# Copy configuration files
COPY --chown=node:node claude-settings.json   ${HOME}/.claude/settings.json
COPY --chown=node:node claude-mcp.json        ${HOME}/.claude.json
COPY --chown=node:node codex-config.toml      ${HOME}/.codex/config.toml
COPY --chown=node:node operating-principles.md ${HOME}/.claude/CLAUDE.md
COPY --chown=node:node operating-principles.md ${HOME}/.codex/AGENTS.md
COPY --chown=node:node tmux.conf              ${HOME}/.tmux.conf
COPY --chown=node:node vimrc                  ${HOME}/.vimrc

# Install Claude Code
RUN curl -fsSL https://claude.ai/install.sh | bash

# Install Codex CLI
RUN npm install -g @openai/codex

# Smoke test
RUN claude --version && codex --version && \
  go version && gopls version && yq --version && \
  node --version && python3 --version && \
  black --version && pylsp --help >/dev/null

WORKDIR /workspace
