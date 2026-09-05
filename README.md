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
- **Development Tools**: `git`, `gh`, `jq`, `ripgrep`, `vim`, `tree`, and common networking utilities. The image also installs the latest stable `kubectl` for its target architecture using the [official binary and checksum](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/).
- **Terminal multiplexers**: tmux 3.5+ for the existing workflow, plus the latest stable Herdr release with Claude Code and Codex session integrations.
- **LSP Support**: `gopls`, `pylsp`, `pyright`, `typescript-language-server`, `rust-analyzer` — enabled by default in Claude Code via the official code-intelligence plugins (`gopls-lsp`, `pyright-lsp`, `typescript-lsp`, `rust-analyzer-lsp`), pre-installed at build time
- **Demo capture** (→ GIF): `asciinema` + `agg` in a fresh isolated tmux server, plus `sharp` for browser screenshots, wired up by an explicit-only `capture-demo` skill for both CLIs.
- **Documentation workflow**: the `docs-visual` skill is installed globally for Codex to research, write, audit, visualize, and validate technical documentation.
- **Codex from Claude Code**: two model-invocable Claude Code skills, `codex` (delegate a task, review a plan, or run Codex's native code review) and `codex-imagegen` (raster images through Codex's bundled `imagegen` skill), both driving `codex exec` non-interactively — no plugin and no MCP bridge.

## Usage

### Kubernetes (primary)

Run the launcher on the Kubernetes control-plane host with `kubectl` and `jq`
available, then connect to the long-lived Pod with `kubectl exec`. The launcher
creates the Pod, waits for readiness, and prints the connection command
([kubectl exec](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_exec/)):

```bash
# Create pod and wait for readiness
# (optional: POD_NAME, NAMESPACE, NODE_NAME, SERVICE_ACCOUNT)
./run-k8s-daemon-example.sh

# Connect
kubectl exec -it devcontainer-<timestamp> -- /bin/bash
```

### Local container (Docker/Podman)

```bash
docker run -it --rm -v "$PWD:/workspace" ghcr.io/kim-tae-kyung/code-devcontainer:latest /bin/bash
```

### Authentication

Authenticate inside the running container. The launcher does not read or copy
host credentials or Git configuration. Set Git identity inside the Pod when
needed ([Git configuration](https://git-scm.com/docs/git-config)).

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

### Terminal sessions (tmux and Herdr)

tmux remains available unchanged. Herdr is an opt-in alternative; start it from
a separate `kubectl exec` connection instead of nesting it inside tmux, so both
multiplexers can keep their default `Ctrl-b` prefix.

```bash
# Existing workflow
tmux

# Herdr alternative, from a fresh shell in the project you want to manage
cd /workspace/my-project
herdr
```

Herdr starts or reattaches to its background session. Press `Ctrl-b q` to
detach without stopping panes, run `herdr` again to reattach, and use
`herdr server stop` when you intend to terminate the session and its pane
processes. Direct installs track the stable channel and can be refreshed in a
running container with `herdr update`.

The image installs Herdr's official Claude Code and Codex integrations for
native agent-session restoration. It also installs the release-matched `herdr`
skill for both agents; the skill activates only when Herdr is explicitly
requested and the agent is running in a Herdr-managed pane (`HERDR_ENV=1`).

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

### Technical documentation

Codex discovers `docs-visual` from `~/.agents/skills/docs-visual`. Like
`capture-demo`, it is user-invocable only: call it explicitly as `$docs-visual`.
Asking for a documentation audit or rewrite in ordinary language does not
activate it, because the skill sets `allow_implicit_invocation: false`.

The skill adds only what the global operating principles do not already state:
pinned primary evidence for repository behavior, and the **Known Issue** callout
format.

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
- `tmux.conf` → `~/.tmux.conf`
- `vimrc` → `~/.vimrc`
- `.claude/skills/` → `~/.claude/skills/` (Claude Code skills: `capture-demo`, `codex`, `codex-imagegen`)
- `.agents/skills/` → `~/.agents/skills/` (Codex skills, e.g. `capture-demo`, `docs-visual`)

The build also installs Herdr's generated Claude Code and Codex hooks, and
writes the release-matched `herdr` skill to both user-level skill directories.

Claude Code gets context7 and language intelligence from official marketplace
plugins. Playwright uses a user-scoped registration in `~/.claude.json`, created
at build time, so it is available in every project
([MCP scope](https://code.claude.com/docs/en/mcp#user-scope)). Both agents use
`PLAYWRIGHT_MCP_VERSION`; `codex-config.toml` mirrors that pin and Renovate
updates the two source locations together. CI checks the source pin, and the
image build checks both installed registrations. The Chromium revision comes
from the pinned server's Playwright dependency
([Playwright browsers](https://playwright.dev/docs/browsers)).

`headless_shell` on `PATH` points to that browser for the bundled Mermaid
renderer. Documentation directory scans skip `.git`, `node_modules`, `.venv`,
and `__pycache__`; explicitly selected files or roots are still inspected.
The working directory is `/workspace`.

### Models, effort, and operating instructions

Neither CLI pins a model. Select a model for the current task with `/model`
([Codex commands](https://learn.chatgpt.com/docs/developer-commands),
[Claude model configuration](https://code.claude.com/docs/en/model-config)).
Codex sets `plan_mode_reasoning_effort = "xhigh"`; ordinary Codex turns and
Claude Code sessions leave effort unspecified
([Codex configuration](https://learn.chatgpt.com/docs/config-file/config-reference),
[Claude effort](https://code.claude.com/docs/en/model-config#adjust-effort-level)).

The shared operating principles support Astra and Claude Fable 5.1 workflows:
finish authorized work, resolve routine choices, reuse prior authorization,
delegate independent tasks, give brief progress updates, and keep testing
proportional to the change. Review-only requests produce findings without
edits. These policies follow the models' guidance on autonomy, delegation,
completion, and validation
([Astra guidance](https://developers.openai.com/api/docs/guides/latest-model),
[Fable 5.1 guidance](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1)).

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

### Terminal integration (tmux and Herdr)

The image provides tmux 3.5+ with extended keys, CSI u, escape-sequence passthrough, true color, and OSC 52 clipboard forwarding. These settings preserve Shift+Enter and built-in agent notifications through the normal `Ghostty → kubectl exec -it → pod tmux → CLI` path.

Both CLIs render on the terminal's main screen — no alternate screen — so their output stays in tmux scrollback (`history-limit 100000`): Claude Code via `"tui": "default"`, Codex via `[tui] alternate_screen = "never"` (alt-screen bypasses tmux history; see [openai/codex#8555](https://github.com/openai/codex/pull/8555)).

The pod explicitly selects Claude Code's `"ghostty"` notification channel and Codex's OSC 9 TUI notifications instead of relying on terminal auto-detection across the remote boundary. Claude Code emits native task-complete and input-needed notifications; Codex enables all supported TUI notification events and emits them regardless of terminal focus ([Claude terminal notifications](https://code.claude.com/docs/en/terminal-config#get-a-terminal-bell-or-notification), [Codex notifications](https://learn.chatgpt.com/docs/config-file/config-advanced#notifications)).

The pod's `tmux.conf` enables escape-sequence passthrough so notifications and progress updates return over the interactive Kubernetes TTY to Ghostty ([Claude tmux configuration](https://code.claude.com/docs/en/terminal-config#configure-tmux)). On the host, Ghostty must have macOS notification permission and `desktop-notifications = true` ([Ghostty option reference](https://ghostty.org/docs/config/reference#desktop-notifications)).

Herdr runs alongside tmux without changing `tmux.conf` or the container entrypoint.
Launch it directly from a separate interactive connection; its local background
server then owns the workspaces, tabs, panes, and agent terminals for that Herdr
session. No Kubernetes Service or inbound port is required.

Claude Remote Control is enabled for every interactive session in the baked-in settings, along with its native mobile push options. It requires a `claude.ai` login inside the running pod and outbound HTTPS access; credentials are deliberately not baked into the image. Remote Control makes outbound connections and does not require an inbound Kubernetes Service.

ChatGPT Remote does not attach directly to an arbitrary Codex CLI process reached through `kubectl exec`. For this workflow, Codex alerts use the built-in terminal notification path to Ghostty; connecting a Codex environment to ChatGPT Remote requires a supported desktop or SSH host.

## Build & Push

### Continuous integration

`ci.yml` runs on every pull request and on pushes to `main`. It validates `claude-settings.json` against the [published settings schema](https://json.schemastore.org/claude-code-settings.json) and additionally compares key sets, because the schema allows additional properties and would otherwise accept keys Claude Code does not implement. It also parses `codex-config.toml`, checks the Playwright pin and flags, and runs focused launcher and documentation-scope tests. Pull requests additionally build `linux/amd64`, which runs the Dockerfile smoke test.

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
