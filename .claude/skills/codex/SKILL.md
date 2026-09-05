---
name: codex
description: >-
  Delegate work to the OpenAI Codex CLI from this session: ask Codex a
  question or hand it a task, have Codex review a plan (plan-mode output or
  any markdown/text file), or run Codex's native code review on the working
  tree, a branch, or a commit. Use when the user names Codex or asks for a
  second model's opinion, review, or independent check.
when_to_use: >-
  "ask codex", "codex한테 물어봐", "have codex review this plan",
  "codex한테 이 plan 리뷰 시켜줘", "codex review the diff",
  "get a second opinion from codex", "let codex implement X".
argument-hint: "[ask|plan|review] [path or instructions]"
allowed-tools: Bash(codex *)
---

# Codex

Run the Codex CLI non-interactively with `codex exec` and report what it
returns. Codex runs as a separate agent with its own ChatGPT login. It does
not see this conversation, so every call must carry the full context it needs.
Codex prints only its final message to stdout; progress goes to stderr.

Standing rules for every call:

- Pass `timeout: 600000` to the Bash tool. Reviews and multi-step tasks run
  for minutes.
- Write the whole command on one line. The image pre-approves a command that
  starts with `codex ` and contains none of `;`, `&`, `|`, `>`, a backtick,
  `$(`, `<(`, `--dangerously`, or a newline. Backslash line continuations count as newlines. Keep
  those characters out of the prompt text too: use commas and periods, and
  write "and" instead of `&`.
- Do not pass `-s`. Codex applies the sandbox policy from its config
  (`sandbox_mode`), which this image sets to full access because the
  disposable pod is the security boundary and Codex's own Linux sandbox
  cannot start inside it. State the intent in the prompt instead: say "do not
  modify any files" unless the user asked Codex to change files. Never pass
  `--dangerously-bypass-approvals-and-sandbox`.
- Always pass `--ephemeral` (no session files in a disposable pod) and
  `--skip-git-repo-check` (the working directory may not be a git repository).
- Give the prompt in single quotes as the last argument. Never pipe into
  `codex`. For a prompt that needs those forbidden characters or several
  paragraphs, write it to a file under `/tmp` with the Write tool, pass `-`
  as the prompt, and add `< /tmp/that-file` to the command.
- Do not pin a model unless the user names one; then add `-m <model>`.
- If the command exits non-zero, report the error and stop. Do not retry in
  a loop.
- Report Codex's final message verbatim, then add at most three lines of your
  own assessment. Do not act on Codex's suggestions unless the user asks.

## Ask or delegate

State the task with the context Codex needs (paths, constraints, expected
output):

```bash
codex exec --ephemeral --skip-git-repo-check 'Explain the retry logic in src/queue.ts and list the edge cases it misses. Do not modify any files.'
```

When the user asked Codex to edit files, say so in the prompt and afterwards
show `git status --short` and `git diff --stat` so the user sees what Codex
changed.

## Review a plan

Plan review is read-only analysis and is allowed in plan mode: Codex reads
the plan file and the repository, is told not to modify anything, and prints
a report. Nothing is written. Give Codex the absolute path of the plan file
(the plan file of the current session, or a path the user named). If the plan
exists only in the conversation, write it to `/tmp/codex-plan.md` first.

```bash
codex exec --ephemeral --skip-git-repo-check 'Review the implementation plan at /home/node/.claude/plans/example.md. Another agent wrote it for the repository in the current directory. Read the plan and the repository as needed. Do not modify any files. Report, in this order: a verdict of approve, approve with changes, or rework. Wrong or unverified assumptions, each with the file or command that disproves it. Missing steps, ordering problems, and risks. Anything simpler that meets the same goal. Be concrete and cite paths. Do not rewrite the plan.'
```

Return the report verbatim under a "Codex review" heading. Then list which
points you would accept and which you would reject, one line of reasoning
each. Change the plan only if the user asked for the review as part of
refining it, or after the user agrees.

## Review code

Use Codex's native review for git changes. Global flags go before `review`.
Pick exactly one target:

```bash
codex exec --ephemeral --skip-git-repo-check review --uncommitted
codex exec --ephemeral --skip-git-repo-check review --base main
codex exec --ephemeral --skip-git-repo-check review --commit HEAD
```

A target flag and a custom prompt are mutually exclusive: `codex exec review`
rejects `--uncommitted 'focus on X'`. To steer the review, pass the
instructions as the only target and name the scope inside them:

```bash
codex exec --ephemeral --skip-git-repo-check review 'Review the uncommitted changes in this repository. Focus on error handling.'
```

Present the findings verbatim, then your assessment.

## Failures

- If Codex reports that it is not logged in, tell the user to run `codex`
  once in the pod to sign in. Do not attempt to log in yourself.
- On rate-limit or network errors, report them and stop.
