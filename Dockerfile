# Reference: https://github.com/anthropics/claude-code/tree/main/.devcontainer
# Base image for Node.js development.
FROM --platform=$TARGETPLATFORM mcr.microsoft.com/devcontainers/typescript-node:24

# Build arguments for multi-platform support.
ARG TARGETPLATFORM
ARG TARGETARCH

# Set timezone.
ARG TZ="Asia/Seoul"
ENV TZ=${TZ}
# Non-interactive frontend for apt.
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies, Python, and Go in a single layer.
RUN apt-get update && \
  apt-get -y install --no-install-recommends \
  git gh jq ripgrep curl \
  less procps fzf man-db unzip gnupg2 \
  iproute2 dnsutils iputils-ping net-tools \
  vim tree tmux \
  postgresql-client \
  python3 python3-pip python3-venv && \
  # Install Go (latest).
  GO_VERSION_STR=$(curl -sSL "https://go.dev/VERSION?m=text" | head -n 1) && \
  GO_VERSION=${GO_VERSION_STR#go} && \
  echo "Installing Go version: ${GO_VERSION}" && \
  curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${TARGETARCH}.tar.gz" -o /tmp/go.tar.gz && \
  tar -C /usr/local -xzf /tmp/go.tar.gz && \
  rm /tmp/go.tar.gz && \
  # Install gopls.
  export PATH="/usr/local/go/bin:$PATH" && \
  go install golang.org/x/tools/gopls@latest && \
  mv /root/go/bin/gopls /usr/local/bin/gopls && \
  rm -rf /root/go && \
  # Clean up apt cache.
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*

# Set environment variables.
ENV PATH="/usr/local/go/bin:${PATH}"
ENV GOPATH="/home/node/go"
ENV PATH="${GOPATH}/bin:${PATH}"
ENV EDITOR=vim
ENV LANG=en_US.UTF-8

# OCI Labels
LABEL org.opencontainers.image.source="https://github.com/kim-tae-kyung/code-devcontainer"
LABEL org.opencontainers.image.description="Development container with Claude Code and Gemini CLI"

# Create and set permissions for workspace and config dirs.
RUN mkdir -p /workspace /home/node/.claude /home/node/.gemini && \
  chown -R node:node /workspace /home/node/.claude /home/node/.gemini

# Switch to non-root user for security.
USER node

# Cache bust argument for CLI tools (changes each build to ensure latest versions).
ARG CACHEBUST=1

# Install Claude Code (always fetch latest).
RUN echo "Cache bust: ${CACHEBUST}" && \
    curl -fsSL https://claude.ai/install.sh | bash

# Install Gemini CLI (always fetch latest).
RUN echo "Cache bust: ${CACHEBUST}" && \
    npm install -g @google/gemini-cli

# Install additional tools (LSPs).
RUN npm install -g pyright typescript typescript-language-server

# Install Python LSP and formatters.
RUN pip3 install --user --break-system-packages python-lsp-server[all] black isort

# Copy configuration files.
COPY --chown=node:node claude-settings.json /home/node/.claude/settings.json
COPY --chown=node:node gemini-settings.json /home/node/.gemini/settings.json

# Set working directory.
WORKDIR /workspace
