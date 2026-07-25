# Research and evidence

## Contents

- Source contract
- Existing-document audit
- New-document discovery
- Claim matrix
- Cross-layer tracing
- Citations and uncertainty

## Source contract

Establish the evidence contract before research:

- exact repository, product, service, or standard;
- version, tag, branch, commit, release date, or API version;
- included and excluded systems;
- target reader and decisions the documentation must support;
- acceptable inference level;
- required official links and permanent source URLs.

Use this default evidence order unless the subject requires another:

1. executable code, runtime handlers, controllers, reconcilers, and state
   machines;
2. public schemas, protocols, API descriptions, and database constraints;
3. tests, fixtures, and recorded runtime behavior;
4. official documentation for the same revision;
5. examples, generated clients, CLI help, and comments;
6. constrained inference.

For non-code subjects, translate the same principle to the nearest primary
evidence: statutes and regulations over summaries, specifications over blog
posts, first-party product docs over aggregators, and original research over
secondary reporting.

When sources disagree, record:

- the conflicting claims;
- which source controls actual behavior;
- whether the conflict is version-specific;
- the user-visible consequence;
- whether the disagreement should remain documented.

## Existing-document audit

Before editing an existing set:

1. Inspect the worktree and preserve existing changes.
2. Enumerate Markdown, MDX, diagrams, images, generated references, and linked
   source files.
3. Extract important claims:
   - actors and ownership;
   - API calls and inputs;
   - state transitions;
   - storage and security claims;
   - call and packet direction;
   - retry, timeout, failure, cleanup, and deletion behavior;
   - fixed values and deployment assumptions.
4. Record every visual claim separately from the prose. Images can contradict
   correct text.
5. Inspect whether links directly prove their adjacent claims.
6. Mark duplicated concepts and choose an authoritative location.

Do not make broad edits until the matrix shows which statements survive.

## New-document discovery

For a new documentation set:

1. Inventory source entry points:
   - top-level packages/modules;
   - API route registration;
   - schemas and models;
   - workflows/jobs;
   - controllers and state machines;
   - integration clients;
   - configuration;
   - tests;
   - deployment manifests;
   - official conceptual docs.
2. Build a domain/resource list from behavior, not directory names alone.
3. Identify the main reader journeys:
   - setup or prerequisites;
   - create/update/delete;
   - request-to-effect flow;
   - steady-state data flow;
   - observation and troubleshooting;
   - failure and recovery.
4. Draft an information architecture and test it against the source inventory.
5. Draft only after every major chapter has direct evidence candidates.

## Claim matrix

Use a spreadsheet, scratch Markdown, database, or structured text outside the
repository. Track at least:

| Field | Purpose |
| --- | --- |
| Claim | One falsifiable statement |
| Target location | Document and section |
| Public contract | API/schema/specification |
| Entry point | Handler, command, event, or trigger |
| Orchestration | Workflow, queue, job, or transaction |
| Internal API | RPC/function/module boundary |
| Persistence | Desired, observed, history, or cache state |
| Reconciliation | Controller/state machine and retry owner |
| External effect | Device, service, user, or packet effect |
| Completion | Exact success/readiness condition |
| Failure | Exact error/stale/partial state |
| Evidence | Direct links or local source paths |
| Level | Confirmed, Inference, Deployment-dependent, Open verification |
| Action | Keep, correct, remove, expand, or split |

Split compound claims. “The API creates a network and retries until ready” is
usually several claims with different owners and evidence.

## Cross-layer tracing

Trace both forward and reverse paths.

Forward control example:

```text
caller
→ authentication and authorization
→ handler
→ transaction or workflow
→ internal API
→ desired state
→ reconciler
→ external effect
→ observed state
→ public status/history
```

Data path example:

```text
source endpoint
↔ local enforcement/translation
↔ physical or logical transport
↔ remote enforcement/translation
↔ destination endpoint
```

Reverse lifecycle example:

```text
delete acknowledgement
→ dependency drain
→ isolation
→ external cleanup
→ state deletion
→ validation
→ reusable/absent projection
```

Confirm which layers are actually skipped. Do not route every operation through
the most common workflow.

Use source search strategically:

- route registration before individual handlers;
- enum/model definitions before prose status tables;
- call sites before interface comments;
- tests for conflict, retry, and partial failure behavior;
- configuration defaults and deployment overlays before claiming fixed values;
- delete handlers and reference checks before documenting cleanup order.

## Citations and uncertainty

Prefer:

- permanent versioned source links;
- the narrowest file or line range proving the statement;
- primary official docs for behavior not visible in code;
- multiple independent layers for important lifecycle claims.

Avoid:

- linking a repository root for a precise claim;
- citing comments that runtime code contradicts;
- treating generated OpenAPI or clients as authoritative when route code
  differs;
- claiming that a test fixture's value is a product constant.

Use uncertainty labels precisely:

- **Inference**: evidence supports the conclusion but no direct contract states
  it.
- **Deployment-dependent**: configuration, topology, capability, provider, or
  environment selects the behavior.
- **Open verification**: pinned evidence is inconsistent or insufficient.

State what is unknown and why. Do not replace uncertainty with a proposed
design unless the user asked for design work.
