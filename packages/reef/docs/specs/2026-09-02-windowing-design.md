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
  no tree. The reducer never cascades upward; a `focusPolicy` that wants
  the tab gone replaces the command via the interceptor (§6).
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
- One entry per `dispatchAll` batch. Focus-only changes update state without
  recording. Consecutive batches sharing a `coalesceKey` merge into one
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
- `openPolicy`: how "open buffer X" compiles. Focus an existing window
  (single-instance buffers), push onto the focused window, split, or new tab.
- `focusPolicy`: what close and split do to focus; focus restoration rules.
- `persistence`: what the hibernation record keeps; whether the projection
  choice persists.

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
  Push targets are an existing `BufferId` (reuse, live sync) or a spec
  (kind + args) that `openPolicy` resolves to create-or-focus.
- `ReplaceBuffer`: swaps current, stacks untouched.
- `PopBuffer` (back) and `NavigateForward`: mirror moves on the stacks.
- Both stacks are always tracked. Exposing forward is the dev's choice:
  mobile wires back only; desktop may bind Alt+Left/Right and mouse
  buttons.
- `openPolicy` defaults: mobile/tabbed pushes onto the focused window;
  desktop opens into a detail window. Pages keep calling `openBuffer(...)`.

Platform back = window back. Android's system back (predictive) and an app
back button bind to `PopBuffer(activeWindow)`. When the back stack empties,
`focusPolicy` decides (close the tab, background the app). Browser back is
a different history with different rules (§9).

## 9. Deep linking

True URIs, browser-compatible. A deep link is a `BufferPath` (path + args)
arriving over any transport: router URL on web and mobile, protocol
handler or launch args on desktop, push notification payloads. All
transports normalize into one seam:

```
transport → BufferPath → linkPolicy.resolve(ref, doc) → commands
          // focus existing | push here | new window | new tab | new shell
```

URL rules:

- Buffer kinds register path templates in the app's route table
  (`tasks` → `/tasks`, `task-edit` → `/tasks/:taskId/edit`). Kind:token
  stays an internal registry identity; the external form is a proper
  hierarchical URI.
- The URL is the focused buffer's path. Query carries buffer args and
  modifiers. Arrangement never touches the URL; the doc hibernation owns
  layout, the URL owns content. Same split as the web: the URL says what
  you are looking at, the site owns how it displays.
- History mapping: focus switches (another tab, another window) rewrite the
  current entry (`replaceState`), like browsers, which also leave tab
  switches out of history. `PushBuffer` navigation adds an entry
  (`pushState`). Browser back/forward arrive as `popState` and resolve
  through `linkPolicy`. App-initiated back traverses when the adjacent
  history entry matches the target location, else rewrites the current
  entry. The browser stack is the session's location
  history; window histories are per-window navigation. They interact through
  the same resolve rule; no strict isomorphism is promised.
- "Open in new shell" is a link property, like `target=_blank`, decided
  by policy, not URL state.
- Ephemeral drafts are addressable when a template exists
  (`/tasks/new` restores a fresh draft). A ref with no template leaves
  the URL unchanged (documented; no garbage params).
- Cold start: restore the doc first, then apply the arriving link as a
  focus or open delta on top. Fresh install: empty doc, link creates.

Worked examples (task app, kinds `tasks`, `task-detail`, `task-edit`):

1. Push notification `/tasks/42/edit`, fresh install: doc becomes shell →
   tab → window with `current = task-edit:42`. Address bar shows
   `/tasks/42/edit`.
2. Web, one window: on `/tasks`, tap task 42 → push, browser stack
   `[/tasks, /tasks/42/edit]`. Browser back pops the window. Forward mirrors.
3. Web, two windows: left list, right detail. Click 43 → right window pushes
   43, focus follows, `pushState(/tasks/43/edit)`. Click the left window →
   `replaceState(/tasks)`, no history entry. Browser back revisits
   `/tasks/42/edit` and focuses that buffer; the right window's own back
   stack `[42]` is untouched.

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

The whole doc serializes under one reserved `windowing:` key in the
existing `HibernationStore`, versioned. Serialized: shells (ordered tabs,
active tab), tabs (window trees with ratios, floating entries with scope,
zIndex, geometry hints, active window), focus pointers, version. Unknown
version discards the doc; buffers are unaffected. Not serialized: undo
history (in memory only), platform shell state.

Restore path: load doc, attach each shell (real shells via platform-first
`open` on desktop, inline surface on single-shell platforms), windows
rematerialize buffers through the existing family providers, hibernated
seeds restore models. Geometry hints are advisory; projections may ignore
them.

## 12. Migration and phasing

Clean slate. Discarded, removed, no shims (done in W0): the old split-tree
feature in reef core, the per-tab router projection in `reef_auto_route`
(the package is an empty shell until W5), the old split-tree hibernation
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
| W5 | `windowing:` doc hibernation + restore, rebuilt router adapter (URL ↔ doc), example app showcase |

Testing per phase: reducer and command table tests without Flutter (W1);
`UndoController` pure tests with fake replay data, host-aware entry tests (W2); pop-out tests with `FakeShellPlatform` (W4); widget tests for containers and projection
switching over an unchanged doc (W3); pop-out/close intent tests plus the
interactive multi-window checklist as a manual demo (W4); hibernation
round-trip and rematerialization tests, deep-link resolution tests (W5).
