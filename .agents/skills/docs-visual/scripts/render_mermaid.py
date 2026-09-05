#!/usr/bin/env python3
"""Render selected Mermaid fences with a pinned CLI and build a contact sheet."""

from __future__ import annotations

import argparse
import base64
import html
import json
import math
import os
import re
import struct
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path


MERMAID_CLI_PACKAGE = "@mermaid-js/mermaid-cli@11.16.0"
MERMAID_CLI_VERSION = "11.16.0"
MARKDOWN_EXTENSIONS = {".md", ".mdx", ".markdown"}
IGNORED_DIRECTORIES = {".git", "node_modules", ".venv", "__pycache__"}
FENCE_PATTERN = re.compile(r"^[ \t]{0,3}(`{3,}|~{3,})(.*)$")


@dataclass(frozen=True)
class MermaidBlock:
    source: Path
    line: int
    definition: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Extract selected Mermaid fences, render them with "
            f"{MERMAID_CLI_PACKAGE}, and create a contact sheet."
        )
    )
    parser.add_argument("targets", nargs="+", type=Path)
    browser = parser.add_mutually_exclusive_group()
    browser.add_argument(
        "--browser-executable",
        type=Path,
        help="Absolute path to Chromium, Chrome, or headless_shell.",
    )
    browser.add_argument(
        "--puppeteer-config",
        type=Path,
        help=(
            "Puppeteer JSON with an absolute executablePath. A browser option "
            "is required only when the selected scope contains Mermaid."
        ),
    )
    parser.add_argument(
        "--mermaid-config",
        type=Path,
        help="Repository-owned Mermaid JSON configuration.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        help="New or empty output directory; defaults to /tmp.",
    )
    return parser.parse_args()


def markdown_files(targets: list[Path]) -> list[Path]:
    files: set[Path] = set()
    for target in targets:
        resolved = target.resolve()
        if resolved.is_file():
            if resolved.suffix.lower() not in MARKDOWN_EXTENSIONS:
                raise RuntimeError(f"not a Markdown target: {target}")
            files.add(resolved)
        elif resolved.is_dir():
            for directory, subdirs, names in os.walk(resolved):
                subdirs[:] = [name for name in subdirs if name not in IGNORED_DIRECTORIES]
                files.update(
                    (Path(directory) / name).resolve()
                    for name in names
                    if Path(name).suffix.lower() in MARKDOWN_EXTENSIONS
                )
        else:
            raise RuntimeError(f"target does not exist: {target}")
    return sorted(files)


def mermaid_blocks(path: Path) -> list[MermaidBlock]:
    content = path.read_text(encoding="utf-8")
    blocks: list[MermaidBlock] = []
    marker: str | None = None
    marker_length = 0
    opening_line = 0
    definition: list[str] = []

    for line_number, line in enumerate(content.splitlines(), 1):
        if marker is not None:
            closing = re.match(
                rf"^[ \t]{{0,3}}{re.escape(marker)}{{{marker_length},}}[ \t]*$",
                line,
            )
            if closing:
                blocks.append(
                    MermaidBlock(
                        source=path,
                        line=opening_line,
                        definition="\n".join(definition) + "\n",
                    )
                )
                marker = None
                definition = []
            else:
                definition.append(line)
            continue

        match = FENCE_PATTERN.match(line)
        if not match:
            continue
        info = match.group(2).strip().split(maxsplit=1)
        if info and info[0].casefold() == "mermaid":
            fence = match.group(1)
            marker = fence[0]
            marker_length = len(fence)
            opening_line = line_number

    if marker is not None:
        raise RuntimeError(f"{path}:{opening_line}: unclosed Mermaid fence")
    return blocks


def prepare_output(path: Path | None) -> Path:
    if path is None:
        return Path(tempfile.mkdtemp(prefix="docs-visual-mermaid.", dir="/tmp"))
    resolved = path.resolve()
    if resolved.exists():
        if not resolved.is_dir():
            raise RuntimeError(f"output path is not a directory: {resolved}")
        if any(resolved.iterdir()):
            raise RuntimeError(f"output directory is not empty: {resolved}")
    else:
        resolved.mkdir(parents=True)
    return resolved


def load_puppeteer_config(args: argparse.Namespace, output_dir: Path) -> tuple[Path, dict]:
    if args.browser_executable is not None:
        executable = args.browser_executable.resolve()
        if not executable.is_file() or not os.access(executable, os.X_OK):
            raise RuntimeError(f"browser is not executable: {executable}")
        config = {
            "executablePath": str(executable),
            "args": ["--no-sandbox", "--disable-dev-shm-usage"],
        }
        config_path = output_dir / "puppeteer-config.json"
        config_path.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
        return config_path, config

    if args.puppeteer_config is None:
        raise RuntimeError(
            "selected scope contains Mermaid; provide --browser-executable "
            "or --puppeteer-config"
        )
    config_path = args.puppeteer_config.resolve()
    config = json.loads(config_path.read_text(encoding="utf-8"))
    executable_value = config.get("executablePath")
    if not isinstance(executable_value, str) or not Path(executable_value).is_absolute():
        raise RuntimeError("Puppeteer config needs an absolute executablePath")
    executable = Path(executable_value)
    if not executable.is_file() or not os.access(executable, os.X_OK):
        raise RuntimeError(f"configured browser is not executable: {executable}")
    return config_path, config


def browser_environment() -> dict[str, str]:
    environment = os.environ.copy()
    environment["PUPPETEER_SKIP_DOWNLOAD"] = "true"
    return environment


def mmdc_command() -> list[str]:
    return [
        "npx",
        "--yes",
        "--package",
        MERMAID_CLI_PACKAGE,
        "--",
        "mmdc",
    ]


def write_combined_markdown(blocks: list[MermaidBlock], output_dir: Path) -> Path:
    path = output_dir / "selected-mermaid.md"
    chunks: list[str] = []
    for index, block in enumerate(blocks, 1):
        chunks.extend(
            [
                f"## Diagram {index}: {block.source}:{block.line}",
                "",
                "```mermaid",
                block.definition.rstrip("\n"),
                "```",
                "",
            ]
        )
    path.write_text("\n".join(chunks), encoding="utf-8")
    return path


def render(
    combined: Path,
    output_dir: Path,
    config_path: Path,
    mermaid_config: Path | None,
    environment: dict[str, str],
) -> list[Path]:
    version = subprocess.run(
        [*mmdc_command(), "--version"],
        env=environment,
        text=True,
        capture_output=True,
        check=True,
    ).stdout.strip()
    if version != MERMAID_CLI_VERSION:
        raise RuntimeError(
            f"expected Mermaid CLI {MERMAID_CLI_VERSION}, received {version}"
        )

    artifacts = output_dir / "rendered"
    rendered_markdown = output_dir / "rendered.md"
    command = [
        *mmdc_command(),
        "--quiet",
        "--input",
        str(combined),
        "--output",
        str(rendered_markdown),
        "--outputFormat",
        "png",
        "--artefacts",
        str(artifacts),
        "--jobs",
        "1",
        "--backgroundColor",
        "white",
        "--puppeteerConfigFile",
        str(config_path),
    ]
    if mermaid_config is not None:
        command.extend(["--configFile", str(mermaid_config.resolve())])
    subprocess.run(command, env=environment, check=True)

    def artifact_index(path: Path) -> int:
        match = re.search(r"-(\d+)\.png$", path.name)
        if match is None:
            raise RuntimeError(f"unexpected Mermaid artifact name: {path.name}")
        return int(match.group(1))

    return sorted(artifacts.glob("*.png"), key=artifact_index)


def png_dimensions(path: Path) -> tuple[int, int]:
    header = path.read_bytes()[:24]
    if not header.startswith(b"\x89PNG\r\n\x1a\n") or len(header) < 24:
        raise RuntimeError(f"invalid PNG output: {path}")
    return struct.unpack(">II", header[16:24])


def write_manifest(
    blocks: list[MermaidBlock], rendered: list[Path], output_dir: Path
) -> None:
    entries = []
    for index, (block, image_path) in enumerate(zip(blocks, rendered), 1):
        width, height = png_dimensions(image_path)
        entries.append(
            {
                "index": index,
                "source": str(block.source),
                "fence_line": block.line,
                "rendered": str(image_path),
                "width": width,
                "height": height,
            }
        )
    (output_dir / "manifest.json").write_text(
        json.dumps(entries, indent=2) + "\n", encoding="utf-8"
    )


def write_contact_sheet(
    blocks: list[MermaidBlock], rendered: list[Path], output_dir: Path
) -> tuple[Path, int, int]:
    count = len(rendered)
    card_width = 900
    card_height = 700
    columns = max(1, math.ceil(math.sqrt(count * card_height / card_width)))
    rows = math.ceil(count / columns)
    sheet_width = columns * card_width + 40
    sheet_height = rows * card_height + 40

    cards: list[str] = []
    for index, (block, image_path) in enumerate(zip(blocks, rendered), 1):
        encoded = base64.b64encode(image_path.read_bytes()).decode("ascii")
        label = html.escape(f"{index}. {block.source}:{block.line}")
        cards.append(
            "<section class=\"card\">"
            f"<h2>{label}</h2>"
            f"<img src=\"data:image/png;base64,{encoded}\" "
            f"alt=\"Rendered Mermaid diagram {index}\">"
            "</section>"
        )

    contact_html = output_dir / "contact-sheet.html"
    contact_html.write_text(
        "<!doctype html><html><head><meta charset=\"utf-8\"><style>"
        "*{box-sizing:border-box}"
        f"html,body{{margin:0;width:{sheet_width}px;height:{sheet_height}px;"
        "overflow:hidden;background:#f3f4f6;font-family:Arial,sans-serif}}"
        f".sheet{{display:grid;grid-template-columns:repeat({columns},"
        f"{card_width - 20}px);gap:20px;padding:20px}}"
        f".card{{width:{card_width - 20}px;height:{card_height - 20}px;"
        "overflow:hidden;background:white;border:1px solid #d1d5db;"
        "border-radius:8px;padding:12px;display:flex;flex-direction:column;"
        "align-items:center}}"
        "h2{align-self:stretch;margin:0 0 8px;font-size:16px;font-weight:600;"
        "white-space:nowrap;overflow:hidden;text-overflow:ellipsis;color:#111827}"
        "img{display:block;max-width:100%;max-height:620px;object-fit:contain;"
        "margin:auto}"
        "</style></head><body><main class=\"sheet\">"
        + "".join(cards)
        + "</main></body></html>\n",
        encoding="utf-8",
    )
    return contact_html, sheet_width, sheet_height


def screenshot_contact_sheet(
    contact_html: Path,
    output_dir: Path,
    width: int,
    height: int,
    config: dict,
    environment: dict[str, str],
) -> Path:
    executable = Path(config["executablePath"])
    configured_args = config.get("args", [])
    if not isinstance(configured_args, list) or not all(
        isinstance(item, str) for item in configured_args
    ):
        raise RuntimeError("Puppeteer config args must be a list of strings")
    screenshot = output_dir / "contact-sheet.png"
    command = [
        str(executable),
        *configured_args,
        "--headless",
        "--hide-scrollbars",
        "--force-device-scale-factor=1",
        f"--window-size={width},{height}",
        f"--screenshot={screenshot}",
        contact_html.resolve().as_uri(),
    ]
    subprocess.run(
        command,
        env=environment,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=True,
    )
    png_dimensions(screenshot)
    return screenshot


def main() -> int:
    args = parse_args()
    files = markdown_files(args.targets)
    output_dir = prepare_output(args.output_dir)
    blocks = [block for path in files for block in mermaid_blocks(path)]
    if not blocks:
        (output_dir / "manifest.json").write_text("[]\n", encoding="utf-8")
        print(f"Markdown files: {len(files)}")
        print("Mermaid blocks: 0")
        print(f"Output: {output_dir}")
        return 0

    config_path, config = load_puppeteer_config(args, output_dir)
    environment = browser_environment()
    combined = write_combined_markdown(blocks, output_dir)
    rendered = render(
        combined,
        output_dir,
        config_path,
        args.mermaid_config,
        environment,
    )
    if len(rendered) != len(blocks):
        raise RuntimeError(f"rendered {len(rendered)}/{len(blocks)} Mermaid blocks")
    write_manifest(blocks, rendered, output_dir)
    contact_html, width, height = write_contact_sheet(blocks, rendered, output_dir)
    contact_sheet = screenshot_contact_sheet(
        contact_html,
        output_dir,
        width,
        height,
        config,
        environment,
    )

    print(f"Markdown files: {len(files)}")
    print(f"Mermaid CLI: {MERMAID_CLI_VERSION}")
    print(f"Rendered: {len(rendered)}/{len(blocks)}")
    print(f"Contact sheet: {contact_sheet}")
    print(f"Manifest: {output_dir / 'manifest.json'}")
    print(f"Output: {output_dir}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (
        json.JSONDecodeError,
        OSError,
        RuntimeError,
        subprocess.CalledProcessError,
    ) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)
