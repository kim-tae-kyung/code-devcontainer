FROM --platform=$TARGETPLATFORM mcr.microsoft.com/devcontainers/typescript-node:24@sha256:58cdebfe398bd451d5f51a567a00d9880691a17a93236d2be07354b80e6e289e

ARG TARGETPLATFORM
ARG TARGETARCH

ARG TZ="Asia/Seoul"
ENV TZ=${TZ}
ENV DEBIAN_FRONTEND=noninteractive

# Switch to non-root user early
USER node

# Install system packages and Go (sudo for root operations)
RUN sudo apt-get update && \
  sudo apt-get -y install --no-install-recommends \
  git gh jq ripgrep curl \
  less procps fzf man-db unzip gnupg2 \
  iproute2 dnsutils iputils-ping net-tools \
  vim tree tmux \
  postgresql-client \
  python3 python3-pip python3-venv && \
  GO_VERSION_STR=$(curl -sSL "https://go.dev/VERSION?m=text" | head -n 1) && \
  GO_VERSION=${GO_VERSION_STR#go} && \
  echo "Installing Go version: ${GO_VERSION}" && \
  curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${TARGETARCH}.tar.gz" -o /tmp/go.tar.gz && \
  sudo tar -C /usr/local -xzf /tmp/go.tar.gz && \
  rm /tmp/go.tar.gz && \
  sudo apt-get clean && \
  sudo rm -rf /var/lib/apt/lists/*

# Install Chromium for headless browser testing via Playwright MCP
ENV PLAYWRIGHT_BROWSERS_PATH=/home/node/.cache/ms-playwright
RUN npx playwright install --with-deps chromium && \
  sudo apt-get clean && \
  sudo rm -rf /var/lib/apt/lists/*

# Environment variables
ENV PATH="/usr/local/go/bin:${PATH}"
ENV GOPATH="/home/node/go"
ENV PATH="${GOPATH}/bin:${PATH}"
ENV EDITOR=vim
ENV LANG=en_US.UTF-8

# Ensure Go PATH persists in tmux login shells (which reset PATH via /etc/profile)
RUN echo 'export PATH="/usr/local/go/bin:/home/node/go/bin:$PATH"' | sudo tee /etc/profile.d/golang.sh

# OCI Labels
LABEL org.opencontainers.image.source="https://github.com/kim-tae-kyung/code-devcontainer"
LABEL org.opencontainers.image.description="Development container with Claude Code and Codex CLI"

# Create workspace and config directories
RUN sudo mkdir -p /workspace && \
  mkdir -p /home/node/.claude /home/node/.codex && \
  sudo chown -R node:node /workspace

# Install LSPs and formatters
RUN go install golang.org/x/tools/gopls@latest
RUN npm install -g pyright typescript typescript-language-server
RUN pip3 install --user --break-system-packages python-lsp-server[all] black isort

# Copy configuration files
COPY --chown=node:node claude-settings.json /home/node/.claude/settings.json
COPY --chown=node:node claude-mcp.json /home/node/.claude.json
COPY --chown=node:node codex-config.toml /home/node/.codex/config.toml
COPY --chown=node:node tmux.conf /home/node/.tmux.conf
COPY --chown=node:node vimrc /home/node/.vimrc

# Install Claude Code
RUN curl -fsSL https://claude.ai/install.sh | bash

# Install Codex CLI
RUN npm install -g @openai/codex

WORKDIR /workspace
