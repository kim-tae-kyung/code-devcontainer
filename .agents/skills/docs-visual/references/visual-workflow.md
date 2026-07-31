# Visual workflow

## Contents

- Visual selection
- Existing visual audit
- Diagram semantics
- Imagegen workflow
- Prompt structure
- Inspection and iteration
- Asset integration

## Visual selection

Use a visual when it makes a relationship materially easier to understand.

Good candidates:

- three or more dependent steps;
- one actor feeding several downstream systems;
- topology, hierarchy, ownership, or trust boundaries;
- separate control, data, and observation paths;
- resource dependency and reverse deletion order;
- resource-specific state transitions;
- failure branches and retry ownership;
- comparisons with repeated fields or conditions.

Prefer prose or a table for:

- a single fact or one-step action;
- exact endpoint catalogs;
- dense enumerations with no spatial relationship;
- content that changes often and is easier to diff as text.

Choose the smallest maintainable form:

- table for mappings and comparisons;
- imagegen infographic for reader-facing architecture, onboarding, conceptual
  synthesis, actor lanes, physical boundaries, annotated flows, or polished
  comparisons;
- Mermaid for exact and frequently maintained calls, acknowledgements, enums,
  state transitions, or deterministic dependencies whose diffable source is
  materially valuable.

When imagegen and Mermaid both communicate the verified model adequately,
prefer imagegen. Boxes and arrows alone are not a reason to choose Mermaid.
Do not create both forms for the same idea merely as a validation aid.

## Existing visual audit

Open every existing raster before deciding. For each visual, record:

- where it is referenced;
- what claims it makes;
- whether it is still legible;
- whether components, labels, arrows, states, and boundaries match evidence;
- whether it duplicates the body or improves it;
- whether an editable Mermaid/vector source exists.

Classify:

- **Retain**: correct, readable, and useful.
- **Edit**: structure is valid; a small number of objects or labels are wrong.
- **Regenerate**: composition or conceptual model is structurally wrong.
- **Delete**: misleading, redundant, or less clear than the text.
- **Add**: a missing visual materially improves comprehension.

After deletion, remove Markdown references and check for scoped orphan assets.

## Diagram semantics

Define a consistent visual grammar before producing a set:

- actor and system zones;
- synchronous control arrows;
- asynchronous workflow/inventory arrows;
- live packet or data arrows;
- observation/reporting arrows;
- deployment-dependent edges;
- warnings and failed states;
- resource ownership and trust boundaries.

Keep direction strict:

- request and response arrows must be independently visible when meaningful;
- polling must point from poller to source, with observation returning;
- steady-state packets must not pass through control components;
- a database arrow must not imply that another component owns the database;
- bidirectional arrows require truly bidirectional semantics.

Use exact component, endpoint, RPC, field, and status names. Avoid:

- invented service layers;
- arbitrary fixed IPs, ports, VLANs, ASNs, route targets, or timeouts;
- generic `Ready` applied across unrelated resources;
- icons that imply unsupported virtualization, cloud, or security guarantees;
- “automatic retry” without identifying its owner.

Write visual labels in English unless the user explicitly requests another
artifact language. Treat values observed in the working environment as test
evidence, not reusable diagram content; include them only when the artifact
defines that environment.

Do not force 16:9 or another aspect ratio. Use landscape, portrait, or a wide
custom canvas according to content. Prioritize readable labels, natural panel
width, and sufficient spacing over uniform dimensions.

## Imagegen workflow

Use the separate `imagegen` skill for raster generation and editing. Read its
full `SKILL.md` when raster work begins.

Follow these rules:

1. Use built-in image generation by default for new or regenerated
   reader-facing visuals.
2. Generate one distinct asset per call.
3. For a local edit target, inspect it with `view_image` first.
4. Distinguish edit targets from style references.
5. Generate into the tool's default location, then copy the selected final into
   the workspace.
6. Never leave a project-referenced asset only under the generation cache.
7. Do not overwrite an existing asset unless replacement is authorized.
8. Inspect the generated image at original detail.
9. Iterate with one concrete change at a time and repeat invariants.
10. Report final paths, prompt set, and generation mode.

Use Mermaid, SVG, HTML/CSS, or another native format instead when repository
policy requires it or when exact diffable text and frequent maintenance
materially outweigh the reader-facing value of imagegen.

## Prompt structure

Use the `infographic-diagram`, `scientific-educational`, or
`productivity-visual` imagegen taxonomy as appropriate.

Build prompts from verified content:

```text
Use case: infographic-diagram
Asset type: technical documentation infographic
Primary request: <exact concept and reader goal>
Subject: <verified actors/resources>
Structure: <panels, lanes, sequence, or comparison>
Arrow semantics: <control, async, data, observation, failure>
Exact text: <verbatim labels, methods, paths, states, RPCs>
Style: <light/dark, outline system, color grammar>
Composition: flexible canvas; prioritize legibility; no stretching
Constraints: only verified relationships; label deployment-dependent behavior
Avoid: unsupported components, fixed sample values, decorative filler,
ambiguous arrows, clipped text, watermark
```

Use English exact text unless the user explicitly requests another artifact
language.

For a documentation set, define a shared style prompt and an asset-specific
content prompt. Do not blindly reuse one composition for every subject.

For edits:

```text
Use case: precise-object-edit
Change only: <one label, arrow, box, or object>
Exact replacement: "<verbatim text>"
Preserve: every other label, arrow, panel, color, spacing, and dimension
```

Shorten text when repeated precise edits fail. Preserve meaning and move full
detail to the body.

## Inspection and iteration

Check every output for:

- text spelling and capitalization;
- cropped or squeezed labels;
- accidental duplicate components;
- missing response arrows;
- incorrect arrowheads;
- visual zones that imply wrong ownership;
- status and field names;
- unsupported fixed values;
- icon semantics;
- agreement with prose and any other visual form present;
- contrast and readability at normal documentation width.

When an error appears:

1. verify the correct fact again;
2. request one precise edit;
3. preserve all other invariants;
4. inspect the result again;
5. reject the variant if unrelated drift appears.

Do not keep an image merely because generation was expensive.

## Asset integration

- Use stable, descriptive, lowercase filenames.
- Match existing repository asset placement.
- Add meaningful alt text describing the concept, not “diagram”.
- Place the image where the reader first needs the mental model.
- Keep exact detail in prose/tables and use the image for relationships.
- Retain correct existing Mermaid when it remains useful; do not add a parallel
  Mermaid counterpart to every imagegen asset.
- Verify every reference and scoped orphan after renames or deletions.
- Record final dimensions as an observation, not a conformance target, unless
  the user specified a target.
