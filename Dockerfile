# https://github.com/anthropics/claude-code/tree/main/.devcontainer

FROM --platform=$TARGETPLATFORM mcr.microsoft.com/devcontainers/typescript-node:22

# Load build arguments for multi-platform support
ARG TARGETPLATFORM
ARG TARGETARCH

# Set timezone and non-interactive frontend for apt
ARG TZ="Asia/Seoul"
ENV TZ=${TZ}
ENV DEBIAN_FRONTEND=noninteractive

# Install essential packages and clean up
RUN apt-get update && \
  apt-get -y install --no-install-recommends \
    git gh jq ripgrep \
    less procps fzf man-db unzip gnupg2 \
    iproute2 dnsutils iputils-ping net-tools \
    vim tree && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*

# Install Go (Golang)
ENV GO_VERSION=1.24.4
RUN curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${TARGETARCH}.tar.gz" -o /tmp/go.tar.gz \
    && rm -rf /usr/local/go \
    && tar -C /usr/local -xzf /tmp/go.tar.gz \
    && rm /tmp/go.tar.gz

ENV PATH="/usr/local/go/bin:${PATH}"

# Create workspace and .claude directory with correct permissions
RUN mkdir -p /workspace /home/node/.claude && \
  chown -R node:node /workspace /home/node/.claude

# Install global npm packages as node user
USER node
RUN npm install -g @anthropic-ai/claude-code @google/gemini-cli

WORKDIR /workspace