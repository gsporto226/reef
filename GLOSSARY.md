# Reef

Reef is a Flutter app framework whose navigation model follows neovim: buffers
hold state, windows show buffers, tabs arrange windows, shells host tabs.

## Windowing

**Shell**:
A platform window: the top-level surface the operating system draws, hosting an
ordered stack of tabs. Exactly one is focused; the last one never closes.
_Avoid_: OS window, platform window, native window

**Tab**:
The arrangement of windows that fills one shell; the unit a user switches
between. A tab may be empty (no tree windows).
_Avoid_: workspace, page, screen

**Window**:
A viewport that shows one buffer, either as a slot in its tab's tree or
floating above a shell, tab, or window. Never empty: it always shows a buffer.
_Avoid_: pane, view, split, viewport

**Floating window**:
A window that lives in an overlay instead of its tab's tree, scoped to one
shell, tab, or window and ordered by z-index. Not a separate kind of window.
_Avoid_: floating pane, panel, popup

**Window history**:
A window's own back and forward stacks of buffers around the one it currently
shows.
_Avoid_: navigation stack, back stack

**Buffer**:
One keyed instance of a page's state. Many windows can show the same buffer and
stay in sync; a buffer outlives any single window.
_Avoid_: document, page state, instance

**Split**:
Dividing a window's slot so a new window sits beside it. The new window shows
the original's buffer unless another buffer is given, inherits its window
history, and takes focus.
_Avoid_: duplicate, clone

**Dock**:
Dropping a dragged tab or window onto a dock area: a tab strip
position, a window's edge or centre, an empty tab or a float layer. A
floating window docked beside a target joins that tab's tree; into an empty
tab, it becomes the whole tree.
_Avoid_: attach, pin

**Dockable**:
A tab or window that the user can drag to dock it somewhere.
_Avoid_: draggable, IDockable

**Dock area**:
A place that accepts a dock, in any shell.
_Avoid_: drop zone, drop target

**Attach (shell)**:
Adding a new shell to the windowing state, holding one empty tab, and focusing
it. Not Dock: attach brings a new container into existence; dock moves an
existing window into a tab's tree.
_Avoid_: open, spawn

**Attach (buffer)**:
Pointing a window at a buffer with a fresh window history, dropping its back
and forward stacks. Not Dock, which moves windows, not buffers.
_Avoid_: load, bind

**Link**:
A path, with optional query arguments, that points at a buffer, such as
`/tasks/42/edit`, and the typed route value it stands for. Opening a link
focuses a window that shows the buffer or opens it, as the link policy decides.
_Avoid_: deep link URL

**Link tree**:
The app's declaration of every link and how they nest: a child link extends
its parent's path and query. It replaces the link table.
_Avoid_: route table, router config

**Fresh link**:
A link that opens a new buffer each time, as a browser tab does, instead of
reaching the buffer already open for the same path.
_Avoid_: draft

**Guard**:
A rule on a link tree node that allows or redirects opening a link at
or below that node.
_Avoid_: middleware, route guard

**Link table**:
Replaced by the link tree (ADR 0004).
