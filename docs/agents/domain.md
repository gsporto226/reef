# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

- **`GLOSSARY.md`** at the repo root.
- **`docs/adr/`**: read ADRs that touch the area you're about to work in. ADRs are binding (see `CLAUDE.md`).

If any of these files don't exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The `/domain-modeling` skill (reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates them lazily when terms or decisions actually get resolved.

## File structure

Single-context repo. The Dart workspace has several packages, but they share one domain and one glossary:

```
/
├── GLOSSARY.md
├── docs/adr/
│   ├── 0001-three-layer-tests-merged-coverage.md
│   └── 0002-window-means-viewport-shell-means-platform-window.md
├── packages/        ← reef, reef_router, reef_fp, reef_utils, reef_widgets
└── apps/            ← integration apps (docs/integration-apps.md)
```

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `GLOSSARY.md`. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal: either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0002 (window means viewport), but worth reopening because…_
