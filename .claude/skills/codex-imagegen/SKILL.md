---
name: codex-imagegen
description: >-
  Generate or edit raster images (infographics, diagrams, illustrations,
  mockups, hero images, icons as PNG) through the Codex CLI's bundled
  `imagegen` skill (built-in `image_gen` tool, gpt-image-2, ChatGPT login,
  no OPENAI_API_KEY). Use when the user asks for an image, picture,
  infographic, illustration, or image edit, or names imagegen.
when_to_use: >-
  "make an infographic", "imagegen으로 인포그래픽 만들어줘", "generate a hero
  image", "edit this png", "이미지 만들어줘", "draw a diagram as an image".
argument-hint: "[output.png] [prompt]"
allowed-tools: Bash(codex *) Bash(mkdir *) Bash(python3 *)
---

# Codex image generation

Delegate the image to Codex; this session cannot call `image_gen` itself.
Codex saves every generated image under `$CODEX_HOME/generated_images/`, and
its `imagegen` skill copies the final file into the workspace when told a
destination. This skill supplies that destination and verifies the result.
Codex prints only its final message to stdout; progress goes to stderr.

Rules:

- Pass `timeout: 600000` to the Bash tool.
- Choose an absolute destination path ending in `.png` inside the current
  project (default `<cwd>/assets/<slug>.png`). Never overwrite an existing
  file unless the user asked; use a `-v2` suffix instead. Create the
  directory with `mkdir -p` first, as a separate command.
- Write the `codex` command on one line with literal absolute paths. Do not
  use shell variables, `$(...)`, backticks, pipes, `;`, `&`, `>`, or
  backslash continuations; the image pre-approves only a plain `codex ...`
  command.
- `-C` must be the directory that contains the destination. Do not pass
  `-s`: Codex applies the sandbox policy from its config, which this image
  sets to full access because the disposable pod is the security boundary
  and Codex's own Linux sandbox cannot start inside it.
- The prompt must contain the literal text `$imagegen` and must be in single
  quotes; in double quotes the shell expands `$imagegen` to nothing.
- Reference or edit-target images go through `-i <file>`. `-i` accepts
  several files, so it must come first, right after `codex exec`, and be
  followed by another flag; otherwise it swallows the prompt as a file path.
  In the prompt, label each attached image's role (reference or edit target).
- Describe the image the way the user did; add only what makes it concrete
  (size or aspect ratio, exact text in quotes, style, what to avoid). Ask
  before inventing content.
- Always pass `--ephemeral` and `--skip-git-repo-check`.

## Generate

```bash
mkdir -p /abs/project/assets
codex exec --ephemeral --skip-git-repo-check -C /abs/project/assets '$imagegen Create a 1536x1024 flat-style infographic titled "Onboarding in 3 steps" with three numbered boxes: "Sign up", "Verify email", "Create a project". White background, no other text. Copy the final PNG to /abs/project/assets/onboarding-infographic.png (create it, do not overwrite other files) and print that path as the last line.'
```

## Edit

```bash
codex exec -i /abs/project/assets/hero.png --ephemeral --skip-git-repo-check -C /abs/project/assets '$imagegen The attached image is the edit target. Change only the background to a warm sunset gradient and keep the subject unchanged. Save the result as /abs/project/assets/hero-v2.png (do not overwrite other files) and print that path as the last line.'
```

## Verify and hand off

1. Check the exit code and read Codex's message from stdout.
2. Check the destination is a PNG and get its dimensions:

   ```bash
   python3 -c 'import struct,sys; p=sys.argv[1]; b=open(p,"rb").read(24); assert b[:8]==b"\x89PNG\r\n\x1a\n", "not a PNG"; w,h=struct.unpack(">II",b[16:24]); print(f"{p}: {w}x{h}")' /abs/project/assets/onboarding-infographic.png
   ```

3. Open the file with the Read tool and confirm it shows what was asked
   (title text, elements, edit applied). If it does not, say so and offer
   another run with a corrected prompt.

If the destination is missing, treat the run as failed: report Codex's
message (it may name a file under `$CODEX_HOME/generated_images/` that the
user can inspect by hand) and do not substitute another image.

Report the final path, dimensions, and byte size. Do not call the image
verified unless steps 2 and 3 passed. Do not upload it anywhere unless the
user asks.
