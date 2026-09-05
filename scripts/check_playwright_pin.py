#!/usr/bin/env python3
"""Check that agent registrations use the image's Playwright MCP pin and flags."""

import argparse
import json
from pathlib import Path
import re
import sys
import tomllib


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dockerfile", type=Path, default=Path("Dockerfile"))
    parser.add_argument("--expected-version")
    parser.add_argument("--codex-config", type=Path, default=Path("codex-config.toml"))
    parser.add_argument("--claude-config", type=Path)
    args = parser.parse_args()
    version = args.expected_version
    if version is None:
        pins = re.findall(r"^ARG PLAYWRIGHT_MCP_VERSION=(\S+)$", args.dockerfile.read_text(), re.M)
        if len(pins) != 1:
            raise ValueError("Dockerfile must declare exactly one Playwright MCP pin")
        version = pins[0]
    expected = ["-y", f"@playwright/mcp@{version}", "--headless", "--browser=chromium", "--no-sandbox"]
    codex = tomllib.loads(args.codex_config.read_text())["mcp_servers"]["playwright"]
    registrations = [("Codex", codex)]
    if args.claude_config is not None:
        claude = json.loads(args.claude_config.read_text())["mcpServers"]["playwright"]
        registrations.append(("Claude Code", claude))
    for name, config in registrations:
        if config.get("command") != "npx" or config.get("args") != expected:
            raise ValueError(f"{name} Playwright registration must use npx {expected!r}")
    print(f"Playwright MCP {version}: {', '.join(name for name, _ in registrations)} matched")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError) as error:
        sys.exit(str(error))
