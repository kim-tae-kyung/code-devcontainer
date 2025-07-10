# Reference: https://github.com/anthropics/claude-code/tree/main/.devcontainer
# Base image from Microsoft's devcontainer repository, including Node.js and TypeScript.
# Using --platform=$TARGETPLATFORM for multi-platform build support.
FROM --platform=$TARGETPLATFORM mcr.microsoft.com/devcontainers/typescript-node:22

# Load build arguments for multi-platform support.
ARG TARGETPLATFORM
ARG TARGETARCH

# Set the timezone.
ARG TZ="Asia/Seoul"
ENV TZ=${TZ}
# Set DEBIAN_FRONTEND to noninteractive to avoid prompts during package installation.
ENV DEBIAN_FRONTEND=noninteractive

# Set the Go version via a build argument for flexibility and reproducibility.
# This can be overridden during the build process, e.g., --build-arg GO_VERSION=1.25.0
ARG GO_VERSION=1.24.4

# Install essential packages, Go, and clean up in a single RUN layer to reduce image size.
RUN apt-get update && \
  apt-get -y install --no-install-recommends \
  # Essential tools
  git gh jq ripgrep curl \
  # Utilities
  less procps fzf man-db unzip gnupg2 \
  # Networking tools
  iproute2 dnsutils iputils-ping net-tools \
  # Development tools
  vim tree tmux && \
  # Install Go (Golang) using the specified version.
  echo "Installing Go version: ${GO_VERSION}" && \
  curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${TARGETARCH}.tar.gz" -o /tmp/go.tar.gz && \
  tar -C /usr/local -xzf /tmp/go.tar.gz && \
  rm /tmp/go.tar.gz && \
  # Clean up apt cache to reduce image size.
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*

# Set environment variables for Go and the shell.
ENV GOPATH="/go"
ENV PATH="/usr/local/go/bin:${GOPATH}/bin:${PATH}"
ENV EDITOR=vim
ENV LANG=en_US.UTF-8

# Create workspace and configuration directories, and set ownership to the 'node' user.
# This ensures that mounted volumes will have the correct permissions.
RUN mkdir -p /workspace /home/node/.claude /home/node/.gemini && \
  chown -R node:node /workspace /home/node/.claude /home/node/.gemini

# Switch to the non-root 'node' user for better security.
USER node

# Install global npm packages.
RUN npm install -g @anthropic-ai/claude-code

# Create a shell-agnostic wrapper script for gemini-cli.
# This makes the 'gemini' command available system-wide, not just in bash.
# It executes npx to always fetch the latest version of the CLI.
RUN echo '#!/bin/sh' > /usr/local/bin/gemini && \
  echo 'exec npx https://github.com/google-gemini/gemini-cli "$@"' >> /usr/local/bin/gemini && \
  chmod +x /usr/local/bin/gemini

# Set the default working directory for the container.
WORKDIR /workspace
