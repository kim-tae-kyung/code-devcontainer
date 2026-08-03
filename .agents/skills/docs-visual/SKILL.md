---
name: docs-visual
description: Research, create, rewrite, or deeply audit technical documentation from authoritative official docs, GitHub repositories, source code, schemas, tests, and runtime configuration, then add verified imagegen-first visuals or maintainable Mermaid diagrams when they materially improve understanding. Use only when the user explicitly invokes `$docs-visual`, names `docs-visual`, or identifies its skill path. Do not invoke implicitly for documentation, research, audit, or visualization tasks that merely match these capabilities.
---

# Docs Visual

Build evidence-backed documentation and, when useful, visuals as one verified
artifact. Treat existing prose, diagrams, and citations as untrusted until
direct sources support them.

## Follow the operating contract

The global operating principles in `AGENTS.md` apply as written. This skill adds
two rules for documentation work and restates none of them:

- Support claims about repository behavior with pinned primary evidence, not
  official documentation alone.
- Surface a must-know pitfall as a brief **Known Issue** with a direct official
  or primary-source link. Do not bury it in prose or invent one without
  evidence.

## Start with a scope contract

Before changing files:

1. Read repository instructions. If the workspace is a Git worktree, inspect
   `git status`.
2. Preserve user and unrelated changes.
3. Establish the exact subject, audience, repository/doc roots, version or
   revision pin, inclusions, exclusions, and required deliverables.
4. Decide whether the task is:
   - **Audit and revise**: inventory every existing document, claim, diagram,
     image reference, and link before editing.
   - **Create new**: inventory the available evidence and design the
     information architecture before drafting.
   - **Hybrid**: retain only verified portions of existing material and build
     missing coverage from primary evidence.
5. Record unresolved scope choices. Ask only when a choice would materially
   change the product or audience; otherwise make and disclose a conservative
   assumption.

Never broaden a product's capabilities merely because an external system could
call it or because an adjacent project mentions a requirement.

## Research from primary evidence

Read [references/research-and-evidence.md](references/research-and-evidence.md)
before source investigation.

1. Pin the requested repository revision. Do not silently move to a newer
   release.
2. Prefer local repository resources, connected sources, or an isolated clone
   outside the working tree.
3. Map each important claim through all applicable layers:
   public contract → handler → workflow/job → internal API → persisted state →
   controller/reconciler → external effect → observed status.
4. Cross-check implementation, schemas, tests, configuration, and official
   docs. Do not stop at the first plausible symbol or comment.
5. Maintain a working claim matrix with:
   claim, document location, source contract, implementation path, downstream
   effect, completion/failure state, evidence level, and required change.
6. Label non-definitive conclusions:
   - `Inference`
   - `Deployment-dependent`
   - `Open verification`

Use current web research when facts may have changed. Prefer official
documentation and primary repositories; cite permanent versioned URLs when
available.

## Design the documentation set

Do not let the old file layout dictate the result.

1. Define one authoritative home for each concept.
2. Separate overview, contracts, detailed flows, status/failure behavior, and
   reference material.
3. Use exact names, methods, paths, identifiers, fields, enums, roles, and
   readiness conditions.
4. Separate synchronous acknowledgement from asynchronous convergence.
5. Separate control path, data path, and observation path.
6. Explain actor boundaries and ownership, not just file names.
7. Link detail chapters instead of duplicating claims across files.
8. Remove or replace material that is wrong, redundant, out of scope, or
   likely to mislead. Check references before deletion.

For an existing set, create the replacement structure only after the audit
matrix is mature. For a new set, validate the proposed structure against the
evidence inventory before filling it.

## Write from the matrix

1. Lead each section with the reader's operational model.
2. State exact contracts wherever the source supports them.
3. Describe conditions and branches instead of choosing one
   deployment-specific behavior as universal.
4. Keep resource-specific state machines separate.
5. Distinguish retry owners: caller, transport/client, workflow engine,
   activity/job, controller reconciliation, and operator.
6. Do not claim idempotency, rollback, readiness, security, cleanup, or
   durability without direct evidence.
7. Put citations next to the claims they support. A link's existence is not
   evidence that it proves the sentence.
8. Preserve uncertainty when code and schemas disagree; identify which source
   controls runtime behavior.

Use `apply_patch` for repository edits. Keep clones, generated indexes,
renderer output, and audit scratch data outside the repository unless the user
asks to retain them.

## Plan visuals after understanding the system

Read [references/visual-workflow.md](references/visual-workflow.md) before
creating or changing visuals.

1. Inventory every existing Mermaid block, raster image, vector asset, and
   reference.
2. Classify each visual as:
   - retain
   - edit
   - regenerate
   - delete
   - add
3. Add a visual only when it materially clarifies topology, sequence,
   dependency, state, comparison, or a path with several actors.
   Producing no visual is valid when none improves understanding; report that
   decision.
4. Prefer imagegen for new or regenerated reader-facing visuals, including
   conceptual boxes-and-arrows diagrams. When imagegen and Mermaid would both
   communicate the verified model adequately, choose imagegen.
5. Use Mermaid only when exact diffable text, frequent maintenance, executable
   state/sequence semantics, repository policy, or an explicit user request
   makes repo-native source materially more valuable.
6. Do not create Mermaid and raster versions of the same visual merely for
   redundancy. Retain a correct existing Mermaid diagram unless changing its
   medium has clear reader value.
7. Before image generation or raster editing, read the `imagegen` skill's
   `SKILL.md` fully and follow its built-in workflow.
8. Never generate before the underlying claims and arrow directions are
   verified.
9. Do not force an aspect ratio. Choose width, height, and orientation for
   content legibility.
10. Use one generation call per distinct asset. Inspect every output, then make
   one precise edit at a time.
11. Copy only final selected assets into the workspace and update consumers.
12. Keep the final prompt set and generation mode for the handoff report.

Do not choose Mermaid solely because a visual contains boxes and arrows.
Choose it for the maintainability or exactness conditions above.

## Validate the integrated result

Read
[references/validation-and-handoff.md](references/validation-and-handoff.md)
before final validation.

At minimum:

1. Run repository-specific tests and, in a Git worktree, `git diff --check`.
2. Validate Markdown style in the repository's accepted configuration.
3. Check local links, anchors, image references, and scoped orphan assets.
4. If the selected scope contains Mermaid, read
   [references/mermaid-validation.md](references/mermaid-validation.md) and use
   its fixed-version runner. Render changed or added blocks by default; render
   the complete set only for a full audit, new documentation set, shared
   Mermaid configuration change, release gate, or explicit user request.
5. Verify external source paths and line anchors against the pinned source;
   distinguish network blocking from real broken links.
6. Decode and visually inspect every final image for text, cropping,
   duplication, direction, ownership, and factual alignment with the prose.
7. Search for stale versions, inconsistent API paths, roles, field names,
   statuses, readiness conditions, and out-of-scope concepts.
8. Compare forward provisioning dependencies with reverse teardown order.
9. Confirm prose and every visual form present describe the same behavior.

Run the bundled basic checker when applicable:

```bash
python3 <docs-visual-skill-dir>/scripts/validate_docs.py <markdown-root> \
  --asset-root <asset-root> \
  --check-orphans
```

Resolve `<docs-visual-skill-dir>` from the directory containing this
`SKILL.md`; do not assume the target repository contains the bundled script.
Enable orphan checking only when the selected Markdown tree owns the complete
asset root; otherwise scan the broader owning documentation tree or omit that
flag.

Do not declare success from a partial parser. If a local renderer fails because
of its environment, report the environment failure separately instead of
exploring ad hoc installations or renderer versions.

## Finish the work

Follow the active collaboration mode and the user's authorization. When
implementation is authorized, complete research, file edits, useful visual
work, and integrated validation rather than returning only a plan or findings
list.

Report:

- the confirmed system or subject model;
- documents created, rewritten, retained, or removed;
- major technical corrections;
- evidence that remains uncertain and why;
- every visual's retain/edit/regenerate/delete/add decision;
- final image paths, final prompt set, and imagegen mode;
- validation commands and results;
- residual risks or follow-up verification.

For a review-only request, do not mutate files. Return severity-ordered findings
with exact locations, direct evidence, recommended changes, and evidence level.
