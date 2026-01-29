FROM --platform=$TARGETPLATFORM mcr.microsoft.com/devcontainers/typescript-node:24

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

# Environment variables
ENV PATH="/usr/local/go/bin:${PATH}"
ENV GOPATH="/home/node/go"
ENV PATH="${GOPATH}/bin:${PATH}"
ENV EDITOR=vim
ENV LANG=en_US.UTF-8

# OCI Labels
LABEL org.opencontainers.image.source="https://github.com/kim-tae-kyung/code-devcontainer"
LABEL org.opencontainers.image.description="Development container with Claude Code and Gemini CLI"

# Create workspace and config directories
RUN sudo mkdir -p /workspace && \
  mkdir -p /home/node/.claude /home/node/.gemini && \
  sudo chown -R node:node /workspace

# Install LSPs and formatters
RUN go install golang.org/x/tools/gopls@latest
RUN npm install -g pyright typescript typescript-language-server
RUN pip3 install --user --break-system-packages python-lsp-server[all] black isort

# Copy configuration files
COPY --chown=node:node claude-settings.json /home/node/.claude/settings.json
COPY --chown=node:node gemini-settings.json /home/node/.gemini/settings.json

# Install Claude Code (always latest via cache invalidation)
RUN date && curl -fsSL https://claude.ai/install.sh | bash

# Install Gemini CLI (always latest via cache invalidation)
RUN date && npm install -g @google/gemini-cli

WORKDIR /workspace
