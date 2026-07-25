#!/usr/bin/env python3
"""Validate common Markdown, local-link, anchor, and image invariants."""

from __future__ import annotations

import argparse
import fnmatch
import re
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import unquote


MARKDOWN_EXTENSIONS = {".md", ".mdx", ".markdown"}
IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg"}
ATX_HEADING_PATTERN = re.compile(r"^(#{1,6})\s+(.+?)\s*#*\s*$")
SETEXT_HEADING_PATTERN = re.compile(r"^[ \t]{0,3}(?:=+|-+)[ \t]*$")
FENCE_OPEN_PATTERN = re.compile(r"^[ \t]{0,3}(`{3,}|~{3,})(.*)$")
HTML_ANCHOR_PATTERN = re.compile(
    r"""<(?:a|[A-Za-z][^>]*)\s+(?:[^>]*?\s)?(?:id|name)=["']([^"']+)["']"""
)
HTML_TARGET_PATTERN = re.compile(
    r"""<([A-Za-z][\w.-]*)\b[^>]*?\b(href|src)=["']([^"']+)["']""",
    re.IGNORECASE,
)
REFERENCE_DEFINITION_PATTERN = re.compile(
    r"^[ \t]{0,3}\[([^\]]+)\]:[ \t]*(.+?)\s*$"
)
REFERENCE_USE_PATTERN = re.compile(
    r"(?<!\\)(!?)\[([^\]]+)\]\[([^\]]*)\]"
)
SHORTCUT_IMAGE_PATTERN = re.compile(
    r"(?<!\\)!\[([^\]]+)\](?!\s*[\[(])"
)


@dataclass(frozen=True)
class MarkdownDocument:
    content: str
    visible: list[tuple[int, str]]
    mermaid_blocks: int
    unclosed_fence: tuple[int, str] | None
    anchors: set[str]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Check Markdown whitespace, local links/anchors, image references, "
            "image signatures, Mermaid fences, and optional scoped orphan assets."
        )
    )
    parser.add_argument("markdown_root", type=Path)
    parser.add_argument(
        "--asset-root",
        action="append",
        default=[],
        type=Path,
        help="Asset directory to validate; repeat for multiple roots.",
    )
    parser.add_argument(
        "--check-orphans",
        action="store_true",
        help="Fail on unreferenced images under asset roots.",
    )
    parser.add_argument(
        "--allow-orphan",
        action="append",
        default=[],
        help="Glob relative to an asset root to exempt from orphan checks.",
    )
    return parser.parse_args()


def markdown_files(root: Path) -> list[Path]:
    if root.is_file():
        return [root] if root.suffix.lower() in MARKDOWN_EXTENSIONS else []
    return sorted(
        path
        for path in root.rglob("*")
        if path.is_file() and path.suffix.lower() in MARKDOWN_EXTENSIONS
    )


def read_utf8(path: Path) -> tuple[str | None, str | None]:
    try:
        data = path.read_bytes()
    except OSError as exc:
        return None, f"cannot read file: {exc}"
    try:
        return data.decode("utf-8"), None
    except UnicodeDecodeError as exc:
        return None, f"invalid UTF-8 at byte {exc.start}"


def visible_lines(
    content: str,
) -> tuple[list[tuple[int, str]], int, tuple[int, str] | None]:
    visible: list[tuple[int, str]] = []
    fence: tuple[str, int, int] | None = None
    mermaid_blocks = 0
    in_html_comment = False

    for line_number, line in enumerate(content.splitlines(), 1):
        if fence is not None:
            marker_char, marker_length, _ = fence
            closing = re.match(
                rf"^[ \t]{{0,3}}{re.escape(marker_char)}"
                rf"{{{marker_length},}}[ \t]*$",
                line,
            )
            if closing:
                fence = None
            continue

        masked, in_html_comment = mask_html_comments(line, in_html_comment)
        match = FENCE_OPEN_PATTERN.match(masked)
        if match:
            marker = match.group(1)
            info = match.group(2).strip().split(maxsplit=1)
            if info and info[0].casefold() == "mermaid":
                mermaid_blocks += 1
            fence = (marker[0], len(marker), line_number)
            continue
        visible.append((line_number, masked))

    if fence is None:
        return visible, mermaid_blocks, None
    marker_char, _, opening_line = fence
    return visible, mermaid_blocks, (opening_line, marker_char)


def mask_html_comments(line: str, in_comment: bool) -> tuple[str, bool]:
    masked = list(line)
    index = 0
    while index < len(line):
        if in_comment:
            closing = line.find("-->", index)
            if closing < 0:
                for position in range(index, len(line)):
                    masked[position] = " "
                return "".join(masked), True
            for position in range(index, closing + 3):
                masked[position] = " "
            index = closing + 3
            in_comment = False
            continue

        opening = line.find("<!--", index)
        if opening < 0:
            break
        closing = line.find("-->", opening + 4)
        if closing < 0:
            for position in range(opening, len(line)):
                masked[position] = " "
            return "".join(masked), True
        for position in range(opening, closing + 3):
            masked[position] = " "
        index = closing + 3
    return "".join(masked), in_comment


def mask_code_spans(line: str) -> str:
    masked = list(line)
    index = 0
    while index < len(line):
        if line[index] != "`":
            index += 1
            continue
        run_end = index + 1
        while run_end < len(line) and line[run_end] == "`":
            run_end += 1
        marker = line[index:run_end]
        closing = line.find(marker, run_end)
        if closing < 0:
            index = run_end
            continue
        for position in range(index, closing + len(marker)):
            masked[position] = " "
        index = closing + len(marker)
    return "".join(masked)


def find_closing(text: str, start: int, opening: str, closing: str) -> int:
    depth = 0
    index = start
    while index < len(text):
        char = text[index]
        if char == "\\":
            index += 2
            continue
        if char == opening:
            depth += 1
        elif char == closing:
            depth -= 1
            if depth == 0:
                return index
        index += 1
    return -1


def inline_markdown_targets(line: str) -> list[tuple[str, bool]]:
    targets: list[tuple[str, bool]] = []
    text = mask_code_spans(line)
    index = 0
    while index < len(text):
        opening = text.find("[", index)
        if opening < 0:
            break
        if opening > 0 and text[opening - 1] == "\\":
            index = opening + 1
            continue
        label_end = find_closing(text, opening, "[", "]")
        if label_end < 0:
            break
        target_start = label_end + 1
        if target_start >= len(text) or text[target_start] != "(":
            index = label_end + 1
            continue
        target_end = find_closing(text, target_start, "(", ")")
        if target_end < 0:
            index = target_start + 1
            continue
        is_image = (
            opening > 0
            and text[opening - 1] == "!"
            and (opening < 2 or text[opening - 2] != "\\")
        )
        targets.append((text[target_start + 1 : target_end], is_image))
        index = target_end + 1
    return targets


def normalize_reference_label(label: str) -> str:
    return re.sub(r"\s+", " ", label.strip()).casefold()


def reference_definitions(
    lines: list[tuple[int, str]],
) -> dict[str, tuple[str, int]]:
    definitions: dict[str, tuple[str, int]] = {}
    for line_number, line in lines:
        match = REFERENCE_DEFINITION_PATTERN.match(mask_code_spans(line))
        if not match:
            continue
        label = normalize_reference_label(match.group(1))
        definitions.setdefault(label, (match.group(2), line_number))
    return definitions


def reference_uses(
    lines: list[tuple[int, str]],
) -> list[tuple[str, bool, int]]:
    uses: list[tuple[str, bool, int]] = []
    for line_number, line in lines:
        masked = mask_code_spans(line)
        if REFERENCE_DEFINITION_PATTERN.match(masked):
            continue
        for match in REFERENCE_USE_PATTERN.finditer(masked):
            label = match.group(3) or match.group(2)
            uses.append(
                (
                    normalize_reference_label(label),
                    match.group(1) == "!",
                    line_number,
                )
            )
        for match in SHORTCUT_IMAGE_PATTERN.finditer(masked):
            uses.append(
                (
                    normalize_reference_label(match.group(1)),
                    True,
                    line_number,
                )
            )
    return uses


def heading_text(text: str) -> str:
    text = re.sub(r"!\[([^\]]*)\]\([^)]*\)", r"\1", text)
    text = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", text)
    text = re.sub(r"!\[([^\]]*)\]\[[^\]]*\]", r"\1", text)
    text = re.sub(r"\[([^\]]+)\]\[[^\]]*\]", r"\1", text)
    return text


def github_slug(text: str) -> str:
    text = heading_text(text)
    text = re.sub(r"`([^`]*)`", r"\1", text.strip().lower())
    text = re.sub(r"<[^>]+>", "", text)
    text = re.sub(r"[*_~]", "", text)
    text = re.sub(r"[^\w\- ]", "", text, flags=re.UNICODE)
    return re.sub(r"[ \t]+", "-", text)


def anchors_for(lines: list[tuple[int, str]]) -> set[str]:
    anchors: set[str] = set()
    counts: Counter[str] = Counter()
    headings: list[str] = []
    previous: tuple[int, str] | None = None

    for line_number, line in lines:
        match = ATX_HEADING_PATTERN.match(line)
        if match:
            headings.append(match.group(2))
        elif (
            SETEXT_HEADING_PATTERN.match(line)
            and previous is not None
            and previous[0] == line_number - 1
            and previous[1].strip()
        ):
            headings.append(previous[1].strip())
        previous = (line_number, line)

    anchors.update(
        HTML_ANCHOR_PATTERN.findall("\n".join(line for _, line in lines))
    )
    for heading in headings:
        base = github_slug(heading)
        occurrence = counts[base]
        counts[base] += 1
        anchors.add(base if occurrence == 0 else f"{base}-{occurrence}")
    return anchors


def load_document(path: Path) -> tuple[MarkdownDocument | None, str | None]:
    content, error = read_utf8(path)
    if content is None:
        return None, error
    visible, mermaid_blocks, unclosed_fence = visible_lines(content)
    return (
        MarkdownDocument(
            content=content,
            visible=visible,
            mermaid_blocks=mermaid_blocks,
            unclosed_fence=unclosed_fence,
            anchors=anchors_for(visible),
        ),
        None,
    )


def normalize_target(raw: str) -> str:
    target = raw.strip()
    if target.startswith("<"):
        closing = target.find(">")
        if closing >= 0:
            return target[1:closing]
    match = re.match(
        r"""(\S+)(?:\s+(?:"[^"]*"|'[^']*'|\([^)]*\)))?$""",
        target,
    )
    return match.group(1) if match else target


def is_external(target: str) -> bool:
    return target.startswith("//") or bool(
        re.match(r"^[A-Za-z][A-Za-z0-9+.-]*:", target)
    )


def image_signature_ok(path: Path) -> bool:
    if path.suffix.lower() == ".svg":
        start = path.read_bytes()[:1024].lstrip()
        return b"<svg" in start
    header = path.read_bytes()[:16]
    suffix = path.suffix.lower()
    if suffix == ".png":
        return header.startswith(b"\x89PNG\r\n\x1a\n")
    if suffix in {".jpg", ".jpeg"}:
        return header.startswith(b"\xff\xd8\xff")
    if suffix == ".gif":
        return header.startswith((b"GIF87a", b"GIF89a"))
    if suffix == ".webp":
        return header.startswith(b"RIFF") and header[8:12] == b"WEBP"
    return False


def main() -> int:
    args = parse_args()
    root = args.markdown_root.resolve()
    files = markdown_files(root)
    if not files:
        print(f"ERROR: no Markdown files found under {root}", file=sys.stderr)
        return 2

    errors: list[str] = []
    warnings: list[str] = []
    document_cache: dict[Path, MarkdownDocument | None] = {}
    document_errors: dict[Path, str] = {}
    image_refs: set[Path] = set()
    external_links = 0
    mermaid_blocks = 0

    def cached_document(path: Path) -> MarkdownDocument | None:
        resolved = path.resolve()
        if resolved not in document_cache:
            document, error = load_document(resolved)
            document_cache[resolved] = document
            if error is not None:
                document_errors[resolved] = error
        return document_cache[resolved]

    def display_path(path: Path) -> Path | str:
        if root.is_dir():
            try:
                return path.relative_to(root)
            except ValueError:
                return path
        return path.name

    for path in files:
        document = cached_document(path)
        if document is None:
            errors.append(f"{display_path(path)}: {document_errors[path.resolve()]}")
            continue
        if document.unclosed_fence is not None:
            opening_line, marker = document.unclosed_fence
            errors.append(
                f"{display_path(path)}:{opening_line}: "
                f"unclosed {marker * 3} fenced code block"
            )

    for path in files:
        document = cached_document(path)
        if document is None:
            continue
        content = document.content
        display = display_path(path)

        if content and not content.endswith("\n"):
            errors.append(f"{display}: missing final newline")
        if "\r\n" in content:
            errors.append(f"{display}: CRLF line endings")
        for line_number, line in enumerate(content.splitlines(), 1):
            if line.rstrip(" \t") != line:
                errors.append(f"{display}:{line_number}: trailing whitespace")

        mermaid_blocks += document.mermaid_blocks
        definitions = reference_definitions(document.visible)
        uses = reference_uses(document.visible)
        image_labels = {label for label, is_image, _ in uses if is_image}

        for label, _, line_number in uses:
            if label not in definitions:
                errors.append(
                    f"{display}:{line_number}: "
                    f"missing reference definition [{label}]"
                )

        targets: list[tuple[str, bool]] = []
        for _, line in document.visible:
            targets.extend(inline_markdown_targets(line))

        visible_content = "\n".join(
            mask_code_spans(line) for _, line in document.visible
        )
        for tag, attribute, raw in HTML_TARGET_PATTERN.findall(visible_content):
            normalized = normalize_target(raw)
            suffix = normalized.partition("#")[0].partition("?")[0]
            is_image = (
                attribute.casefold() == "src"
                and (
                    tag.casefold() in {"img", "image", "picture", "source"}
                    or Path(suffix).suffix.lower() in IMAGE_EXTENSIONS
                )
            )
            targets.append((raw, is_image))

        for label, (raw, _) in definitions.items():
            targets.append((raw, label in image_labels))

        for raw, is_image in targets:
            target = normalize_target(raw)
            if not target:
                errors.append(f"{display}: empty local target")
                continue
            if target.casefold().startswith(("http://", "https://")):
                external_links += 1
                continue
            if is_external(target):
                continue
            if target.startswith("#"):
                anchor = unquote(target[1:])
                if anchor and anchor not in document.anchors:
                    errors.append(f"{display}: missing anchor {target}")
                continue

            path_part, separator, anchor = target.partition("#")
            path_part = path_part.partition("?")[0]
            decoded_path = unquote(path_part)
            decoded_path = re.sub(r"\\([ ()])", r"\1", decoded_path)
            destination = (
                path.resolve()
                if decoded_path == ""
                else (path.parent / decoded_path).resolve()
            )
            if not destination.exists():
                errors.append(f"{display}: missing local target {target}")
                continue

            if is_image:
                image_refs.add(destination)
                if destination.suffix.lower() not in IMAGE_EXTENSIONS:
                    warnings.append(
                        f"{display}: image reference has unexpected extension {target}"
                    )
                else:
                    try:
                        signature_ok = image_signature_ok(destination)
                    except OSError as exc:
                        errors.append(
                            f"{display}: cannot read image {target}: {exc}"
                        )
                    else:
                        if not signature_ok:
                            errors.append(
                                f"{display}: invalid image signature {target}"
                            )

            if (
                separator
                and anchor
                and destination.suffix.lower() in MARKDOWN_EXTENSIONS
            ):
                destination_document = cached_document(destination)
                if destination_document is None:
                    errors.append(
                        f"{display}: cannot read anchor target {target}: "
                        f"{document_errors[destination]}"
                    )
                    continue
                decoded_anchor = unquote(anchor)
                if decoded_anchor not in destination_document.anchors:
                    errors.append(f"{display}: missing anchor {target}")

    asset_roots = [path.resolve() for path in args.asset_root]
    asset_files: set[Path] = set()
    for asset_root in asset_roots:
        if not asset_root.exists():
            errors.append(f"missing asset root: {asset_root}")
            continue
        if not asset_root.is_dir():
            errors.append(f"asset root is not a directory: {asset_root}")
            continue
        for path in asset_root.rglob("*"):
            if path.is_file() and path.suffix.lower() in IMAGE_EXTENSIONS:
                asset_files.add(path.resolve())
                try:
                    signature_ok = image_signature_ok(path)
                except OSError as exc:
                    errors.append(f"cannot read image {path}: {exc}")
                else:
                    if not signature_ok:
                        errors.append(f"invalid image signature: {path}")

    if args.check_orphans:
        for path in sorted(asset_files - image_refs):
            owning_root = next(
                root_path for root_path in asset_roots if path.is_relative_to(root_path)
            )
            relative = path.relative_to(owning_root).as_posix()
            if any(fnmatch.fnmatch(relative, glob) for glob in args.allow_orphan):
                continue
            errors.append(f"orphan asset: {path}")

    print(f"Markdown files: {len(files)}")
    print(f"External links counted: {external_links}")
    print(f"Mermaid blocks counted: {mermaid_blocks}")
    print(f"Local image references: {len(image_refs)}")
    print(f"Assets scanned: {len(asset_files)}")
    print(f"Warnings: {len(warnings)}")
    print(f"Errors: {len(errors)}")
    for warning in warnings:
        print(f"WARNING: {warning}")
    for error in errors:
        print(f"ERROR: {error}")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
