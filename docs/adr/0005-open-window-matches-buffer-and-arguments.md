---
status: accepted
---

# An open window matches on buffer and arguments, and the verb decides the rest

Supersedes the matching rule in ADR 0004 D1 ("Matching an open window compares
the buffer only"). The rest of D1 still holds.

With buffer-only matching, a link to `/search?q=y` while `/search?q=x` is open
focused the old window and dropped `q=y`. Arguments are page state, but a user
who asked for different page state expects to get it.

## Decision

An open window matches a link only when its current entry has the same buffer
**and** the same arguments. A match focuses that window. When only the buffer
matches, the verb decides:

| Verb | Same buffer, different arguments |
|---|---|
| go / open link | opens another window |
| push | pushes a new entry in the focused window |
| replace | replaces the current entry, with the new arguments |
| new tab, split, new window | always open, as before |

A history entry's id is created with the command, not in the reducer, so the
reducer stays pure and replay and undo are deterministic.

## Consequences

- The same buffer can be open in two windows with different arguments.
- Browser back and forward (ADR 0004 D2) can rely on the id carried by the
  command.
