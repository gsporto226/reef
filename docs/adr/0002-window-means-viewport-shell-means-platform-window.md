---
status: accepted
---

# "Window" means a buffer viewport; "shell" means the platform window

The windowing spec (`packages/reef/docs/specs/2026-09-02-windowing-design.md`)
called the buffer viewport a "pane" and the platform window an "OS window".
Shipped code already names the viewport `ReefWindow`, and the blueprint
follows neovim, where a window shows a buffer. We keep the neovim meaning:
**window** is the viewport, **shell** is the platform window, and "pane" is
retired. Each word has exactly one meaning, and no shipped API is renamed.

## Considered options

- **Rename `ReefWindow` to `ReefPane`, keep "OS window".** Rejected: it
  renames shipped API to fit a spec, and "window" would still mean two things
  in conversation.
- **Keep both terms and explain them in the glossary.** Rejected: it leaves
  `closeOsWindow` next to `ReefWindow` for every reader to untangle.

## Consequences

- Spec identifiers change before W1 code exists: `OsWindowId` → `ShellId`,
  `PaneId` → `WindowId`, `SplitPane` → `SplitWindow`, `FloatPane` →
  `FloatWindow`, `OsWindowHost` → `ShellHost`, `PaneHost` → `WindowHost`, and
  so on through the spec.
- The multi-window spike's `WindowHost` (opens platform windows) becomes
  `ShellPlatform`, freeing `WindowHost` for the viewport container and
  `ShellHost` for the shell container.
