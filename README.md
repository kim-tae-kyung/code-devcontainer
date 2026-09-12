# Coding Agent Sandbox

A container image for AI-assisted software development, bundling the Anthropic Claude Code and OpenAI Codex CLIs with the tooling an agent needs. It is built on a Node.js/TypeScript base and is run primarily as a long-lived **Kubernetes pod** (or any local Docker/Podman container).

## Features

- **Base Image**: `mcr.microsoft.com/devcontainers/typescript-node:24` (digest-pinned)
- **Languages**: Node.js, Python 3, Go (latest), Rust (stable, minimal profile)
- **AI Tools**:
  - **Claude Code** (Anthropic) — installed via the official native installer
  - `@openai/codex` — installed via npm
- **Browser & docs servers** (pre-configured for **both** Claude Code and Codex):
  - **Playwright** — headless Chromium browser automation for UI testing/debugging in containers (both CLIs run the same pinned local MCP server)
  - **context7** — on-demand, up-to-date library/framework documentation (Claude Code uses the official plugin backed by Upstash's hosted HTTP server; Codex runs the local `npx` server)
- **Development Tools**: `git`, `gh`, `jq`, `ripgrep`, `nvim` (default editor), `vim`, `tree`, and common networking utilities. The image installs the latest stable Neovim from its [official release assets](https://github.com/neovim/neovim/releases), verifies the SHA-256 digest, and requires version 0.12 or newer. It also installs the latest stable `kubectl` for its target architecture using the [official binary and checksum](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/).
- **Terminal multiplexers**: the latest stable Herdr release as the primary workspace, with Claude Code and Codex session integrations. tmux remains installed with its default settings for optional use and demo capture.
- **LSP Support**: `gopls`, `pyright`, `typescript-language-server`, and `rust-analyzer` are connected to Neovim's native LSP client and Claude Code's official code-intelligence plugins. `pylsp` remains available as an optional Python server. TypeScript stays on the latest 6.x release for compatibility with the [language server](https://github.com/typescript-language-server/typescript-language-server#installing); Rust includes `rust-src` and `rustfmt`.
- **Demo capture** (→ GIF): `asciinema` + `agg` in a fresh isolated tmux server, plus `sharp` for browser screenshots, wired up by an explicit-only `capture-demo` skill for both CLIs.
- **Codex from Claude Code**: two model-invocable Claude Code skills, `codex` (delegate a task, review a plan, or run Codex's native code review) and `codex-imagegen` (raster images through Codex's bundled `imagegen` skill), both driving `codex exec` non-interactively — no plugin and no MCP bridge.

## Usage

### Kubernetes (primary)

Run the launcher on the Kubernetes control-plane host with `kubectl` and `jq`
available, then connect to the long-lived Pod with `kubectl exec`. The launcher
creates the Pod, waits for readiness, copies the launcher's `${HOME}/.ssh` and
`${HOME}/.gitconfig` when present, and prints the connection command
([kubectl exec](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_exec/)):

```bash
# Create pod and wait for readiness
# (optional: POD_NAME, NAMESPACE, NODE_NAME, SERVICE_ACCOUNT)
./run-k8s-daemon-example.sh

# Connect directly to Herdr
kubectl exec -it devcontainer-<timestamp> -- herdr

# Optional plain shell
kubectl exec -it devcontainer-<timestamp> -- /bin/bash
```

Add `-n NAMESPACE` to either command when using a non-default namespace.
Herdr can run directly under `kubectl exec -it`; an initial Bash session is not
required. The image exports `SHELL=/bin/bash`, so Herdr starts new interactive
panes with Bash ([Herdr terminal defaults](https://herdr.dev/docs/configuration/#terminal-defaults)).
This image default applies to newly created containers after the updated image
is published; existing Pods keep their original environment. In an existing
`sh` pane, run `exec /bin/bash` to switch that pane to Bash.

### Local container (Docker/Podman)

```bash
docker run -it --rm -v "$PWD:/workspace" ghcr.io/kim-tae-kyung/code-devcontainer:latest /bin/bash
```

### Authentication

The launcher copies the contents of `${HOME}/.ssh` into `/home/node/.ssh` in the
new Pod when the source directory exists. Copied directories use mode `700`
and regular files use mode `600`. It also copies `${HOME}/.gitconfig` to
`/home/node/.gitconfig` with mode `600`, preserving the launcher's global
[Git configuration](https://git-scm.com/docs/git-config). Each missing source
is skipped independently. If copying or permission setup fails, the launcher
exits with an error before printing the connection command.

Authenticate the GitHub CLI, Claude Code, and Codex inside the running
container.

```bash
# GitHub CLI: https://cli.github.com/manual/gh_auth_login
gh auth login

# Claude Code: open the printed URL locally and paste the login code
claude auth login

# Codex CLI: sign in from a remote/headless Pod
codex login --device-auth
```

For Claude Code, follow the [container login flow](https://code.claude.com/docs/en/troubleshoot-install#oauth-login-fails-in-wsl2-ssh-or-containers).
For Codex, enable device-code login for your account or workspace and follow
[headless authentication](https://learn.chatgpt.com/docs/auth#login-on-headless-devices).
The Pod's `SERVICE_ACCOUNT` selects an existing Kubernetes ServiceAccount;
its API permissions come from your cluster's RBAC, not from the launcher's
host credentials ([ServiceAccounts](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/)).

### Terminal sessions (Herdr)

Use Herdr for interactive work. Start it directly through the Kubernetes
connection above, or run it from a shell after connecting over SSH or entering
a local container. Keep tmux and Herdr in separate connections so their default
`Ctrl-b` prefixes do not conflict.

```bash
# From a shell inside the server or container
herdr

# Optional tmux session, using its default settings
tmux
```

Herdr starts or reattaches to its background session. Press `Ctrl-b q` to
detach without stopping panes. Repeat `kubectl exec -it POD_NAME -- herdr` to
reattach, or run `herdr` again from a shell. The background server keeps pane
processes running while the container stays alive. Stopping or replacing the
container ends those processes; restoring a saved layout or agent conversation
requires the corresponding state files to survive
([Herdr session state](https://herdr.dev/docs/session-state/)). Use
`herdr server stop` to terminate the session and its pane processes. Direct
installs track the stable channel and can be refreshed in a running container
with `herdr update`.

The image installs Herdr's official Claude Code and Codex integrations for
native agent-session restoration. It also installs the latest official `herdr`
skill from the upstream `master` branch for both agents
([official skill source](https://github.com/herdrdev/herdr/blob/master/skills/herdr/SKILL.md)).
The skill activates only when Herdr is explicitly requested and the agent is
running in a Herdr-managed pane (`HERDR_ENV=1`).

The skill tracks upstream independently of the Herdr binary. Version skew is
intentional; use the installed `herdr --help` to check available commands.
Remote `ADD` makes source changes invalidate the skill installation layer even
when earlier build layers are cached ([Docker cache rules](https://docs.docker.com/build/cache/invalidation/)).
A failed download, empty file, or missing expected skill header stops the build
instead of falling back to the binary's bundled copy.

To install or refresh the same official skill on a local machine with Herdr
installed, run:

```bash
(
  set -eu
  herdr_skill=$(mktemp)
  trap 'rm -f "$herdr_skill"' EXIT
  curl -fsSL https://raw.githubusercontent.com/herdrdev/herdr/master/skills/herdr/SKILL.md -o "$herdr_skill"
  test -s "$herdr_skill"
  test "$(head -n 1 "$herdr_skill")" = '---'
  grep -q '^name: herdr$' "$herdr_skill"
  for skill_root in "$HOME/.claude/skills" "$HOME/.agents/skills"; do
    install -d "$skill_root/herdr"
    install -m 0644 "$herdr_skill" "$skill_root/herdr/SKILL.md"
    cmp "$herdr_skill" "$skill_root/herdr/SKILL.md"
  done
  herdr integration install claude
  herdr integration install codex
  herdr integration status
)
```

Rerun this procedure to refresh local skills and integrations; it does not
install an automatic updater. The user-level locations make the skill
available across projects in [Claude Code](https://code.claude.com/docs/en/skills#choose-where-skills-load)
and [Codex](https://learn.chatgpt.com/docs/build-skills#where-codex-loads-local-skills).

### Editing and Git diff (Neovim)

Open `nvim` in a Herdr pane. The image sets `EDITOR`, `VISUAL`, and Git's system
`core.editor` to `nvim`; explicit user Git configuration takes precedence.
Vim and its existing `.vimrc` remain available. Neovim uses its own defaults
for indentation, colors, recovery files, and editing keys, with only native
DiffTool and LSP configuration added.

```bash
nvim path/to/file
git status --short           # Complete Git change inventory
git ndiff                    # Unstaged changes to tracked files
git ndiff --cached            # Staged changes
git ndiff HEAD -- path/to/dir  # Compare a revision, restricted to a path
```

`git ndiff` launches the optional built-in
[DiffTool](https://neovim.io/doc/user/plugins/#difftool) through
[`git difftool --dir-diff`](https://git-scm.com/docs/git-difftool), using a
command-scoped tool definition. It leaves the copied `~/.gitconfig` and other
diff-tool settings intact. Use `:cnext` / `:cprevious` to move through the
changed-file list, `]c` / `[c` for differences within a file, `Ctrl-w w` to
switch windows, and `:qa` to quit.

This is an editable content comparison, not a staging interface. Saving a
worktree-backed buffer can change the working file, including in a staged
comparison; it does not stage the edit. Untracked files are excluded until
Git includes them in a diff. Empty-file additions/deletions and permission-only
changes may be absent from the content comparison, so use `git status` for the
complete inventory. GNU diff is installed for the built-in directory comparator
([DiffTool implementation](https://github.com/neovim/neovim/blob/v0.12.5/runtime/pack/dist/opt/nvim.difftool/lua/difftool.lua)).

### Code navigation and completion (LSP)

Neovim connects to the pre-installed servers when a matching code file opens.
It uses [`vim.lsp.config()` and `vim.lsp.enable()`](https://neovim.io/doc/user/lsp/#lsp-quickstart),
without a plugin manager or additional Neovim plugins. Neovim and Claude Code
share the installed executables, with separate server processes per client.

| Language | Server | Project root |
| --- | --- | --- |
| Go | `gopls` | `go.work`, then `go.mod`, then `.git` |
| Python | `pyright-langserver --stdio` | Pyright/Python project configuration, then `.git` |
| JavaScript, TypeScript, JSX, TSX | `typescript-language-server --stdio` | Nearest `tsconfig.json`, `jsconfig.json`, or `package.json`, then `.git` |
| Rust | `rust-analyzer` | Cargo workspace, or `rust-project.json` / `.git` |

Python uses only Pyright in Neovim, avoiding duplicate diagnostics from `pylsp`.
Project configuration controls analysis and dependency resolution; activate a
Python virtual environment before starting Neovim when appropriate. Rust
standard-library sources are installed at build time for navigation
([rust-analyzer setup](https://rust-analyzer.github.io/book/installation.html)).

Use Neovim's [native LSP keys](https://neovim.io/doc/user/lsp/#lsp-defaults):

| Action | Key / command |
| --- | --- |
| Definition / return | `Ctrl-]` / `Ctrl-t` |
| Hover documentation | `K` |
| References / rename / code action | `grr` / `grn` / `gra` |
| Next / previous diagnostic | `]d` / `[d` |
| Request completion | `Ctrl-x Ctrl-o` in Insert mode |
| Next / previous completion candidate | `Ctrl-n` / `Ctrl-p` |
| Accept / dismiss completion | `Ctrl-y` / `Ctrl-e` |
| Inspect server connections | `:checkhealth vim.lsp` |

The native completion menu also opens on server-defined trigger characters,
with no candidate selected automatically. Features depend on the server's
capabilities. Formatting is manual (`gq` or `:lua vim.lsp.buf.format()` when
supported); Python formatting remains available through the installed `black`
CLI. Saving does not run custom format or import-organizing hooks. LSP does
not auto-start in sessions launched with `nvim -d`, including `git ndiff`.

### The same editor setup on macOS

Use native macOS tools instead of the image's Linux binaries. Install
[Neovim](https://formulae.brew.sh/formula/neovim) and
[GNU diff](https://formulae.brew.sh/formula/diffutils) with Homebrew, and reuse
or install the language servers:

```bash
brew install neovim diffutils
npm install -g pyright typescript@6 typescript-language-server
go install golang.org/x/tools/gopls@latest
```

For Rust, use [rustup](https://rust-lang.github.io/rustup/installation/index.html)
with a stable toolchain and the same components as the image:

```bash
rustup toolchain install stable --profile minimal \
  --component rust-analyzer --component rust-src --component rustfmt
```

From this repository, install the shared configuration and Git helper. These
commands replace the corresponding local files:

```bash
install -d "$HOME/.config/nvim" "$HOME/.local/bin"
install -m 0644 nvim/init.lua "$HOME/.config/nvim/init.lua"
install -m 0755 scripts/git-ndiff "$HOME/.local/bin/git-ndiff"
git config --global core.editor nvim
```

Keep zsh as the macOS shell. Set `EDITOR=nvim` and `VISUAL=nvim` in the shell
startup configuration, and put `~/.cargo/bin`, Go's `bin` directory, and
`~/.local/bin` on `PATH`. Keep `~/.cargo/bin` ahead of a standalone Homebrew
`rust-analyzer` so the server matches the rustup toolchain. Homebrew's `bin`
directory should precede `/usr/bin` so Neovim uses GNU diff. Apply these settings
to both login and interactive shells, then open a new terminal or Herdr pane.

Check `command -v nvim git-ndiff gopls pyright-langserver typescript-language-server
rust-analyzer`, `diff --version`, and `git var GIT_EDITOR`. Run the same real
LSP and diff checks locally with `python3 scripts/check_neovim.py`.

### Browser Automation (Playwright MCP)

Headless Chromium is pre-installed for browser automation via the Playwright MCP server. Both Claude Code and Codex are pre-configured with the same pinned MCP registration, enabling the agent to navigate pages, take screenshots, click elements, and read console logs — all from within the pod/container.

```bash
# Start your dev server
npm run dev  # e.g. Vite on localhost:5173

# In Claude Code or Codex, ask:
# "Navigate to http://localhost:5173 and take a screenshot"
# "Check for console errors on the page"
# "Click the submit button and verify the result"
```

### Capturing demos (GIF)

The `capture-demo` skill turns browser flows or isolated terminal sessions into
task-specific screenshots or an **animated GIF** for docs, PRs, or issues. A
browser capture starts with an evidence contract for the target artifact, waits
for stable application state, reproduces the documented interaction, and
verifies the final frame. Creation and destructive flows stop at the final
confirmation boundary unless the request explicitly authorizes submission.
Every terminal recording creates a private tmux socket and a fresh session,
then removes that server when recording ends.

The skill is user-invocable only. Call it explicitly as `$capture-demo` in
Codex or `/capture-demo` in Claude Code; ordinary recording-related language
does not activate it.

```bash
# Command -> fresh isolated tmux session -> GIF (asciinema + agg)
~/.claude/skills/capture-demo/terminal_capture.sh -o demo.gif -c "npm test; sleep 1"

# Interactive fresh tmux session -> GIF; type exit to finish
~/.claude/skills/capture-demo/terminal_capture.sh -o demo.gif --interactive --duration 60

# Browser flow -> GIF: capture context, interaction, and proved end state as
# frames/001.png, frames/002.png, ... then assemble (sharp, no ffmpeg):
node ~/.claude/skills/capture-demo/frames_to_gif.mjs frames/ --out demo.gif --delay 900 --width 1000
```

Generic page-open images are not accepted as evidence for distinct procedures.
Existing outputs are not overwritten unless `--force` is supplied.

### Delegating to Codex from Claude Code

Two user-level skills let a Claude Code session hand work to the Codex CLI in
the same pod through [`codex exec`](https://learn.chatgpt.com/docs/non-interactive-mode).
Claude invokes them from ordinary language ("ask codex", "codex한테 이 plan
리뷰 시켜줘", "imagegen으로 인포그래픽 만들어줘"); `/codex` and
`/codex-imagegen` also work.

- `codex` — delegate a task or question (told not to modify files unless the
  user asks Codex to edit), review a plan in plan mode (Codex reads the plan
  file by path and prints a report), or run Codex's native code review with
  `codex exec ... review --uncommitted`, `--base <branch>`, or
  `--commit <sha>`; a custom review prompt is its own target and cannot be
  combined with those flags. Codex's reply is returned verbatim, followed by
  a short assessment.
- `codex-imagegen` — generate or edit PNGs through Codex's bundled `imagegen`
  skill ([image generation](https://learn.chatgpt.com/docs/image-generation):
  built-in `image_gen` tool, `gpt-image-2`, ChatGPT login, no
  `OPENAI_API_KEY`). The skill names an absolute destination inside the
  project, Codex copies the result there from `$CODEX_HOME/generated_images/`,
  and the skill checks the PNG header and views the image before reporting
  the path and dimensions.

Every call passes `--ephemeral` and `--skip-git-repo-check`, and inherits the
configured `danger-full-access` policy described under
[Security model](#security-model), without adding `-s`
([Codex execution options](https://learn.chatgpt.com/docs/non-interactive-mode)).
Codex needs its own login in the Pod; check it with `codex login status`
([authentication](https://learn.chatgpt.com/docs/auth)).

Claude Code's default bypass mode applies to these calls; no custom approval
hook or prompt-character filter is installed
([permission modes](https://code.claude.com/docs/en/permission-modes#skip-all-checks-with-bypasspermissions-mode)).
Review-only requests remain read-only by instruction. When the original request
includes implementation, Claude can apply relevant findings without a second
approval. Recoverable failures get one retry, with partial edits checked first.

## Security model

This image is intended for trusted IaaS development, including administration
of clusters where the operator supplies broad permissions. Network isolation
is not an assumption or a control provided by this repository.

- **Codex** uses `approval_policy = "never"` and `sandbox_mode = "danger-full-access"`
  ([Codex permissions](https://developers.openai.com/codex/agent-approvals-security)).
- **Claude Code** starts in `bypassPermissions`, with no custom approval hooks.
  Its built-in exceptions still apply; this setting does not promise that every
  possible prompt disappears
  ([Claude permission modes](https://code.claude.com/docs/en/permission-modes#skip-all-checks-with-bypasspermissions-mode)).
- **Playwright** receives `--no-sandbox` in both MCP registrations
  ([server options](https://github.com/microsoft/playwright-mcp#configuration)).

The CLIs run as `node`. Kubernetes API authority depends on the Pod's selected
ServiceAccount and cluster RBAC. The launcher retains token-mount defaults and
does not create roles or bindings
([ServiceAccounts](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/)).
Shared instructions define task scope, preserve review-only behavior, and
require clarification for unapproved destructive actions. They do not create
an operating-system or cluster security boundary.

## Configuration

Files baked into the image at build time:

- `claude-settings.json` → `~/.claude/settings.json` (Claude Code permissions/behavior)
- `codex-config.toml` → `~/.codex/config.toml` (Codex model, sandbox, MCP servers)
- `operating-principles.md` → `~/.claude/CLAUDE.md` **and** `~/.codex/AGENTS.md` (global agent instructions)
- `herdr-config.toml` → `~/.config/herdr/config.toml`
- `vimrc` → `~/.vimrc`
- `nvim/init.lua` → `~/.config/nvim/init.lua` (native DiffTool and LSP)
- `.claude/skills/` → `~/.claude/skills/` (Claude Code skills: `capture-demo`, `codex`, `codex-imagegen`)
- `.agents/skills/` → `~/.agents/skills/` (Codex skill: `capture-demo`)

The build also installs Herdr's generated Claude Code and Codex hooks, and
writes the latest upstream `herdr` skill to both user-level skill directories.

Herdr has four explicit settings: skip onboarding (`onboarding = false`), show
agent labels on pane borders (`ui.show_agent_labels_on_pane_borders = true`),
use distinct status symbols (`ui.status_indicators = "symbols"`), and send
notifications through the connected terminal (`ui.toast.delivery = "terminal"`).
Keys, theme, and other settings use upstream defaults. Herdr's shell setting
also remains at its upstream default, which reads the image's `SHELL=/bin/bash`
environment variable ([Herdr configuration](https://herdr.dev/docs/configuration/)).
No custom tmux configuration is baked into the image.

Claude Code gets context7 and language intelligence from official marketplace
plugins. Playwright uses a user-scoped registration in `~/.claude.json`, created
at build time, so it is available in every project
([MCP scope](https://code.claude.com/docs/en/mcp#user-scope)). Both agents use
`PLAYWRIGHT_MCP_VERSION`; `codex-config.toml` mirrors that pin and Renovate
updates the two source locations together. CI checks the source pin, and the
image build checks both installed registrations. The Chromium revision comes
from the pinned server's Playwright dependency
([Playwright browsers](https://playwright.dev/docs/browsers)).

`headless_shell` on `PATH` points to the installed Chromium headless shell
([Playwright headless shell](https://playwright.dev/docs/browsers#chromium-headless-shell)).
The working directory is `/workspace`.

### Models, effort, and operating instructions

Neither CLI pins a model. Select a model for the current task with `/model`
([Codex commands](https://learn.chatgpt.com/docs/developer-commands),
[Claude model configuration](https://code.claude.com/docs/en/model-config)).
Codex sets `plan_mode_reasoning_effort = "xhigh"`; ordinary Codex turns and
Claude Code sessions leave effort unspecified
([Codex configuration](https://learn.chatgpt.com/docs/config-file/config-reference),
[Claude effort](https://code.claude.com/docs/en/model-config#adjust-effort-level)).

The shared operating principles stay under 200 words. They define language,
authorized scope, execution, documentation, and communication; this README
holds the model-specific rationale:

- For GPT-6 Astra, the instructions reuse prior authorization, resolve routine
  choices, explain skill blockers, delegate bounded tasks, and limit repeated
  verification to new evidence
  ([Astra prompting guidance](https://developers.openai.com/api/docs/guides/latest-model?model=gpt-6-astra#prompting-best-practices)).
- For Claude Fable 5.1, the instructions require task completion, targeted
  edits, proportional tests, independent tool-call batching, brief progress
  updates, and preservation of goals and unfinished work across compaction
  ([Fable 5.1 prompting guidance](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1)).

Review-only requests produce findings without edits. Durable documentation
uses official sources and describes current behavior. Replies use concise,
plain language, with lists or tables when helpful.

Codex memory generation and injection are disabled, and `history.persistence`
is `none`; this setting controls `history.jsonl`, not all session storage
([Codex configuration](https://learn.chatgpt.com/docs/config-file/config-reference)).
Claude auto memory is disabled and `cleanupPeriodDays` is `3`
([Claude settings](https://code.claude.com/docs/en/settings)). Persistent
instructions belong in `operating-principles.md`.

The release build refreshes the unpinned CLI installers and latest stable
kubectl. Inspect installed versions in the build log or with each CLI's version
command. kubectl follows upstream stable rather than a cluster-specific pin;
check its [supported version skew](https://kubernetes.io/releases/version-skew-policy/#kubectl)
when connecting to an older cluster.

### Terminal integration

The primary connection path is `terminal → kubectl exec -it → Herdr → CLI`.
Herdr's local background server owns its workspaces, tabs, panes, and agent
terminals. This connection requires no Kubernetes Service or inbound port.

Both CLIs retain their main-screen settings: Claude Code uses
`"tui": "default"`, and Codex uses `[tui] alternate_screen = "never"`
([Codex alternate-screen behavior](https://github.com/openai/codex/pull/8555)).

The pod explicitly selects Claude Code's `"ghostty"` notification channel and Codex's OSC 9 TUI notifications instead of relying on terminal auto-detection across the remote boundary. Claude Code emits native task-complete and input-needed notifications; Codex enables all supported TUI notification events and emits them regardless of terminal focus ([Claude terminal notifications](https://code.claude.com/docs/en/terminal-config#get-a-terminal-bell-or-notification), [Codex notifications](https://learn.chatgpt.com/docs/config-file/config-advanced#notifications)).

Herdr separately sends background-agent notifications to the outer terminal
with `ui.toast.delivery = "terminal"`; it suppresses its popups for the active
tab. Actual desktop display depends on terminal support and notification
permissions ([Herdr notifications](https://herdr.dev/docs/configuration/#notifications)).
For Ghostty on macOS, enable notification permission and
`desktop-notifications = true`
([Ghostty option reference](https://ghostty.org/docs/config/reference#desktop-notifications)).

Herdr also needs to identify the outer terminal before emitting a notification.
If plain `kubectl exec` does not expose that identity, Ghostty users can pass it
for the connection explicitly
([Herdr terminal detection](https://github.com/herdrdev/herdr/blob/v0.9.0/src/terminal_notify.rs)):

```bash
kubectl exec -it POD_NAME -- env TERM_PROGRAM=ghostty herdr
```

Claude Remote Control is enabled for every interactive session in the baked-in settings, along with its native mobile push options. It requires a `claude.ai` login inside the running pod and outbound HTTPS access; credentials are deliberately not baked into the image. Remote Control makes outbound connections and does not require an inbound Kubernetes Service.

ChatGPT Remote does not attach directly to an arbitrary Codex CLI process reached through `kubectl exec`. For this workflow, Codex alerts use the built-in terminal notification path to Ghostty; connecting a Codex environment to ChatGPT Remote requires a supported desktop or SSH host.

## Build & Push

### Continuous integration

`ci.yml` runs on every pull request and on pushes to `main`. It validates `claude-settings.json` against the [published settings schema](https://json.schemastore.org/claude-code-settings.json) and additionally compares key sets, because the schema allows additional properties and would otherwise accept keys Claude Code does not implement. It also parses `codex-config.toml` and `herdr-config.toml`, checks the Playwright pin and flags, and runs focused launcher and browser-pin tests. Pull requests additionally build `linux/amd64`, which runs the Dockerfile smoke test.

The image build also runs `scripts/check_neovim.py`: real language-server
connections and navigation/diagnostics for all four languages, plus Git diff
fixtures covering staged and unstaged changes, path filtering, file additions
and deletions, and editing without staging. These checks run as `node` using
the configuration shipped in the image.

Renovate runs weekly on Monday and automerges minor, patch, and digest updates. It delegates the merge to GitHub via [`platformAutomerge`](https://docs.renovatebot.com/configuration-options/#platformautomerge) so a PR lands as soon as it is mergeable, instead of waiting a full week for the next Renovate run to merge it. The active [`main` repository ruleset](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets) requires `validate-config` and `build`, so GitHub merges Renovate PRs only after both CI jobs pass against the current branch tip. The ruleset lists the Repository admin role in its [bypass list](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/creating-rulesets-for-a-repository#granting-bypass-permissions-for-your-ruleset), so the maintainer can push to `main` directly; Renovate's PRs stay behind the required checks.

### Via GitHub Actions

Container images are built and pushed via GitHub Actions every Monday at 06:00 KST, refreshing unpinned tools without the build cache and using the base-image digest tracked by Renovate. Each architecture builds on its own native runner — `linux/amd64` on `ubuntu-latest`, `linux/arm64` on `ubuntu-24.04-arm` — and a merge job joins the two digests into the `:latest` manifest, then prunes the GHCR package back to it. Emulating arm64 under QEMU is not an option here; see `AGENTS.md`. To build off-schedule:

1. Go to the **Actions** tab in the repository
2. Select **Build and Push Container Image** workflow
3. Click **Run workflow**

### Local Build (Podman)

Run the smoke test on a native arm64 host:

```bash
podman build --platform linux/arm64 -t code-devcontainer:local .
```

Use `linux/amd64` on a native amd64 host. Publish the combined image through
the release workflow so each architecture runs its Chromium check natively.
For a local refresh of unpinned tools, add `--no-cache`
([Podman build options](https://docs.podman.io/en/latest/markdown/podman-build.1.html)).
