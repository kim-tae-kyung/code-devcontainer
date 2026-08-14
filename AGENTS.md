# Repository Notes

Maintenance context for this build repository. Nothing here ships in the image;
the image carries `operating-principles.md`.

## Check the Playwright MCP pin while you are here

`@playwright/mcp` loads only the Chromium revision its `playwright` core was
built against, and the image bakes one revision. Two places name the server
version and must stay equal:

- `PLAYWRIGHT_MCP_VERSION` in the `Dockerfile`, which also derives the Chromium
  install from that version's `playwright` core
- the `mcp_servers.playwright` args in `codex-config.toml`

Renovate raises both together. When you open this repository for any task, spend
a moment confirming the pin is still current and the two agree:

```bash
npm view @playwright/mcp version                               # newest release
grep -n 'PLAYWRIGHT_MCP_VERSION=' Dockerfile
grep -n '@playwright/mcp@' codex-config.toml
```

If a newer release exists, raise both and let CI rebuild — the Chromium install
follows the pin, so nothing else needs changing. If the two files disagree, the
pod runs one server version against a browser built for another, and browser
automation fails with `Executable doesn't exist at .../chromium_headless_shell-<rev>`.

The build launches Chromium once and fails if it cannot, so a mismatch cannot
reach a published image. That check runs on `linux/amd64` in CI; `linux/arm64` is
only exercised by the release build, after automerge — so a Playwright bump can
be merged before anything has run it on arm64.

The release build gives each architecture its own native runner
(`ubuntu-latest` and `ubuntu-24.04-arm`) and joins the two digests into one
manifest. Do not fold it back into a single QEMU job: the launch check starts
the headless shell, whose GPU process cannot start under emulation
(`GPU process launch failed: error_code=1002`), and it fails there regardless of
whether the pin is correct.

`@upstash/context7-mcp` (Codex only; Claude Code gets context7 via the official
plugin, which talks to Upstash's hosted HTTP server) tracks `@latest` and needs
no such check: it fetches documentation over HTTP and is not coupled to anything
in the image.
