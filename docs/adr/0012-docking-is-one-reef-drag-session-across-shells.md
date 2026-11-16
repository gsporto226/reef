---
status: accepted
---

# Docking is one reef drag session across shells

Apps built tab, pane and buffer drag and drop by hand with Flutter's
`Draggable`. Each app wired its own drop handlers, and none could drop into
another platform window, because `Draggable` stops at its view. Reef core
now owns docking: one module next to `WindowingRoot`, used by the default
projections.

## Decision

- What can be dragged is a sealed `Dockable`: a tab or a window. `DockSource` makes any widget a drag handle for one.
  `DockArea` declares a drop zone: a tab strip position, a window edge or
  centre, an empty tab, a float layer.
- A drop resolves to one batch of existing windowing commands (`MoveTab`,
  `MoveWindow`, `DockWindow`, `FloatWindow`, `SplitWindow`, `PushBuffer`,
  `NewTab`, pop-out). It goes through `dispatchAll`, so the interceptor sees
  it and it is one undo step. Docking adds no new commands and no new doc
  state.
- A drag is a reef drag session, not a Flutter `Draggable`. Reef tracks the
  pointer in screen coordinates and hit-tests the `DockArea`s of every shell,
  so a drag can end in another platform window. A drop on no area pops a tab
  or window out into a new shell where pop-out is supported, and is
  cancelled otherwise.
- While a drag hovers an area, reef asks the interceptor about the batch it
  would dispatch, without dispatching it, and the area shows whether the
  drop is allowed. A drop the interceptor vetoes changes nothing.
- A window dropped on another window's centre works like a link dropped on a
  page: the target pushes the dragged window's current entry, and the dragged
  window closes. Back on the target returns to its old page. When the
  target already shows that page, the dragged window only closes.
- A shell may lose its last tab, by close or by dock. The shell then closes,
  unless it is the last shell, which keeps one empty tab. This supersedes
  the spec's "a shell's last tab never closes" (§6, §10).
- The default projections wrap tab strips, windows and empty tabs in
  `DockArea`s and their handles in `DockSource`s.

## Considered options

- **Keep `Draggable` per app; a drop outside the view pops out.** Rejected:
  moving into an existing platform window stays menu-only, and every app
  rewrites the drop mapping.
- **A separate `reef_docking` package.** Rejected: the default projections
  need it, and it only composes core commands.
- **An `IDockable` interface that widgets implement.** Rejected: reef keeps
  the `I` prefix for value interfaces like `ILocalizable`; the dragged thing
  is data, so a sealed payload fits.

- **Centre drop swaps the two windows** (tiling window managers). Rejected:
  browsers navigate the target page instead, which is what users expect.

## Consequences

- The interceptor gains a dry-run use. An interceptor must be a pure
  function of the doc and the command, which §6 already implies.
- A dock that closes a shell clears the undo timeline, as every shell
  change does today, so it can't be undone.
- Buffer drags (links, bookmarks) keep their current behaviour. `Dockable`
  starts with tabs and windows only.

- Reef needs screen-space pointer tracking across views on each
  `ShellPlatform`. `FakeShellPlatform` must simulate it so apps can test
  cross-shell drops without the windowing flag.
- The glossary's **Dock** widens from floating windows to tabs, windows and
  buffers.
