# Validation and handoff

## Contents

- Validation layers
- Link and source checks
- Fixed Mermaid and image checks
- Consistency checks
- Final report

## Validation layers

Run checks in increasing scope:

1. syntax and whitespace;
2. Markdown style;
3. local links and anchors;
4. image references and scoped orphans;
5. scoped Mermaid fixed-version rendering when Mermaid is present;
6. image decoding and visual inspection;
7. pinned external source verification;
8. cross-document semantic consistency;
9. operating-contract conformance;
10. checks relevant to changed documentation and required repository gates.

Start with:

```bash
python3 <skill-dir>/scripts/validate_docs.py <markdown-root>
```

In a Git worktree, also run `git diff --check`.
Add `--asset-root` for each owned asset tree. Use `--check-orphans` only when
the Markdown scan covers every legitimate consumer of that asset tree.

Run the repository's Markdown linter with its configuration. If a rule is
intentionally disabled, report it rather than hiding the exception.

## Link and source checks

Check:

- relative Markdown targets;
- generated heading anchors and duplicate headings;
- image targets;
- versioned external URLs;
- file and line anchors in the pinned source checkout;
- renamed or deleted documents and assets.

For versioned repository links, prefer validating against the local pinned
checkout. This separates a real missing path from authentication, rate limit,
or network blocking.

For live official sites:

- use HEAD only when the server supports it;
- fall back to GET without downloading unnecessary large bodies;
- record redirects;
- distinguish `403`/`429`/bot protection from `404`;
- do not report a blocked checker as proof of a broken link.

## Fixed Mermaid and image checks

For Mermaid:

- read [mermaid-validation.md](mermaid-validation.md);
- render added or changed blocks by default;
- render every block only for a new set, full audit, shared Mermaid
  configuration change, release gate, or explicit user request;
- use the bundled fixed `@mermaid-js/mermaid-cli@11.16.0` runner with one job;
- treat a successful fixed-version render as the syntax/parser check;
- inspect the generated contact sheet, then suspicious originals at full
  detail;
- supply an existing browser portably instead of using architecture-specific
  installation or ad hoc renderer experiments;
- report syntax failures separately from browser/environment failures.

For raster assets:

- verify file type and dimensions;
- decode/open every final file;
- inspect at original detail;
- check text, cropping, arrows, ownership, status, and repeated objects;
- compare every image to the current prose and exact source facts.

Do not consider an image valid merely because a file exists.

## Consistency checks

Search the entire documentation set for:

- stale version pins;
- inconsistent endpoint roots, methods, and parameter names;
- provider/admin/viewer/tenant role drift;
- singular/plural request-field drift;
- status names used in the wrong resource domain;
- readiness and deletion conditions that disagree;
- retries with no owner;
- forward dependencies that do not match reverse cleanup;
- deployment values presented as constants;
- external systems described as product-owned components;
- control paths presented as live data paths;
- old terminology and out-of-scope concepts;
- unrequested prior behavior or transition history;
- environment observations presented as durable assumptions;
- external tool, API, configuration, or version claims without official links;
- must-know pitfalls buried in prose instead of a brief linked **Known Issue**.

When generated schemas and executable routes can drift, independently calculate
both sets and compare them. Do not copy an existing count from the document.

## Final report

Lead with the outcome. Keep the report compact, state assumptions explicitly,
and include only the applicable sections below. Do not add a preamble, restate
the request, or recap information already available from linked sources.

### Confirmed model

Summarize the subject's actors, boundaries, contracts, state ownership, and
observable completion model.

### Documentation changes

List files created, rewritten, retained, moved, or deleted. Identify the
authoritative home of major concepts.

### Technical corrections

Prioritize corrections that affect API contracts, security, state, data flow,
failure behavior, or operator decisions.

### Uncertainty

List `Inference`, `Deployment-dependent`, and `Open verification` items with
the reason direct evidence cannot select one answer.

### Visual decisions

For every visual, report:

- retain/edit/regenerate/delete/add;
- final path;
- purpose;
- major corrections;
- final prompt or prompt-set identifier;
- imagegen generation mode.

### Validation

Report commands or check categories and exact results:

- files scanned;
- local link/anchor errors;
- external source links checked;
- Mermaid selected scope, CLI version, browser mode, and pass count;
- image reference/orphan count;
- image visual review;
- linter/test status.

### Residual risk

Identify remaining source ambiguity, generated-text maintainability, unavailable
integrations, or checks that were blocked.

Surface any must-know residual risk as a brief **Known Issue** with a direct
official or primary-source link.

Do not claim a clean result if validation skipped a required layer.
