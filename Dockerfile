# Reference: https://github.com/anthropics/claude-code/tree/main/.devcontainer
# Base image for Node.js development.
FROM --platform=$TARGETPLATFORM mcr.microsoft.com/devcontainers/typescript-node:22

# Build arguments for multi-platform support.
ARG TARGETPLATFORM
ARG TARGETARCH

# Set timezone.
ARG TZ="Asia/Seoul"
ENV TZ=${TZ}
# Non-interactive frontend for apt.
ENV DEBIAN_FRONTEND=noninteractive

# Set Go version via build argument.
ARG GO_VERSION=1.24.5

# Install system dependencies and Go in a single layer.
RUN apt-get update && \
  apt-get -y install --no-install-recommends \
  git gh jq ripgrep curl \
  less procps fzf man-db unzip gnupg2 \
  iproute2 dnsutils iputils-ping net-tools \
  vim tree tmux \
  postgresql-client && \
  # Install Go.
  echo "Installing Go version: ${GO_VERSION}" && \
  curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${TARGETARCH}.tar.gz" -o /tmp/go.tar.gz && \
  tar -C /usr/local -xzf /tmp/go.tar.gz && \
  rm /tmp/go.tar.gz && \
  # Clean up apt cache.
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*

# Set environment variables.
ENV PATH="/usr/local/go/bin:${PATH}"
ENV EDITOR=vim
ENV LANG=en_US.UTF-8

# Create and set permissions for workspace and config dirs.
RUN mkdir -p /workspace /home/node/.claude /home/node/.gemini && \
  chown -R node:node /workspace /home/node/.claude /home/node/.gemini

# Create a system-wide 'gemini' command wrapper.
RUN echo '#!/bin/sh' > /usr/local/bin/gemini && \
  echo 'exec npx https://github.com/google-gemini/gemini-cli "$@"' >> /usr/local/bin/gemini && \
  chmod +x /usr/local/bin/gemini

# Switch to non-root user for security.
USER node

# Install claude code via npm and migrate to local installation.
RUN npm install -g @anthropic-ai/claude-code && \
  CI=true claude migrate-installer

# Set working directory.
WORKDIR /workspace
