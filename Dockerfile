FROM --platform=$TARGETPLATFORM mcr.microsoft.com/devcontainers/typescript-node:24@sha256:b55b444f6658dd2370d430c12d4bc9540c8ed0d3d5b05e4c247161173666954f

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
    CARGO_HOME=${HOME}/.cargo \
    RUSTUP_HOME=${HOME}/.rustup \
    PATH=/usr/local/go/bin:${HOME}/go/bin:${HOME}/.cargo/bin:${HOME}/.local/bin:${PATH} \
    PLAYWRIGHT_BROWSERS_PATH=${HOME}/.cache/ms-playwright \
    CAPTURE_DEMO_RUNTIME_DIR=${HOME}/.claude/skills/capture-demo

LABEL org.opencontainers.image.source="https://github.com/kim-tae-kyung/code-devcontainer"
LABEL org.opencontainers.image.description="Development container with Claude Code and Codex CLI"

# Switch to non-root user early
USER node

# Install system packages
RUN sudo apt-get update && \
  sudo apt-get -y install --no-install-recommends \
    git gh jq ripgrep curl tini \
    iproute2 dnsutils iputils-ping net-tools \
    vim tree tmux ncurses-bin \
    python3 python3-pip python3-venv && \
  sudo apt-get clean && \
  sudo rm -rf /var/lib/apt/lists/*

# Install Go
RUN GO_VERSION_STR=$(curl -sSL "https://go.dev/VERSION?m=text" | head -n 1) && \
  GO_VERSION=${GO_VERSION_STR#go} && \
  echo "Installing Go version: ${GO_VERSION}" && \
  curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${TARGETARCH}.tar.gz" -o /tmp/go.tar.gz && \
  sudo rm -rf /usr/local/go && \
  sudo tar -C /usr/local -xzf /tmp/go.tar.gz && \
  rm /tmp/go.tar.gz

# Install Rust (minimal profile) with rust-analyzer for LSP support.
# rustup detects the target architecture itself, so no TARGETARCH branching.
RUN curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs | \
  sh -s -- -y --no-modify-path --profile minimal --default-toolchain stable -c rust-analyzer

# Install agg (asciinema gif generator; renders .cast recordings to GIF).
# aarch64 ships only a gnu build, amd64 a static musl build — both run on the glibc base.
ARG AGG_VERSION=v1.9.0
RUN case "${TARGETARCH}" in \
      amd64) AGG_TARGET=x86_64-unknown-linux-musl ;; \
      arm64) AGG_TARGET=aarch64-unknown-linux-gnu ;; \
      *) echo "unsupported arch: ${TARGETARCH}" >&2; exit 1 ;; \
    esac && \
  curl -fsSL "https://github.com/asciinema/agg/releases/download/${AGG_VERSION}/agg-${AGG_TARGET}" -o /tmp/agg && \
  sudo install -m 0755 /tmp/agg /usr/local/bin/agg && \
  rm /tmp/agg

# Install Chromium for headless browser testing via Playwright MCP. The browser
# revision comes from the pinned server's own playwright core, so the pair cannot
# drift apart on a rebuild. Renovate raises the pin; the browser follows.
ARG PLAYWRIGHT_MCP_VERSION=0.0.79
RUN set -e; \
  PLAYWRIGHT_CORE="$(npm view "@playwright/mcp@${PLAYWRIGHT_MCP_VERSION}" dependencies.playwright)"; \
  if ! echo "${PLAYWRIGHT_CORE}" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$'; then \
    echo "playwright dependency is not an exact version: '${PLAYWRIGHT_CORE}'" >&2; \
    exit 1; \
  fi; \
  echo "Installing Chromium for playwright ${PLAYWRIGHT_CORE}"; \
  npx -y "playwright@${PLAYWRIGHT_CORE}" install --with-deps chromium; \
  npx -y "playwright@${PLAYWRIGHT_CORE}" screenshot --browser=chromium about:blank /tmp/launch-check.png; \
  rm /tmp/launch-check.png; \
  sudo apt-get clean; \
  sudo rm -rf /var/lib/apt/lists/*

# Ensure Go/Rust PATH persists in tmux login shells (which reset PATH via /etc/profile)
RUN echo "export PATH=\"/usr/local/go/bin:${HOME}/go/bin:${HOME}/.cargo/bin:${HOME}/.local/bin:\$PATH\"" | sudo tee /etc/profile.d/golang.sh

# Create workspace
RUN sudo install -d -o node -g node /workspace

# Install LSPs and formatters
RUN go install golang.org/x/tools/gopls@latest
RUN go install github.com/mikefarah/yq/v4@latest
RUN npm install -g pyright typescript typescript-language-server
RUN pip3 install --user --break-system-packages 'python-lsp-server[all]' black isort asciinema==2.4.0

# Copy configuration files
COPY --chown=node:node claude-settings.json   ${HOME}/.claude/settings.json
COPY --chown=node:node codex-config.toml      ${HOME}/.codex/config.toml
COPY --chown=node:node operating-principles.md ${HOME}/.claude/CLAUDE.md
COPY --chown=node:node operating-principles.md ${HOME}/.codex/AGENTS.md
COPY --chown=node:node tmux.conf              ${HOME}/.tmux.conf
COPY --chown=node:node vimrc                  ${HOME}/.vimrc

# Ship agent skills to each CLI's user-level discovery directory.
COPY --chown=node:node .claude/skills/ ${HOME}/.claude/skills/
COPY --chown=node:node .agents/skills/ ${HOME}/.agents/skills/

# Vendor the shared capture-demo runtime and exercise both render paths.
RUN cd ${CAPTURE_DEMO_RUNTIME_DIR} && npm ci --omit=dev && npm test

# Install Claude Code
RUN curl -fsSL https://claude.ai/install.sh | bash

# Install Codex CLI
RUN npm install -g @openai/codex

# Install Claude Code plugins: the code-intelligence plugins activate the LSP
# tool for the language servers installed above (gopls, pyright,
# typescript-language-server, rust-analyzer); context7 (Upstash's hosted HTTP
# server — no npx process per session) and playwright replace local MCP
# registrations, so no `claude mcp add` runs at build. The playwright plugin
# launches `@playwright/mcp@latest` with no flags; the flags the old MCP
# registration passed (--headless --browser=chromium --no-sandbox) come from
# PLAYWRIGHT_MCP_* env vars in claude-settings.json instead. Installing at
# build time bakes the plugin cache into the image so sessions need no
# marketplace clone at pod start.
RUN claude plugin marketplace add anthropics/claude-plugins-official && \
  claude plugin install gopls-lsp@claude-plugins-official && \
  claude plugin install pyright-lsp@claude-plugins-official && \
  claude plugin install typescript-lsp@claude-plugins-official && \
  claude plugin install rust-analyzer-lsp@claude-plugins-official && \
  claude plugin install context7@claude-plugins-official && \
  claude plugin install playwright@claude-plugins-official

# Install the latest stable Herdr release. Its installer selects the native
# Linux asset and verifies the release-published SHA-256 checksum.
RUN curl -fsSL https://herdr.dev/install.sh | sh

# Install Herdr's native session integrations after both agent configs have
# reached their final build-time state. The bundled skill is release-matched;
# install it into the same user-level discovery directories as the other skills.
RUN herdr integration install claude && \
  herdr integration install codex && \
  install -d ${HOME}/.claude/skills/herdr ${HOME}/.agents/skills/herdr && \
  herdr --skill > /tmp/herdr-SKILL.md && \
  install -m 0644 /tmp/herdr-SKILL.md ${HOME}/.claude/skills/herdr/SKILL.md && \
  install -m 0644 /tmp/herdr-SKILL.md ${HOME}/.agents/skills/herdr/SKILL.md && \
  rm /tmp/herdr-SKILL.md

# Fail the build if a server does not load. The pinned check covers Codex's
# playwright server and pre-warms the npx cache. The `@latest` checks (the
# Claude Code playwright plugin, and context7 for Codex) are re-resolved per
# session, so they cover the build only.
RUN npx -y "@playwright/mcp@${PLAYWRIGHT_MCP_VERSION}" --version && \
  npx -y @playwright/mcp@latest --version && \
  npx -y @upstash/context7-mcp --version

# Smoke test
RUN test -f ${HOME}/.agents/skills/docs-visual/SKILL.md && \
  test -f ${HOME}/.agents/skills/capture-demo/SKILL.md && \
  grep -q '^name: herdr$' ${HOME}/.claude/skills/herdr/SKILL.md && \
  grep -q '^name: herdr$' ${HOME}/.agents/skills/herdr/SKILL.md && \
  claude --version && codex --version && codex --strict-config mcp-server </dev/null >/dev/null && \
  herdr --version && herdr --help >/dev/null && \
  herdr integration status | grep -q '^claude: current ' && \
  herdr integration status | grep -q '^codex: current ' && \
  go version && gopls version && yq --version && \
  cargo --version && rustc --version && rust-analyzer --version && \
  test -d ${HOME}/.claude/plugins/cache/claude-plugins-official/gopls-lsp && \
  test -d ${HOME}/.claude/plugins/cache/claude-plugins-official/pyright-lsp && \
  test -d ${HOME}/.claude/plugins/cache/claude-plugins-official/typescript-lsp && \
  test -d ${HOME}/.claude/plugins/cache/claude-plugins-official/rust-analyzer-lsp && \
  test -d ${HOME}/.claude/plugins/cache/claude-plugins-official/context7 && \
  test -d ${HOME}/.claude/plugins/cache/claude-plugins-official/playwright && \
  command -v pyright-langserver && \
  node --version && python3 --version && \
  tmux -V && dpkg --compare-versions "$(tmux -V | awk '{print $2}')" ge 3.5 && \
  infocmp -x tmux-256color >/dev/null && \
  tmux -L config-smoke -f ${HOME}/.tmux.conf start-server \; kill-server && \
  black --version && pylsp --help >/dev/null && \
  typescript-language-server --version && pyright --version && isort --version && \
  asciinema --version && agg --version

WORKDIR /workspace

# PID 1 must reap zombies; -s keeps reaping as subreaper when pause is PID 1 (shareProcessNamespace)
ENTRYPOINT ["/usr/bin/tini", "-s", "--"]

# ENTRYPOINT clears the base image CMD, so supply the long-lived default the pod
# expects. Override it for interactive runs: `docker run -it <image> /bin/bash`.
CMD ["sleep", "infinity"]
