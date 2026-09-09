# Reef windowing design

Status: accepted design, 2026-09-02. Supersedes the split-tree workspace feature
(`features/workspace/`) and the per-tab workspace projection in `reef_auto_route`;
both are discarded, not migrated (§12).

## 1. Vocabulary and goals

Reef's navigation model borrows four abstractions from neovim: buffers hold
state, windows show buffers, tabs arrange windows, OS windows host tabs. The
abstractions stay. The vim command idioms do not; the framework exposes
app-native intents only.

| Entity | Meaning | Identity |
|---|---|---|
| OS window | a platform window; hosts a stack of tabs | `OsWindowId`, uuid v7 |
| tab | fills one OS window; the unit users switch between | `TabId`, uuid v7 |
| pane | subdivides a tab's canvas, or floats over any container | `PaneId`, uuid v7 |
| buffer | the content a pane draws; one buffer can back many panes | `BufferId` (existing, blueprint §4.4) |

Goals:

1. One canonical windowing state in reef core. Projections render it per
   platform and are presentation only. Which projection runs is a dynamic
   choice (app or user decides); reef ships a default policy.
2. Every surveyed windowing style is reachable with minimal effort: tiling
   splits, tabbed documents, one-buffer-many-views, pop-out windows, mobile
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
  osWindows:  Map<OsWindowId, OsWindowState>   // ordered tabIds, activeTabId
  tabs:       Map<TabId, TabState>             // windowId, pane tree root, activePaneId
  panes:      Map<PaneId, PaneState>           // history per pane
  floating:   Map<PaneId, FloatingState>       // scope, zIndex, geometry hint
  focusedOsWindowId: OsWindowId

PaneState
  history: BufferHistory { back: List<BufferId>, current: BufferId, forward: List<BufferId> }

Membership is structural: a pane appears in its tab's pane tree (tree pane)
or in the floating map (floating pane). No parent field to keep in sync.

FloatingState
  scope: OsWindowId | TabId | PaneId           // which container's overlay hosts it
  zIndex: int
  geometryHint: (optional, advisory)
```

Rules:

- Ids are extension types over `String`, uuid v7, the `BufferId` recipe.
- Buffers are not in the doc. The doc references `BufferId`s; the buffer
  registry and hibernation store own buffer existence (blueprint §10.2).
- One buffer, many panes: several panes may reference the same `BufferId`.
  Live sync comes from the family-viewmodel contract, free of charge.
- A pane is either a tree pane (a leaf slot in its tab's pane tree) or a
  floating pane (a member of a container's overlay, ordered by `zIndex`).
  Floating panes are uniform panes, not a separate kind; the same
  `PaneState` serves both.
- Invariants, enforced in the reducer: every tab belongs to exactly one
  window; a window's `tabIds` order is the tab strip order; pane trees
  partition tree panes per tab; each floating pane has exactly one scope;
  the focused chain is window → its active tab → its active pane; the last
  OS window can never be closed; doc changes that alter the OS-window set
  are undo barriers (§4).

## 3. Commands and the reducer

All mutations go through sealed commands. A pure reducer maps
`(doc, command) → doc`. Commands carry pre-generated ids for entities they
create, so dispatch stays synchronous and pure, and effects reference stable
ids.

| Group | Commands |
|---|---|
| Tabs | `NewTab` (optional initial buffer, creates the tab's first pane), `CloseTab`, `MoveTab`, `ActivateTab` |
| Tree panes | `SplitPane`, `ClosePane`, `MovePane`, `ResizePane` |
| Floating | `FloatPane`, `DockPane`, `RaisePane` |
| Buffer content | `AttachBuffer`, `PushBuffer`, `PopBuffer`, `ReplaceBuffer`, `NavigateForward` |
| Focus | `ActivatePane`, `ActivateOsWindow` |
| OS windows | `AttachOsWindow`, `CloseOsWindow` |

Dispatch semantics:

- A command invalid in the current state (moving the last tab out of a
  window, closing a nonexistent pane) returns the doc unchanged. Callers
  that care can diff or ask first; nothing throws across the API.
- `dispatchAll` applies a batch atomically with one publish. A move is
  remove + insert in one batch. A batch is one undo unit (§4).
- Controller methods (`splitPane(...)`, `moveTab(...)`) construct and
  dispatch commands. Pages call methods; the command record exists for the
  undo timeline and the audit log, not for ceremony.
- Platform intents are async controller methods and the only impure edge:
  `popOutTab` opens the real window first, then dispatches `AttachOsWindow`
  on success (the doc never claims a window that does not exist);
  `closeOsWindow` dispatches first, then closes the real window best-effort.
  On hosts without multi-window support these return a capability failure
  and the doc stays untouched.

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
- Undo history resets when the OS-window set changes (§2 barriers). Layout
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
through `WindowingScope` (inherited lookup of the controller); mutations go
back through controller intents. Units take ids, never objects, so the same
widget renders whatever the doc says and projection switches re-run
assembly over an unchanged doc.

Containers. Each container renders its content plus its own `Overlay`.

| Unit | Renders | Overlay hosts |
|---|---|---|
| `OsWindowHost` | active tab's canvas; dev supplies window chrome via `surfaceBuilder` | window-scoped floating panes |
| `TabCanvas` | the tab's pane tree (Flex recursion), resize handles, `paneArrangement` | tab-scoped floating panes |
| `PaneHost` | the pane's `ReefWindow`, focus ring slot | pane-scoped floating content |
| `TabStripSlot` | headless tab data: tabIds, activeTabId, activate/close/reorder callbacks | dev renders the look |
| `FloatingLayer` | a container's floating panes in an `Overlay`, ordered by `zIndex`, each wrapped in the dev's positioning widget | |

`paneArrangement` decides how a tab's panes manifest: `flexTree` (desktop
default), `focusedOnly` (compact default), or a custom builder. Drag-resize
ships as `PaneResizeHandle`, emitting `ResizePane` intents coalesced under
the undo key `resize:paneId`, so one drag is one undo step.

Projections:

```dart
typedef WindowingProjection = Widget Function(
    BuildContext context, WindowingController controller, OsWindowId windowId);
typedef WindowingProjectionPolicy = WindowingProjection Function(
    BuildContext context, WindowingController controller, OsWindowId windowId);
```

Two reference assemblies ship as widgets: `DesktopProjection` (one
`OsWindowHost` per doc window, optional tab strip, `flexTree` canvas) and
`TabbedProjection` (single window, dev tab bar via `TabStripSlot`,
`focusedOnly` canvas). `defaultWindowingProjection` resolves via
`screenTypeOf`: expanded → desktop, medium/compact → tabbed. Apps replace
the policy, start from a shipped projection and swap slots, or compose
containers directly under their own `surfaceBuilder`. Three depths, one
contract.

Rebuild discipline: units consume per-entity selectables, so activating a
tab rebuilds that tab's slot, not the tree.

`WindowingShortcuts` is an opt-in unit with standard default bindings
(close pane, split, navigate back/forward, undo/redo). Keybinding is app
chrome; the unit exists so nobody rewires the obvious keys by hand.

## 6. Delegates

One `WindowingDelegate` bundle, handed to `WindowingRoot`, distributed via
`WindowingScope`, overridable per subtree by nesting
`WindowingDelegateScope(delegate.copyWith(...))`.

Visual hooks (each with a framework default):

| Hook | Default | Example override |
|---|---|---|
| `projectionPolicy` | screen-class resolution | user preference "always tabs" |
| `paneArrangement` | `flexTree` / `focusedOnly` by screen class | pane carousel on tablet |
| `tabStrip` | headless slot defaults | segmented control, overflow menu |
| `splitter` | thin draggable divider | thick themed handle, double-click maximizes |
| `paneChrome` | border when focused | pane headers with titles and close buttons |
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
  lacks), policy limits (max panes per tab), and smart routing. Veto
  reports the failure and leaves the doc untouched. Replace rewrites the
  command before the reducer sees it, e.g. a horizontal split into a
  vertical one.
- `openPolicy`: how "open buffer X" compiles. Focus an existing pane
  (single-instance buffers), push onto the focused pane, split, or new tab.
- `focusPolicy`: what close and split do to focus; focus restoration rules.
- `persistence`: what the hibernation record keeps; whether the projection
  choice persists.

Non-overridable core: doc invariants (reducer), the command set, the undo
timeline, buffer live sync. Delegates work through the pipeline
(intercept, replace, parameterize). They can make the system stricter or
smarter, never corrupt it.

## 7. Multi-window

The spike's `WindowHost` seam graduates into a `reef_multi_window` adapter
package (the `reef_auto_route` pattern). `RealWindowHost` quarantines the
unstable Flutter-master API (`@internal` imports; per-invocation
`FLUTTER_WINDOWING=true` env override, never the global config flag).
`FakeWindowHost` serves tests.

```dart
abstract interface class WindowHost {
  bool get isSupported;                                 // false on single-window platforms
  Future<Result<HostError, Unit>> open(OsWindowId id);  // create a real window for that doc window
  void close(OsWindowId id);                            // best-effort destroy
}
```

- Ordering is deliberately asymmetric. Create is host-first: `popOutTab`
  opens the real window, then dispatches `AttachOsWindow`. The doc never
  claims a window that does not exist. Close is doc-first: dispatch, then
  `host.close` best-effort. The doc is truth; a platform failure is a
  leak, recoverable by closing the real window.
- View plumbing: `runWidget(ProviderScope(WindowManager(...)))`. One scope
  above the manager, so inherited lookups (including `WindowingScope`)
  cross view boundaries and every real window shares providers. The
  adapter maps each doc OS window to a real `View`; each View hosts that
  window's `surfaceBuilder` subtree. Buffers stay plain shared state.
- `controller.capabilities.canPopOut` gates pop-out UI. On mobile and
  tablet the host reports unsupported and pop-out UI hides; the
  doc still holds the one window entity.
- The last OS window can never be closed (reducer invariant). Closing the
  last real window on desktop is the platform's app exit, outside the doc.
- Limitation, documented: native close buttons bypass reef. Upstream
  `onWindowCloseRequested` is fire-and-destroy with no veto. Dev-built
  title bars call `controller.closeOsWindow` and get the interceptor's
  veto path; the platform X button does not, until upstream ships a
  veto-able hook.

## 8. Buffer navigation

Navigator semantics on top of the spatial model. Each pane owns a history
in the doc (§2 `BufferHistory`): `back`, `current`, `forward`.

- `PushBuffer`: demotes current to back, clears forward, sets new current.
  Push targets are an existing `BufferId` (reuse, live sync) or a spec
  (kind + args) that `openPolicy` resolves to create-or-focus.
- `ReplaceBuffer`: swaps current, stacks untouched.
- `PopBuffer` (back) and `NavigateForward`: mirror moves on the stacks.
- Both stacks are always tracked. Exposing forward is the dev's choice:
  mobile wires back only; desktop may bind Alt+Left/Right and mouse
  buttons.
- `openPolicy` defaults: mobile/tabbed pushes onto the focused pane;
  desktop opens into a detail pane. Pages keep calling `openBuffer(...)`.

Platform back = pane back. Android's system back (predictive) and an app
back button bind to `PopBuffer(activePane)`. When the back stack empties,
`focusPolicy` decides (close the tab, background the app). Browser back is
a different history with different rules (§9).

## 9. Deep linking

True URIs, browser-compatible. A deep link is a `BufferPath` (path + args)
arriving over any transport: router URL on web and mobile, protocol
handler or launch args on desktop, push notification payloads. All
transports normalize into one seam:

```
transport → BufferPath → linkPolicy.resolve(ref, doc) → commands
          // focus existing | push here | new pane | new tab | new OS window
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
- History mapping: focus switches (another tab, another pane) rewrite the
  current entry (`replaceState`), like browsers, which also leave tab
  switches out of history. `PushBuffer` navigation adds an entry
  (`pushState`). Browser back/forward arrive as `popState` and resolve
  through `linkPolicy`. App-initiated back traverses when the adjacent
  history entry matches the target location, else rewrites the current
  entry. The browser stack is the session's location
  history; pane histories are per-pane navigation. They interact through
  the same resolve rule; no strict isomorphism is promised.
- "Open in new window" is a link property, like `target=_blank`, decided
  by policy, not URL state.
- Ephemeral drafts are addressable when a template exists
  (`/tasks/new` restores a fresh draft). A ref with no template leaves
  the URL unchanged (documented; no garbage params).
- Cold start: restore the doc first, then apply the arriving link as a
  focus or open delta on top. Fresh install: empty doc, link creates.

Worked examples (task app, kinds `tasks`, `task-detail`, `task-edit`):

1. Push notification `/tasks/42/edit`, fresh install: doc becomes window →
   tab → pane with `current = task-edit:42`. Address bar shows
   `/tasks/42/edit`.
2. Web, one pane: on `/tasks`, tap task 42 → push, browser stack
   `[/tasks, /tasks/42/edit]`. Browser back pops the pane. Forward mirrors.
3. Web, two panes: left list, right detail. Click 43 → right pane pushes
   43, focus follows, `pushState(/tasks/43/edit)`. Click the left pane →
   `replaceState(/tasks)`, no history entry. Browser back revisits
   `/tasks/42/edit` and focuses that buffer; the right pane's own back
   stack `[42]` is untouched.

## 10. Lifecycles

Every death cascades doc-side first (one command; the reducer cascades),
then buffer-side (detachment triggers the existing last-pane rule).

| Entity | Born | Dies | Children |
|---|---|---|---|
| OS window | host-first on pop-out; the first window materializes at boot; mobile's is implicit and undying | `CloseOsWindow`; last one unclosable | its tabs, their panes, buffer detachments |
| tab | `NewTab`, empty or with an initial buffer (one command, one undo unit) | `CloseTab` (interceptor veto point) or parent window death | panes, detachments |
| pane | `SplitPane`, a tab's first pane, or `FloatPane` (reparenting, not birth) | `ClosePane` or parent death | buffer detach; pane history vanishes with it |
| buffer | first pane binds it (fresh or `hibernatedSeed`) | last pane detaches → auto-hibernate; pinned stays materialized until explicit close; discard wipes the store record | — |

Rules:

- Detach is not death. A buffer shown in panes across two windows survives
  one window closing. Zero panes triggers hibernation. Undo of a cascade
  restores pane bindings; buffers rematerialize from hibernation, or never
  left (pinned).
- When a buffer's content closes, panes still showing it navigate back
  through their history; a pane whose history empties closes.
- Dead refs in a pane history arise only after explicit discard
  (auto-hibernate always keeps the JSON). Prune on encounter; fall back to
  the nearest alive neighbor; close the pane when the stack is all dead.

## 11. Hibernation

The whole doc serializes under one reserved `windowing:` key in the
existing `HibernationStore`, versioned. Serialized: windows (ordered tabs,
active tab), tabs (pane trees with ratios, floating entries with scope,
zIndex, geometry hints, active pane), focus pointers, version. Unknown
version discards the doc; buffers are unaffected. Not serialized: undo
history (in memory only), platform window state.

Restore path: load doc, attach each OS window (real windows via host-first
`open` on desktop, inline surface on single-window platforms), panes
rematerialize buffers through the existing family providers, hibernated
seeds restore models. Geometry hints are advisory; projections may ignore
them.

## 12. Migration and phasing

Clean slate. Discarded, removed, no shims: `features/workspace/`
(`SplitNode`, `SplitTreeController`, `SplitWorkspace`), the per-tab
workspace projection in `reef_auto_route`, the old `workspace:` hibernation
records. The kind:token registry concept is reimplemented inside the new
adapter. Breaking change; reef's version bumps.

Kept as foundation, untouched: `BufferId`, `ReefScope`, `ReefWindow`,
`ReefBufferScope`, hibernation store, `BufferRegistry`, family providers,
the quartet machinery, `ScreenTypeLayout`, listenable_plus, reef_fp.

| Phase | Delivers |
|---|---|
| W0 | Discard: remove the workspace feature, the old adapter projection, stale hibernation key handling |
| W1 | `WindowingDoc` (with per-pane `BufferHistory`) + full command set + pure reducer + controller + `dispatchAll`; headless, exhaustive table tests |
| W2 | `UndoController`, `UndoEntry<S>`, `UndoHost<S>`, `WindowingUndoHost`, `UndoableModel` mixin, `BufferUndoHost` |
| W3 | Render: `WindowingScope`, containers, overlay layers, `WindowingDelegate`, reference projections + default policy, drag-resize, `WindowingShortcuts` |
| W4 | `reef_multi_window` adapter, host-first/doc-first wiring, capabilities |
| W5 | `windowing:` doc hibernation + restore, rebuilt router adapter (URL ↔ doc), example app showcase |

Testing per phase: reducer and command table tests without Flutter (W1);
`UndoController` pure tests with fake replay data, host-aware entry tests
with `FakeWindowHost` (W2); widget tests for containers and projection
switching over an unchanged doc (W3); pop-out/close intent tests plus the
interactive multi-window checklist as a manual demo (W4); hibernation
round-trip and rematerialization tests, deep-link resolution tests (W5).
