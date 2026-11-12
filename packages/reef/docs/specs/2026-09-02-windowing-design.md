# Reef windowing design

Status: accepted design, 2026-09-02. Vocabulary per ADR 0002 (2026-11-07). Replaced the earlier split-tree feature
and the per-tab router projection in `reef_auto_route`; both were deleted in
W0, not migrated (§12).

## 1. Vocabulary and goals

Reef's navigation model borrows four abstractions from neovim: buffers hold
state, windows show buffers, tabs arrange windows, shells host tabs. The
abstractions stay. The vim command idioms do not; the framework exposes
app-native intents only.

| Entity | Meaning | Identity |
|---|---|---|
| shell | a platform window; hosts a stack of tabs | `ShellId`, uuid v7 |
| tab | fills one shell; the unit users switch between | `TabId`, uuid v7 |
| window | subdivides a tab's canvas, or floats over any container | `WindowId`, uuid v7 |
| buffer | the content a window draws; one buffer can back many windows | `BufferId` (existing, blueprint §4.4) |

Goals:

1. One canonical windowing state in reef core. Projections render it per
   platform and are presentation only. Which projection runs is a dynamic
   choice (app or user decides); reef ships a default policy.
2. Every surveyed windowing style is reachable with minimal effort: tiling
   splits, tabbed documents, one-buffer-many-views, pop-out shells, mobile
   stacks, master-detail, tmux-style detach/reattach, floating panels.
3. The framework provides state, intents, and composable units. It never
   enforces chrome. No forced tab bar, no forced look.
4. Layout survives form-factor changes, pop-outs, and app restarts.

Non-goals: shipping UI chrome; locking apps to a router; buffer content
concerns (the quartet and hibernation own those); streams (reef principle 1);
a cross-isolate protocol (one engine, one isolate; blueprint §10.4).

## 2. Canonical state

New feature folder `features/windowing/` in reef core. The state is one
immutable, id-normalized document. Flat maps with id references; no nesting.

```
WindowingDoc
  shells:  Map<ShellId, ShellState>   // ordered tabIds, activeTabId
  tabs:       Map<TabId, TabState>             // windowId, window tree root, activeWindowId
  windows:      Map<WindowId, WindowState>           // history per window
  floating:   Map<WindowId, FloatingState>       // scope, zIndex, geometry hint
  focusedShellId: ShellId

WindowState
  history: BufferHistory { back: List<BufferId>, current: BufferId, forward: List<BufferId> }

Membership is structural: a window appears in its tab's window tree (tree window)
or in the floating map (floating window). No parent field to keep in sync.

FloatingState
  scope: ShellId | TabId | WindowId           // which container's overlay hosts it
  zIndex: int
  geometryHint: (optional, advisory)
```

Rules:

- Ids are extension types over `String`, uuid v7, the `BufferId` recipe.
- Buffers are not in the doc. The doc references `BufferId`s; the buffer
  registry and hibernation store own buffer existence (blueprint §10.2).
- One buffer, many windows: several windows may reference the same `BufferId`.
  Live sync comes from the family-viewmodel contract, free of charge.
- A window is either a tree window (a leaf slot in its tab's window tree) or a
  floating window (a member of a container's overlay, ordered by `zIndex`).
  Floating windows are uniform windows, not a separate kind; the same
  `WindowState` serves both.
- A window is never empty: `BufferHistory.current` is required. A tab can
  be empty: closing or floating its last tree window leaves the tab with
  no tree. The reducer never cascades upward. A `focusPolicy` that wants
  the tab gone appends a `CloseTab` to the triggering batch (§6). Appended
  commands pass through the interceptor like any other.
- Invariants, enforced in the reducer: every tab belongs to exactly one
  shell; a shell's `tabIds` order is the tab strip order; window trees
  partition tree windows per tab; each floating window has exactly one scope;
  the focused chain is shell → its active tab → its active window; the last
  shell can never be closed; doc changes that alter the shell set
  are undo barriers (§4).

## 3. Commands and the reducer

All mutations go through sealed commands. A pure reducer maps
`(doc, command) → doc`. Commands carry pre-generated ids for entities they
create, so dispatch stays synchronous and pure, and effects reference stable
ids.

| Group | Commands |
|---|---|
| Tabs | `NewTab` (optional initial buffer, creates the tab's first window), `CloseTab`, `MoveTab`, `ActivateTab` |
| Tree windows | `SplitWindow` (optional buffer, defaulting to the split window's; the new window copies the window history and takes focus), `CloseWindow`, `MoveWindow` (to any tab tree in any shell), `ResizeWindow` |
| Floating | `FloatWindow`, `DockWindow` (target window + axis + side; becomes the tree root in an empty tab; drops the geometry hint), `RaiseWindow`, `MoveFloating` (sets the advisory geometry hint, a rectangle in the scope's space) |
| Buffer content | `AttachBuffer`, `PushBuffer`, `PopBuffer`, `ReplaceBuffer`, `NavigateForward` |
| Focus | `ActivateWindow`, `ActivateShell` |
| shells | `AttachShell`, `CloseShell` |

Dispatch semantics:

- A command invalid in the current state (moving the last tab out of a
  shell, closing a nonexistent window) returns the doc unchanged. Callers
  that care can diff or ask first; nothing throws across the API.
- `dispatchAll` applies a batch atomically with one publish. A move is
  remove + insert in one batch. A batch is one undo unit (§4).
- Controller methods (`splitWindow(...)`, `moveTab(...)`) construct and
  dispatch commands. Pages call methods; the command record exists for the
  undo timeline and the audit log, not for ceremony.
- Platform intents are async controller methods and the only impure edge.
  `openShell({BufferId? buffer})` and `popOutTab(TabId)` return
  `Future<Result<ShellError, ShellId>>` and open the real shell first, then
  dispatch the batch (`AttachShell`, the tab, close the placeholder tab) on
  success, so the doc never claims a shell that does not exist. A batch the
  doc would refuse fails with `refused` before any real shell opens; the batch is
  all or nothing: if an interceptor keeps it from landing whole, nothing is
  published and the real shell it opened closes. `closeShell` keeps
  its signature: it dispatches first, and every shell that leaves a
  published doc has its real shell closed best-effort. Without a platform, or
  where it is unsupported, the open intents return `unsupported` and the doc
  stays untouched.

## 4. Undo

One app-scoped `UndoController` owns one global timeline. Subsystems do not
keep their own stacks; they submit entries. Entries are data only.

```dart
class UndoEntry<S> {
  final ILocalizable label;      // audit log only, not a controller listenable
  final S snapshotBefore;        // reverses
  final S snapshotAfter;         // replays
  final Object? coalesceKey;
}

abstract interface class UndoHost<S> {
  void undo(S snapshotBefore);
  void redo(S snapshotAfter);
}

class UndoController {
  void registerHost<S>(UndoHost<S> host);
  void record<S>(UndoEntry<S> entry);       // truncates the redo tail, coalesces by key
  void undo();                              // sync, total; caller consults $canUndo
  void redo();
  ValueListenable<bool> get $canUndo, $canRedo;
}
```

Semantics:

- Snapshots, not inverse commands. `undo()` moves a pointer and republishes
  a snapshot. Total function; no failure modes (§4 in reef principle 3 does
  not apply: nothing here is fallible).
- Type safety: `registerHost<S>` and `record<S>` key the internal map by the
  reified type argument. The one downcast happens inside the controller.
  Snapshot types are named classes (`WindowingDoc`, `BufferSnapshot`);
  denotable type arguments are a stated requirement.
- One entry per `dispatchAll` batch. Changes to focus or window history
  alone (navigation, §8) update state without recording; window history is
  not an edit. Consecutive batches sharing a `coalesceKey` merge into one
  entry (resize drags).
- Undo history resets when the shell set changes (§2 barriers). Layout
  undo never crosses a pop-out.
- Bound: last 64 entries, in memory only. The doc hibernates; history does
  not survive restarts.
- Labels live on entries for the audit log. Menus render generic
  Undo/Redo. Labeled menus can be added later as one listenable without
  rework.

Roles:

| Role | Who | Job |
|---|---|---|
| Controller | reef provides; app instantiates once (keepAlive provider) | history, coalescing, dispatch by type |
| Host | the subsystem that owns the state | publish a snapshot back into its own state |
| Recorders | subsystem mutation paths | submit entries at recorded mutations |
| Consumers | shortcuts, menus, dev tools | call undo/redo, read `$canUndo`/`$canRedo`; never see hosts or entries |

Reef ships two hosts. `WindowingUndoHost` (keyed `WindowingDoc`) publishes
doc snapshots; the windowing dispatcher records one entry per batch.
`BufferUndoHost` (keyed `BufferSnapshot`, a uniform `bufferId + model`
record) publishes models through the owning viewmodel; viewmodels opt in
with an `UndoableModel` mixin. Models are already immutable freezed
snapshots, so content entries carry the previous and next model directly.
Since entries carry full snapshots, undoing a content edit works even if
that buffer hibernated and rematerialized in between. Focused text fields
consume Ctrl+Z before the shell binding sees it (Flutter convention);
field-level undo stays Flutter-owned.

## 5. Rendering

Design-free units over `package:flutter/widgets.dart`. State flows down
through `WindowingScope` (inherited lookup of the controller and the buffer
builder); mutations go back through controller intents.

`WindowingRoot(controller:, bufferBuilder:, delegate:, child:)` is the entry
point. The buffer builder is the app's buffer-to-page mapping:

```dart
typedef BufferBuilder = Widget? Function(BuildContext context, BufferId buffer);
```

`WindowHost` calls it for its window's current buffer; the page reads its
window id with `WindowHost.of(context)`. Returning null means the buffer is
not ready, and the window shows the delegate's `hibernatingBuilder`. The
example app passes its kind-to-page mapping (`bufferPageFor`: the `kind`
prefix of a `kind:token` id picks the page). Units take ids, never objects, so the same
widget renders whatever the doc says and projection switches re-run
assembly over an unchanged doc.

Containers. Each container renders its content with its own `FloatingLayer`
stacked above it.

| Unit | Renders | Floating layer hosts |
|---|---|---|
| `ShellHost` | active tab's canvas; dev supplies shell chrome via `surfaceBuilder` | shell-scoped floating windows, above the chrome too |
| `TabCanvas` | the tab's window tree (Flex recursion), resize handles, `windowArrangement` | tab-scoped floating windows |
| `WindowHost` | the window's `ReefWindow`, focus ring slot | window-scoped floating content |
| `TabStripSlot` | headless tab data: tabIds, activeTabId, activate/close/reorder callbacks | dev renders the look |
| `FloatingLayer` | a container's floating windows in a `Stack` layer above the container's content, ordered by `zIndex`, each wrapped in the dev's positioning widget | |

`windowArrangement` decides how a tab's windows manifest: `flexTree` (desktop
default), `focusedOnly` (compact default), or a custom builder. Drag-resize
ships as `WindowResizeHandle`, emitting `ResizeWindow` intents coalesced under
the undo key `resize:windowId`, so one drag is one undo step.

Projections:

```dart
typedef WindowingProjection = Widget Function(
    BuildContext context, WindowingController controller, ShellId shellId);
typedef WindowingProjectionPolicy = WindowingProjection Function(
    BuildContext context, WindowingController controller, ShellId shellId);
```

Two reference assemblies ship as widgets: `DesktopProjection` (one
`ShellHost` per doc shell, optional tab strip, `flexTree` canvas) and
`TabbedProjection` (single shell, dev tab bar via `TabStripSlot`,
`focusedOnly` canvas). `defaultWindowingProjection` resolves via
`screenTypeOf`: expanded → desktop, medium/compact → tabbed. Apps replace
the policy, start from a shipped projection and swap slots, or compose
containers directly under their own `surfaceBuilder`. Three depths, one
contract.

Rebuild discipline: units consume per-entity selectables, so activating a
tab rebuilds that tab's slot, not the tree.

`WindowingShortcuts` is an opt-in unit with standard default bindings
(close window, split, navigate back/forward, undo/redo). Keybinding is app
chrome; the unit exists so nobody rewires the obvious keys by hand.

## 6. Delegates

One `WindowingDelegate` bundle, handed to `WindowingRoot`, distributed via
`WindowingScope`, overridable per subtree by nesting
`WindowingDelegateScope(delegate.copyWith(...))`.

Visual hooks (each with a framework default):

| Hook | Default | Example override |
|---|---|---|
| `projectionPolicy` | screen-class resolution | user preference "always tabs" |
| `windowArrangement` | `flexTree` / `focusedOnly` by screen class | window carousel on tablet |
| `tabStrip` | headless slot defaults | segmented control, overflow menu |
| `splitter` | thin draggable divider | thick themed handle, double-click maximizes |
| `windowChrome` | border when focused | window headers with titles and close buttons |
| `floating` | plain entry wrapper | draggable panels with snap and minimize |
| `labels` | none | entity to `ILocalizable` ("Task: Buy milk") |
| `emptyBuilder`, `hibernatingBuilder` | blank / spinner | branded states |

Behavioral hooks:

- `interceptor`, runs in the controller before dispatch:

```dart
sealed class CommandDecision {
  const factory CommandDecision.approve() = _Approve;
  const factory CommandDecision.veto(ILocalizable reason) = _Veto;
  const factory CommandDecision.replace(WindowingCommand command) = _Replace;
}
```

  Enables confirm-before-close (the veto Flutter's `onWindowCloseRequested`
  lacks), policy limits (max windows per tab), and smart routing. Veto
  reports the failure and leaves the doc untouched. Replace rewrites the
  command before the reducer sees it, e.g. a horizontal split into a
  vertical one.
- `openPolicy`: how `controller.openBuffer(buffer)` compiles into one
  batch of commands (§8).
- `focusPolicy`: what close, split and back do to focus. The controller
  runs it after each command of a batch and appends the commands it
  returns to that batch, so they reach the interceptor and land in the
  same undo step. Options: `splitTakesFocus` (default true),
  `closeEmptyTab` (default false; a shell's last tab never closes),
  `focusAfterClose` (default none: the reducer's neighbour) and
  `emptyBack` (§8).
- `linkPolicy`: what a resolved link does (§9).

`interceptor`, `openPolicy`, `focusPolicy` and `linkPolicy` are also
`WindowingController` constructor parameters. A non-null value on the
delegate replaces the controller's while `WindowingRoot` is mounted, and
the previous value comes back on unmount. A policy that must apply before
the root mounts, such as for a launch link opened at start-up, goes to the
controller constructor.
- `persistence`: what the hibernation record keeps. Unlike the other hooks
  it is a `WindowingController` constructor parameter next to the store,
  because restore happens before any widget mounts: a doc-to-doc transform
  applied before saving (default: the whole doc). The controller's `extra`
  is an app-owned JSON value saved next to the doc and restored with it
  (default: none), e.g. the projection choice.

Non-overridable core: doc invariants (reducer), the command set, the undo
timeline, buffer live sync. Delegates work through the pipeline
(intercept, replace, parameterize). They can make the system stricter or
smarter, never corrupt it.

## 7. Multi-window

The spike's `WindowHost` seam became `ShellPlatform` in reef core, and the
`reef_multi_window` adapter package implements it. `RealShellPlatform`
quarantines the unstable Flutter-master API (`@internal` imports;
per-invocation `FLUTTER_WINDOWING=true` env override, never the global config
flag). `FakeShellPlatform` ships in reef core so apps can test their pop-out
flows without the flag.

```dart
abstract interface class ShellPlatform {
  bool get isSupported;                                // false on single-shell platforms
  Future<Result<ShellError, Unit>> open(ShellId id);   // create a real shell for that doc shell
  void close(ShellId id);                              // best-effort destroy
}
```

`ShellError` has a kind (`unsupported`, `refused`, `platformFailure`) and an
optional cause. An app hands its platform to
`WindowingController(platform: ...)`.

- Ordering is deliberately asymmetric. Create is platform-first: `openShell`
  and `popOutTab` open the real shell, then dispatch the batch. The doc never
  claims a shell that does not exist. Close is doc-first: when a published
  doc has fewer shells than the one before, the controller calls
  `platform.close` for each shell that left. This covers `closeShell`, raw
  `CloseShell` commands and interceptor replacements. The doc is truth; a
  platform failure is a leak, recoverable by closing the real shell.
- View plumbing: `runWidget(ProviderScope(WindowingRoot(child:
  ShellViews(...))))`. `ShellViews` takes the controller, the
  `RealShellPlatform` and a `shellBuilder(context, shellId)`. It opens a real
  shell for each doc shell at mount and draws one view per open real shell,
  each with `shellBuilder` inside; apps draw the shell there with
  `ShellProjection(shellId)`. One scope sits above every view, so inherited
  lookups (including `WindowingScope`) cross view boundaries and every shell
  shares providers. Buffers stay plain shared state. Without multi-shell
  support `ShellViews` draws the focused shell inline in the implicit view,
  so one entry point serves every platform.
- `controller.capabilities.canPopOut` gates pop-out UI. On mobile and
  tablet the platform reports unsupported and pop-out UI hides; the
  doc still holds the one shell entity.
- The last shell can never be closed (reducer invariant). Closing the
  last real shell on desktop is the platform's app exit, outside the doc.
- Native close goes through the doc. With more than one shell in the doc,
  the platform close button calls `controller.closeShell(id)`: an
  interceptor can veto it and the shell stays open; otherwise the doc-first
  close destroys the real shell. Activating a real shell calls
  `controller.activateShell(id)`.
- Limitation: the platform close button on the last shell destroys it
  directly (app exit). No interceptor runs, so there is no confirm before
  quit.

## 8. Buffer navigation

Navigator semantics on top of the spatial model. Each window owns a history
in the doc (§2 `BufferHistory`): `back`, `current`, `forward`.

- `PushBuffer`: demotes current to back, clears forward, sets new current.
  The target is a `BufferId`.
- `ReplaceBuffer`: swaps current, stacks untouched.
- `PopBuffer` (back) and `NavigateForward`: mirror moves on the stacks.
- Both stacks are always tracked. Exposing forward is the dev's choice:
  mobile wires back only; desktop may bind Alt+Left/Right and mouse
  buttons.
- Pages open buffers with `controller.openBuffer(buffer)`, which
  dispatches what `openPolicy` returns as one batch. The default,
  `defaultOpenPolicy`, focuses a window of the focused shell's active tab
  that already shows the buffer, else pushes. Reef also ships
  `pushOpenPolicy` (push onto the active window), `splitBesideOpenPolicy`
  (a new window beside the active one, horizontal split) and
  `newTabOpenPolicy` (a new tab in the focused shell). Push and split give
  an empty tab its first window. There is no screen-class default: an app
  that wants a detail window on desktop picks `splitBesideOpenPolicy`
  itself.

Platform back = window back. `controller.back()` pops the focused shell's
active window and returns true. When that window history has nothing behind it, or no window
is active, `focusPolicy.emptyBack(doc)` decides: it returns the commands to
dispatch (handled), or null (returns false). Reef ships `emptyBackNothing`
(the default), `emptyBackCloseWindow` and `emptyBackUnhandled`. Back that
closes app-owned UI first (a drawer, an overlay) is the app's own
`didPopRoute`, falling back to `controller.back()`.
`WindowingSystemBack` is an opt-in widget that binds system back, such as
Android's back gesture, to `controller.back()`. Back it leaves unhandled
goes on to the platform, which can background the app. Browser back is a
different history with different rules (§9).

## 9. Deep linking

True URIs, browser-compatible. A deep link is a `BufferPath`: path segments
plus query arguments. It can arrive over any transport: the route
information (the browser URL on web), launch arguments on desktop, or a
push notification payload. Every transport ends in one call:

```
transport → BufferPath → controller.openLink(path, newShell: ...)
          → links.resolve(path) → linkPolicy, else openPolicy → one batch
```

The link table:

- The link table is a `LinkTable` in reef core, handed to the
  `WindowingController` as `links`. It maps each buffer kind to one path
  template (`task-edit` → `/tasks/:taskId/edit`). The template's
  parameters, with `%` and `/` percent-encoded, joined by `/` form the
  buffer token, so `/tasks/42/edit`
  resolves to `task-edit:42`. The kind:token id stays the internal
  identity. The path is the external form.
- `links.pathOf(buffer)` maps back: the path of a buffer, or null when its
  kind has no template or its token does not fit the template.
- A template without parameters resolves to one buffer with an empty
  token (`/tasks` → `tasks:`), so the link focuses the buffer already
  open. A kind listed in `drafts` resolves to a fresh buffer each time
  instead (`/tasks/new` → `task-new:<uuid v7>`), so drafts are
  addressable.
- Query arguments reach the link policy only. Core has no buffer
  arguments: the resolved buffer is an id, and the arguments do not enter
  the doc.

Opening a link:

- `openLink` returns false and changes nothing when no template matches.
- With `newShell: true` and `capabilities.canPopOut`, the buffer opens in
  a new shell (`openShell`). "Open in new shell" is a property of the call,
  like `target=_blank`, not URL state. Without pop-out support, or when
  the shell fails to open, the link goes to the policies below.
- `linkPolicy(doc, buffer, arguments)` returns the commands to dispatch,
  or null to let `openPolicy` decide. The default, `defaultLinkPolicy`,
  focuses a window that shows the buffer, in any shell, preferring the
  focused shell. Else it returns null.
- Cold start: the controller restores the doc first (§11), then the app
  calls `openLink` on top. Fresh install: the initial doc, then the link.

URL sync (`reef_router`, ADR 0003):

- `WindowingLinkSync` sits under `WindowingRoot`. It keeps the route
  information equal to the path of the focused shell's focused buffer.
  Arrangement never touches the URL: the doc hibernation owns layout, the
  URL owns content.
- Push or replace: a doc change reports a new entry (`navigate`) when the
  focused window's history grew by exactly the buffer that window
  showed before. Every other change rewrites the current entry
  (`neglect`): focus switches, `ReplaceBuffer`, `PopBuffer` and other
  app-initiated back.
- When the focused buffer has no path, or the path equals the current
  URL, nothing is reported.
- The initial route and every later route notification (browser back and
  forward, a typed URL) go to `openLink`. Changes caused by that call are
  not reported back. An initial route that does not resolve is then
  replaced by the focused buffer's path.
- Limitation: browser back and forward do not traverse window histories.
  They open the location of the target entry through `openLink` like any
  other link. If no window shows that buffer, `openPolicy` opens it, which
  by default pushes, so the window's history grows instead of shrinking.
  A template without parameters opens a fresh buffer on every traversal.
  The browser stack and the window histories are separate; no mapping
  between them is promised.

Worked examples (task app, kind `task-edit` at `/tasks/:taskId/edit`,
default policies):

1. Push notification `/tasks/42/edit`, fresh install: `openLink` resolves
   `task-edit:42` and pushes it onto the active window. The URL shows
   `/tasks/42/edit`.
2. Web, one window on task 42. The page opens task 43 with `openBuffer`:
   the window pushes 43 and the browser gets a new entry,
   `/tasks/43/edit`. Browser back opens `/tasks/42/edit` as a link. No
   window shows 42, so the default `openPolicy` pushes it: the window's
   back history is now `[42, 43]`.
3. Web, two windows on tasks 42 and 43, 43 focused. Click the window on
   42: a focus switch, so `/tasks/42/edit` replaces the current entry.

## 10. Lifecycles

Every death cascades doc-side first (one command; the reducer cascades),
then buffer-side (detachment triggers the existing last-window rule).

| Entity | Born | Dies | Children |
|---|---|---|---|
| shell | platform-first on pop-out; the first shell materializes at boot; mobile's is implicit and undying | `CloseShell`; last one unclosable | its tabs, their windows, buffer detachments |
| tab | `NewTab`, empty or with an initial buffer (one command, one undo unit) | `CloseTab` (interceptor veto point) or parent shell death | windows, detachments |
| window | `SplitWindow`, a tab's first window, or `FloatWindow` (reparenting, not birth) | `CloseWindow` or parent death | buffer detach; window history vanishes with it |
| buffer | first window binds it (fresh or `hibernatedSeed`) | last window detaches → auto-hibernate; pinned stays materialized until explicit close; discard wipes the store record | — |

Rules:

- Detach is not death. A buffer shown in windows across two shells survives
  one shell closing. Zero windows triggers hibernation. Undo of a cascade
  restores window bindings; buffers rematerialize from hibernation, or never
  left (pinned).
- When a buffer's content closes, windows still showing it navigate back
  through their history; a window whose history empties closes.
- Dead refs in a window history arise only after explicit discard
  (auto-hibernate always keeps the JSON). Prune on encounter; fall back to
  the nearest alive neighbor; close the window when the stack is all dead.

## 11. Hibernation

The doc hibernates as one record under the reserved id
`WindowingController.hibernationKey` (`windowing:`) in the existing
`HibernationStore`. Buffer providers must not use that id; debug builds
assert on it.

- The record holds `version` (currently 1), `doc` and `extra`. `doc`
  holds the shells (ordered tabs, active tab), the tabs (window trees with
  axes and ratios, active window), every window's history (back, current,
  forward), the floating entries (scope, zIndex, geometry hint) and the
  focused shell. Not saved: undo history (in memory only) and platform
  shell state.
- `persistence`, a constructor parameter, turns the live doc into the doc
  that is saved (default: the whole doc). `controller.extra` is an
  app-owned JSON value saved next to it and restored with it.
- With a `store`, the controller saves on every published doc change and
  on every `extra` write.
- At construction, the controller loads the record. A record with another
  version, a malformed record and a record whose doc breaks an invariant
  are deleted and ignored. Without a restored doc the controller calls
  `initial` (a callback, so it runs only then) and starts from its doc, or
  from `WindowingDoc.initial()` when it is null or returns null.
  Buffer records are unaffected.
- `controller.discardSavedLayout()` deletes the record. The next published
  doc is saved again.

Restore path: the controller starts on the restored doc before any widget
mounts. `ShellViews` opens a real shell for each doc shell at mount. A
shell whose real shell fails to open leaves the doc through a raw
`CloseShell` dispatch that bypasses the interceptor, since no rule may keep
a shell that does not exist; the last shell is never closed. On single-shell platforms the focused shell draws inline.
Windows rematerialize buffers through the existing family providers, and
hibernated seeds restore models. Geometry hints are advisory; projections
may ignore them.

## 12. Migration and phasing

Clean slate. Discarded, removed, no shims (done in W0): the old split-tree
feature in reef core, the per-tab router projection in `reef_auto_route`
(replaced by `reef_router` in W5, ADR 0003), the old split-tree hibernation
records. The kind:token registry concept is reimplemented inside the new
adapter. Breaking change; reef's version bumps.

Kept as foundation, untouched: `BufferId`, `ReefScope`, `ReefWindow`,
`ReefBufferScope`, hibernation store, `BufferRegistry`, family providers,
the quartet machinery, `ScreenTypeLayout`, listenable_plus, reef_fp.

| Phase | Delivers |
|---|---|
| W0 | Discard: remove the old split-tree feature, the old adapter projection, stale hibernation key handling |
| W1 | `WindowingDoc` (with per-window `BufferHistory`) + full command set + pure reducer + controller + `dispatchAll`; headless, exhaustive table tests |
| W2 | `UndoController`, `UndoEntry<S>`, `UndoHost<S>`, `WindowingUndoHost`, `UndoableModel` mixin, `BufferUndoHost` |
| W3 | Render: `WindowingScope`, containers, overlay layers, `WindowingDelegate`, reference projections + default policy, drag-resize, `WindowingShortcuts` |
| W4 | `reef_multi_window` adapter, platform-first/doc-first wiring, capabilities |
| W5 | `windowing:` doc hibernation + restore, `openPolicy`, `focusPolicy`, `controller.back()` and `WindowingSystemBack`, `LinkTable` + `openLink` + `linkPolicy`, `reef_router` (URL ↔ doc), example app showcase |
| W6 | Integration apps (`docs/integration-apps.md`) |

Testing per phase: reducer and command table tests without Flutter (W1);
`UndoController` pure tests with fake replay data, host-aware entry tests (W2); pop-out tests with `FakeShellPlatform` (W4); widget tests for containers and projection
switching over an unchanged doc (W3); pop-out/close intent tests plus the
interactive multi-window checklist as a manual demo (W4); hibernation
round-trip and rematerialization tests, deep-link resolution tests (W5).
