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
Codex prints its final message to stdout and progress to stderr
([non-interactive mode](https://learn.chatgpt.com/docs/non-interactive-mode)).

Standing rules for every call, using the
[Codex CLI options](https://learn.chatgpt.com/docs/cli/reference):

- Pass `timeout: 600000` to the Bash tool. Reviews and multi-step tasks run
  for minutes.
- Quote prompts and paths as shell arguments. Use a single-quoted prompt when
  possible; for literal apostrophes or long prompts, use a uniquely named
  temporary prompt file and `codex exec ... - < /tmp/prompt-file`.
- Do not pass `-s`. Codex applies the sandbox policy from its config
  (`sandbox_mode`), which this image sets to full access for trusted IaaS
  development. State the authorized scope in the prompt: say "do not modify
  any files" for questions and reviews. Never pass
  `--dangerously-bypass-approvals-and-sandbox`.
- Always pass `--ephemeral` (no session files in a disposable pod) and
  `--skip-git-repo-check` (the working directory may not be a git repository).
- In plan mode, use an existing plan file or pass the plan in the prompt.
  Create a temporary file only when the active mode permits that write.
- Do not pin a model unless the user names one; then add `-m <model>`.
- On a recoverable read-only failure, diagnose the cause and retry once.
  Before retrying an editing task, inspect partial changes to avoid repeating
  completed work. Do not retry authentication failures or loop on errors.
- Report Codex's final message verbatim, then add at most three lines of your
  own assessment. Apply relevant findings when the original request includes
  implementation; keep review-only requests read-only.

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
a report. Give Codex the absolute path of an existing plan file, or include
its text in the prompt when the plan exists only in the conversation. Follow
the active mode's write restrictions for any temporary prompt file.

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
- Retry a transient network or rate-limit failure once after any supplied retry
  delay. If it persists, report the blocker and finish independent authorized
  work. Do not treat a failed delegation as completion of the original task.
