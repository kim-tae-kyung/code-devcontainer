# Validation and handoff

## Contents

- Validation layers
- Link and source checks
- Diagram and image checks
- Consistency checks
- Final report

## Validation layers

Run checks in increasing scope:

1. syntax and whitespace;
2. Markdown style;
3. local links and anchors;
4. image references and scoped orphans;
5. Mermaid parsing and rendering;
6. image decoding and visual inspection;
7. pinned external source verification;
8. cross-document semantic consistency;
9. repository-specific tests.

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

## Diagram and image checks

For Mermaid:

- extract every block;
- run a parser;
- render each block to SVG or PNG;
- use an independent renderer if the local environment fails for a non-syntax
  reason;
- report parser failures separately from renderer/environment failures.

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
- old terminology and out-of-scope concepts.

When generated schemas and executable routes can drift, independently calculate
both sets and compare them. Do not copy an existing count from the document.

## Final report

Lead with the outcome. Include:

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
- imagegen built-in or fallback mode.

### Validation

Report commands or check categories and exact results:

- files scanned;
- local link/anchor errors;
- external source links checked;
- Mermaid pass count;
- image reference/orphan count;
- image visual review;
- linter/test status.

### Residual risk

Identify remaining source ambiguity, generated-text maintainability, unavailable
integrations, or checks that were blocked.

Do not claim a clean result if validation skipped a required layer.
