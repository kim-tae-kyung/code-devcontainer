FROM mcr.microsoft.com/devcontainers/typescript-node:24@sha256:b55b444f6658dd2370d430c12d4bc9540c8ed0d3d5b05e4c247161173666954f

ARG TARGETARCH
ARG TZ="Asia/Seoul"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Base image does not declare HOME in ENV; set it explicitly so ${HOME} expands
# in subsequent ENV/COPY/RUN instructions during build.
ENV HOME=/home/node

ENV TZ=${TZ} \
    SHELL=/bin/bash \
    DEBIAN_FRONTEND=noninteractive \
    EDITOR=nvim \
    VISUAL=nvim \
    LANG=en_US.UTF-8 \
    GOPATH=${HOME}/go \
    CARGO_HOME=${HOME}/.cargo \
    RUSTUP_HOME=${HOME}/.rustup \
    PATH=/usr/local/go/bin:${HOME}/go/bin:${HOME}/.cargo/bin:${HOME}/.local/bin:${PATH}

LABEL org.opencontainers.image.source="https://github.com/kim-tae-kyung/code-devcontainer"
LABEL org.opencontainers.image.description="Development container with Claude Code and Codex CLI"

# Switch to non-root user early
USER node

# Install system packages
RUN sudo apt-get update && \
  sudo apt-get -y install --no-install-recommends \
    git gh jq ripgrep curl tini diffutils \
    iproute2 dnsutils iputils-ping net-tools \
    tree \
    python3 python3-pip python3-venv && \
  sudo apt-get clean && \
  sudo rm -rf /var/lib/apt/lists/*

# Install the latest stable Neovim, including its runtime, for the native arch.
# Release asset digests: https://docs.github.com/en/rest/releases/assets
# CI authenticates the API request to avoid the shared runner IP's rate limit.
# https://docs.docker.com/build/ci/github-actions/secrets/
RUN --mount=type=secret,id=github_token,uid=1000 \
  case "${TARGETARCH}" in \
      amd64) NVIM_ARCH=x86_64 ;; \
      arm64) NVIM_ARCH=arm64 ;; \
      *) echo "unsupported arch: ${TARGETARCH}" >&2; exit 1 ;; \
    esac && \
  NVIM_API_HEADERS=() && \
  if [ -f /run/secrets/github_token ]; then \
    NVIM_API_HEADERS=(-H "Authorization: Bearer $(cat /run/secrets/github_token)"); \
  fi && \
  NVIM_RELEASE="$(curl -fsSL "${NVIM_API_HEADERS[@]}" https://api.github.com/repos/neovim/neovim/releases/latest)" && \
  NVIM_ASSET="$(jq -ce --arg name "nvim-linux-${NVIM_ARCH}.tar.gz" \
    '.assets[] | select(.name == $name)' <<< "${NVIM_RELEASE}")" && \
  NVIM_URL="$(jq -er '.browser_download_url' <<< "${NVIM_ASSET}")" && \
  NVIM_SHA256="$(jq -er '.digest | select(test("^sha256:[0-9a-f]{64}$")) | ltrimstr("sha256:")' <<< "${NVIM_ASSET}")" && \
  curl -fsSL "${NVIM_URL}" -o /tmp/nvim.tar.gz && \
  echo "${NVIM_SHA256}  /tmp/nvim.tar.gz" | sha256sum --check && \
  sudo install -d /opt/nvim && \
  sudo tar -xzf /tmp/nvim.tar.gz -C /opt/nvim --strip-components=1 && \
  sudo ln -s /opt/nvim/bin/nvim /usr/local/bin/nvim && \
  rm /tmp/nvim.tar.gz && \
  nvim --version && \
  nvim --clean --headless -c 'lua if vim.fn.has("nvim-0.12") == 0 then vim.cmd.cquit() end' -c qa && \
  sudo git config --system core.editor nvim

# Install Go
RUN GO_VERSION_STR=$(curl -sSL "https://go.dev/VERSION?m=text" | head -n 1) && \
  GO_VERSION=${GO_VERSION_STR#go} && \
  echo "Installing Go version: ${GO_VERSION}" && \
  curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${TARGETARCH}.tar.gz" -o /tmp/go.tar.gz && \
  sudo rm -rf /usr/local/go && \
  sudo tar -C /usr/local -xzf /tmp/go.tar.gz && \
  rm /tmp/go.tar.gz

# Install Rust with the LSP server, standard-library sources and formatter.
# rustup detects the target architecture itself, so no TARGETARCH branching.
RUN curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs | \
  sh -s -- -y --no-modify-path --profile minimal --default-toolchain stable \
    -c rust-analyzer -c rust-src -c rustfmt

# Install Chromium for headless browser testing via Playwright MCP. The browser
# revision comes from the pinned server's own playwright core, so the pair cannot
# drift apart on a rebuild. Renovate raises the pin; the browser follows.
ARG PLAYWRIGHT_MCP_VERSION=0.0.85
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

# Ensure Go/Rust PATH persists in login shells (which reset PATH via /etc/profile)
RUN echo "export PATH=\"/usr/local/go/bin:${HOME}/go/bin:${HOME}/.cargo/bin:${HOME}/.local/bin:\$PATH\"" | sudo tee /etc/profile.d/golang.sh

# Create workspace
RUN sudo install -d -o node -g node /workspace

# Install LSPs and formatters
RUN go install golang.org/x/tools/gopls@latest
RUN go install github.com/mikefarah/yq/v4@latest
# This server requires the JavaScript tsserver from TypeScript 6, not TS 7.
# https://github.com/typescript-language-server/typescript-language-server#installing
RUN npm install -g pyright typescript@6 typescript-language-server
RUN pip3 install --user --break-system-packages black isort

# Copy configuration files
COPY --chown=node:node claude-settings.json   ${HOME}/.claude/settings.json
COPY --chown=node:node codex-config.toml      ${HOME}/.codex/config.toml
COPY --chown=node:node operating-principles.md ${HOME}/.claude/CLAUDE.md
COPY --chown=node:node operating-principles.md ${HOME}/.codex/AGENTS.md
COPY --chown=node:node herdr-config.toml      ${HOME}/.config/herdr/config.toml
COPY --chown=node:node bash_aliases           ${HOME}/.bash_aliases
COPY --chown=node:node nvim/                  ${HOME}/.config/nvim/
COPY --chmod=0755 scripts/git-ndiff           /usr/local/bin/git-ndiff
COPY --chmod=0755 scripts/herdr               /usr/local/bin/herdr

# Ship the Claude Code skills to its user-level discovery directory.
COPY --chown=node:node .claude/skills/ ${HOME}/.claude/skills/

# Install the latest stable kubectl for the target architecture and verify it.
# https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/
RUN KUBECTL_VERSION="$(curl -fsSL https://dl.k8s.io/release/stable.txt)" && \
  curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl" -o /tmp/kubectl && \
  curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl.sha256" -o /tmp/kubectl.sha256 && \
  echo "$(cat /tmp/kubectl.sha256)  /tmp/kubectl" | sha256sum --check && \
  sudo install -m 0755 /tmp/kubectl /usr/local/bin/kubectl && \
  rm /tmp/kubectl /tmp/kubectl.sha256

# Install the latest stable GitLab CLI for the target architecture and verify it.
# https://gitlab.com/gitlab-org/cli/-/releases
RUN GLAB_RELEASE="$(curl -fsSL https://gitlab.com/api/v4/projects/gitlab-org%2Fcli/releases/permalink/latest)" && \
  GLAB_VERSION="$(jq -er '.tag_name | ltrimstr("v")' <<< "${GLAB_RELEASE}")" && \
  GLAB_ARCHIVE="glab_${GLAB_VERSION}_linux_${TARGETARCH}.tar.gz" && \
  GLAB_URL="$(jq -er --arg name "${GLAB_ARCHIVE}" '.assets.links[] | select(.name == $name) | .direct_asset_url' <<< "${GLAB_RELEASE}")" && \
  GLAB_CHECKSUMS_URL="$(jq -er '.assets.links[] | select(.name == "checksums.txt") | .direct_asset_url' <<< "${GLAB_RELEASE}")" && \
  mkdir /tmp/glab && \
  curl -fsSL "${GLAB_URL}" -o "/tmp/glab/${GLAB_ARCHIVE}" && \
  curl -fsSL "${GLAB_CHECKSUMS_URL}" -o /tmp/glab/checksums.txt && \
  GLAB_SHA256="$(awk -v name="${GLAB_ARCHIVE}" '$2 == name {print $1}' /tmp/glab/checksums.txt)" && \
  echo "${GLAB_SHA256}  /tmp/glab/${GLAB_ARCHIVE}" | sha256sum --check && \
  tar -xzf "/tmp/glab/${GLAB_ARCHIVE}" -C /tmp/glab bin/glab && \
  sudo install -m 0755 /tmp/glab/bin/glab /usr/local/bin/glab && \
  rm -rf /tmp/glab

# Install Claude Code
RUN curl -fsSL https://claude.ai/install.sh | bash

# Install Codex CLI
RUN npm install -g @openai/codex

# Install code intelligence plugins.
# https://code.claude.com/docs/en/discover-plugins
RUN claude plugin marketplace add anthropics/claude-plugins-official && \
  claude plugin install gopls-lsp@claude-plugins-official && \
  claude plugin install pyright-lsp@claude-plugins-official && \
  claude plugin install typescript-lsp@claude-plugins-official && \
  claude plugin install rust-analyzer-lsp@claude-plugins-official

# Both agents use the same server and the Chromium installed for that pin.
# User scope makes the registration available in every project.
# https://code.claude.com/docs/en/mcp#user-scope
RUN claude mcp add --transport stdio --scope user playwright -- \
  npx -y "@playwright/mcp@${PLAYWRIGHT_MCP_VERSION}" \
  --headless --browser=chromium --no-sandbox

# Disable the empty-prompt left-arrow gesture that opens the agents view and
# hands a working session to a background copy. Herdr owns backgrounding here.
# This is a global-config key in ~/.claude.json, not a settings.json key.
RUN jq '. + {leftArrowOpensAgents: false}' ${HOME}/.claude.json > /tmp/claude.json && \
  mv /tmp/claude.json ${HOME}/.claude.json

# Install the latest stable Herdr release. Its installer selects the native
# Linux asset and verifies the release-published SHA-256 checksum. The binary
# goes to /opt/herdr; /usr/local/bin/herdr waits for a terminal size, then runs it.
RUN sudo install -d -o node -g node /opt/herdr && \
  curl -fsSL https://herdr.dev/install.sh | HERDR_INSTALL_DIR=/opt/herdr sh && \
  test ! -e ${HOME}/.local/bin/herdr

# Install Herdr's native session integrations after both agent configs have
# reached their final build-time state.
RUN herdr integration install claude && \
  herdr integration install codex

# Track the official skill independently of the installed Herdr release. Remote
# ADD checks source changes even when preceding install layers are cached.
# https://herdr.dev/docs/agent-skill/
ADD --chown=node:node https://raw.githubusercontent.com/herdrdev/herdr/master/skills/herdr/SKILL.md /tmp/herdr-SKILL.md
RUN test -s /tmp/herdr-SKILL.md && \
  test "$(head -n 1 /tmp/herdr-SKILL.md)" = '---' && \
  grep -q '^name: herdr$' /tmp/herdr-SKILL.md && \
  install -d ${HOME}/.claude/skills/herdr ${HOME}/.agents/skills/herdr && \
  install -m 0644 /tmp/herdr-SKILL.md ${HOME}/.claude/skills/herdr/SKILL.md && \
  install -m 0644 /tmp/herdr-SKILL.md ${HOME}/.agents/skills/herdr/SKILL.md && \
  sha256sum /tmp/herdr-SKILL.md && \
  rm /tmp/herdr-SKILL.md

# Load the pinned browser server and pre-warm its npx cache.
RUN npx -y "@playwright/mcp@${PLAYWRIGHT_MCP_VERSION}" --version

# Smoke test: the installed tools run, the CLI interfaces the skills and
# integrations rely on exist, and no credentials are baked in.
RUN test "$(printenv SHELL)" = /bin/bash && \
  claude --version && codex --version && codex --strict-config app-server </dev/null >/dev/null && \
  codex exec --help >/dev/null && codex exec review --help >/dev/null && \
  codex features list | grep -E '^image_generation +stable +true' >/dev/null && \
  herdr --version && herdr --help >/dev/null && herdr config check && \
  herdr integration status | grep '^claude: current ' >/dev/null && \
  herdr integration status | grep '^codex: current ' >/dev/null && \
  jq -e '.hooks.SessionStart' ${HOME}/.claude/settings.json >/dev/null && \
  test "$(bash -ic 'alias claude' 2>/dev/null)" = "alias claude='claude --dangerously-skip-permissions'" && \
  test "$(bash -ic 'alias codex' 2>/dev/null)" = "alias codex='codex --no-daemon'" && \
  ! codex login status >/dev/null 2>&1 && \
  ! claude auth status >/dev/null 2>&1 && \
  glab --version && kubectl version --client && \
  go version && gopls version && yq --version && \
  cargo --version && rustc --version && rust-analyzer --version && \
  test -d ${HOME}/.claude/plugins/cache/claude-plugins-official/gopls-lsp && \
  test -d ${HOME}/.claude/plugins/cache/claude-plugins-official/pyright-lsp && \
  test -d ${HOME}/.claude/plugins/cache/claude-plugins-official/typescript-lsp && \
  test -d ${HOME}/.claude/plugins/cache/claude-plugins-official/rust-analyzer-lsp && \
  command -v pyright-langserver && \
  node --version && python3 --version && \
  black --version && isort --version && \
  typescript-language-server --version && pyright --version

# Exercise the shipped editor configuration and real LSP/directory-diff flows.
COPY --chown=node:node scripts/check_neovim.py /tmp/check_neovim.py
RUN test "${EDITOR}" = nvim && test "${VISUAL}" = nvim && \
  test "$(git var GIT_EDITOR)" = nvim && \
  rustfmt --version && \
  test -f "$(rustc --print sysroot)/lib/rustlib/src/rust/library/std/src/lib.rs" && \
  python3 /tmp/check_neovim.py && rm /tmp/check_neovim.py

# `kubectl exec -- herdr` must wait for the size kubectl applies after starting it.
COPY --chown=node:node scripts/check_herdr_launch.py /tmp/check_herdr_launch.py
RUN python3 /tmp/check_herdr_launch.py && rm /tmp/check_herdr_launch.py

WORKDIR /workspace

# PID 1 must reap zombies; -s keeps reaping as subreaper when pause is PID 1 (shareProcessNamespace)
ENTRYPOINT ["/usr/bin/tini", "-s", "--"]

# ENTRYPOINT clears the base image CMD, so supply the long-lived default the pod
# expects. Override it for interactive runs: `docker run -it <image> /bin/bash`.
CMD ["sleep", "infinity"]
