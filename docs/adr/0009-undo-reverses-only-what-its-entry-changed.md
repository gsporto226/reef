---
status: accepted
---

# Undo reverses only what its entry changed

Supersedes spec §4's "snapshots, not inverse commands" for the windowing
host. `BufferUndoHost` is unchanged.

A windowing entry holds the whole doc before and after its batch. Undo
publishes the "before" doc, so every change made since that entry and not
recorded (navigation, focus, arguments) is lost too. In the browser, Ctrl+Shift+T
after browsing in another tab rewinds that tab.

## Decision

- A windowing entry still records `before` and `after` docs. Undo computes
  the **patch** between them, the shells, tabs, windows, floating entries
  and focus the batch touched, and applies its reverse to the **current**
  doc. Redo applies the patch forward.
- Units the batch did not touch keep their current state. A unit the batch
  touched comes back as it was in `before`, including the window histories
  it held, so a reopened tab returns with its history.
- **Conflict:** if a later unrecorded change removed or moved a unit the
  reverse patch needs (its parent tab or shell is gone), undo falls back to
  publishing the whole `before` doc, as today. The result always satisfies
  the doc invariants; the reducer validates it.
- Undo stays synchronous and total.

## Considered options

- **Keep whole snapshots.** Rejected: browser undo loses work.
- **Replay unrecorded changes onto the old snapshot.** Rejected: it means
  recording navigation after all, which §4 rules out.
- **Inverse commands.** Rejected: every command would need a hand-written
  inverse; diffing two docs is one function.

## Consequences

- One pure function, `diff(before, after)` plus `apply(patch, doc)`, tested
  in isolation, carries the change.
- Undo of a layout change no longer resets navigation done since.
