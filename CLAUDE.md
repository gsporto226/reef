# Reef workspace

## Architecture decisions

Always follow the ADRs in `docs/adr/`. They are binding. Read the relevant ones
before changing code. To deviate from an ADR, first write a new ADR that
supersedes it and get it agreed; never silently work around one.

## Agent skills

### Issue tracker

Issues and specs live in GitHub Issues on `gsporto226/reef` (`gh` CLI). See `docs/agents/issue-tracker.md`.

### Triage labels

The five default roles, each label named after its role (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: root `GLOSSARY.md` and `docs/adr/`. See `docs/agents/domain.md`.
