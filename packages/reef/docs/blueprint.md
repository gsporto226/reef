# Reef Blueprint

Prescriptive architecture extracted from the CIApp (`FlutterMonorepo/apps/ciapp/app`).
This document defines **the reef way** — the patterns we keep, the ones we redefine,
and the ones we drop. It is not a description of how CIApp is today; where CIApp and
reef disagree, reef wins.

Decided in the design sessions of 2026-08; implementation lives in the sibling
packages (`reef`, `reef_fp`, `listenable_plus`, `task_graph`, `reef_utils`) and
consumes `formularium` untouched.

---

## 1. Foundational principles

1. **Synchronous current value.** Reactive state must be readable without
   subscribing: the UI always has a synchronous snapshot of the current state,
   which is simpler to reason about and develop against. Reef uses
   `ValueListenable` / `ValueNotifier` / `Listenable` (the same model as
   `pkg:listen`, the Flutter team's pure-Dart state package) and represents
   async state with synchronous values (§3). **Streams are banned** — a
   stream is a sequence of events with no current value. No rxdart, no
   `StreamBuilder`.
2. **Async state is a value inside a listenable.** The universal async/error surface is
   `ValueListenable<Async<Result<E, T>>>`. One-shot async work is a `Future` whose
   completion writes into a `ValueNotifier`.
3. **Errors are values.** Fallible operations return `Result<E, T>` (reef_fp, err-first:
   `Err` carries the error type, `Ok` the success value). Widgets never see exceptions;
   they render state.
4. **The viewmodel mediates everything.** UI objects are input devices the viewmodel
   listens to; the model is mutated only through the viewmodel.
5. **Feature-first organization** with underscore-prefixed folders
   (`_interfaces/`, `_implementations/`, `_presentation/`, `_providers/`), inherited
   from CIApp.

## 2. Package map

| Package | Role |
|---|---|
| **reef** (this framework) | `ViewModel` base, `Operation`, `bind()`, formularium bridge, `ReefWindow` scaffold, buffer identity & scope, hibernation lifecycle, windowing (shells, tabs, windows; see the windowing design spec), async/result builders, responsive layouts, riverpod composition helpers |
| **reef_widgets** | Widget-layer features over listenables — currently the infinite-scroll behavior (`InfiniteScrollController`/`InfiniteScrollWidget`); design-system-agnostic (§5.7) |
| **reef_router** | The link adapter (§10.3): the URL follows the focused buffer over Flutter's route information API (ADR 0003) |
| **reef_fp** | Sync value types: `Either`, `Result`, `Optional`, `Async` (`Idle`/`Pending`/`Ready`) |
| **listenable_plus** | Pure reactive combinators over `ValueListenable` (`map`, `select`, `where`, `distinct`, `debounceTime`, `combineWith`, `switchListen`) |
| **task_graph** | DAG bootstrap scheduler (pre-init / post-init), Zig-inspired |
| **formularium** | Form fields & validation. Consumed **unchanged** |
| riverpod (codegen) | Composition root / DI. Reference implementation, dependency of core |

Dropped from CIApp: `get_it` (declared but unused), `rxdart_plus` /
`SeededValueStream` (superseded by listenables), legacy `pages/` quartets, the
`module/` vs `pages/` vs `features/` split (reef apps have exactly one screen
convention — features).

## 3. reef_fp — the `Async` type

`Async<T>` replaces the old `Pending<T>`/`NotReady` pair and carries lifecycle:

| Variant | Meaning |
|---|---|
| `Idle<T>` | never ran / reset |
| `Pending<T>` | in flight (loading), no payload |
| `Ready<T>` | has a value |

```dart
sealed class Async<T> {
  const factory Async.idle() = Idle<T>;
  const factory Async.pending() = Pending<T>;
  const factory Async.ready(T value) = Ready<T>;
}
```

- Universal async/error surface: `ValueListenable<Async<Result<E, T>>>`.
- `Pending` carries **no previous value**; "keep last ready value while reloading" is a
  combinator (`keepLast`-style extension in reef), not core semantics.
- Existing `Pending`/`Result` builders port to a three-way switch
  (idle → placeholder, pending → skeleton, ready → render `Result`).

## 4. The quartet — Page, Model, ViewModel, Provider

| Layer | File | Owns | Forbidden |
|---|---|---|---|
| **Page** | `<x>_page.dart` | layout composition (responsive variants) + wiring: watches provider, binds (model, viewmodel) into layout; **defines a buffer type** (§4.4, §10) | any state, any logic |
| **Model** | `<x>_model.dart` | the page's **domain model**: non-derived, settled state; immutable (**must be a `@freezed` object**); fully serializable | `Async`/`Either`/`Result`/`Optional` *fields*; streams; Flutter types; I/O; service refs |
| **ViewModel** | `<x>_viewmodel.dart` | **owns the model instance**; `ValueListenable<M>` reactive view; out-bindings; in-bindings; ephemeral UI objects; all async/error state | persisted state; widget/layout concerns |
| **Provider** | `<x>_provider.dart` | composition root: builds model → viewmodel(model, deps); owns lifetimes, `onRefDispose` | business logic |

### 4.1 Model rules

- **Models must be `@freezed` objects.** freezed generates `==`, `hashCode`,
  `toString`, `copyWith` and (with json_serializable) the JSON codec; the model
  file carries only the data shape and the domain behavior. Recipe:

  ```dart
  @freezed
  abstract class TaskEditModel with _$TaskEditModel {
    const TaskEditModel._(); // required so class-body methods can read fields

    const factory TaskEditModel({@Default('') String title, DateTime? dueDate}) =
        _TaskEditModel;

    factory TaskEditModel.fromJson(Map<String, dynamic> json) =>
        _$TaskEditModelFromJson(json);

    // The mutation language — named methods — lives in the class body.
    Result<TaskError, TaskEditModel> withDueDate(DateTime? date) => /* ... */;
  }
  ```

  Dependencies: `freezed`, `json_serializable`, `build_runner` as dev deps
  (current latest: freezed 4.0.1, json_serializable 6.14.1, build_runner
  2.16.0; requires Dart ≥ 3.13); `freezed_annotation` and `json_annotation` as
  regular deps. The reef core stays freezed-free — codegen is an app concern.
- Immutable. State changes are **pure named methods returning the modified model**:
  `withColor(c) → Model`. Dart forbids a method sharing a field name, so the
  canonical convention is `with<Field>(value)` — named after the change it applies.
- **Fallible changes return `Result<E, Model>`** — the `Result` is the return type of a
  pure operation, never stored state.
- **`copyWith` is allowed for mechanical field diffs** (freezed generates it);
  fallible or invariant-bearing changes **must** go through the named methods
  so the rules stay in exactly one place. Teams that want the stricter
  single-surface rule can opt out per model with `@Freezed(copyWith: false)`.
- Serializable (pure data) — this is the hibernation contract (§7).
- Domain behavior (validation/normalization) allowed; must be pure.
- **Multi-state domains**: freezed unions (sealed variants) are the sanctioned
  pattern — one named case per state, exhaustively switchable.

### 4.2 ViewModel rules

- Reactive view of the model: `ValueListenable<Model>` (the out-binding root).
- **Out-bindings** are `$`-prefixed (`$model`, `$searchText`, `$save`, ...); derived
  chains start at `$model` via listenable_plus combinators (`map`/`select`,
  `combineWith`, `debounceTime`, `switchListen`).
- **In-bindings** are intents: `on<Event>` / imperative verbs.
- Owns **ephemeral UI objects** (`TextEditingController`, `FocusNode`, `ValueNotifier`
  UI state); recreated on restore seeded from the model.
- **Sole publisher**: the only code that replaces the model, with explicit publish.
- Owns **all** async/error state (`Async`/`Result`) — the model never carries it.

### 4.3 Folder shape (per screen)

```
features/<feature>/_presentation/<screen>/
  <screen>_page.dart
  <screen>_viewmodel.dart
  <screen>_model.dart
  <screen>_provider.dart      (+ .g.dart)
  _layouts/                    (responsive variants)
  _widgets/
```

### 4.4 Buffer identity & scope

A page defines a **buffer type**; the provider family materializes **buffers** —
individual, keyed page states that live independently of how many windows show
them (§10).

- **`BufferId`** — identity of a materialized buffer. An extension type over
  `String`, generated with **uuid v7** (the `uuid` package, called directly —
  time-sortable, unique). `BufferId.manual(s)` for tests/reattachment;
  `id.sub(x)` namespaces child scopes. Not generic.
- **Family-keyed provider convention** — the buffer materializer:

  ```dart
  @riverpod
  TaskEditViewModel taskEditViewModel(Ref ref,
      {required BufferId bufferId, TaskEditModel? initial}) { ... }
  ```

- **`ReefScope`** — disposable callback registry for non-provider resources that
  must die with the buffer (subscriptions to global listenables, timers).
  Exposed as an auto-dispose family `reefScopeProvider(bufferId)`; its lifetime
  is the buffer's — shared by all windows on the buffer, disposed when the last
  one goes (or the buffer is closed).
- **`ReefWindow`** — the viewport widget (formerly `ReefPage`). Owns identity,
  scope and provider watch in one place:

  ```dart
  typedef BufferViewModelProvider<V extends ViewModel<Object?>>
      = ProviderListenable<V> Function(BufferId bufferId);

  ReefWindow<TaskEditViewModel>(
    // bufferId: null → materialize a fresh buffer
    // bufferId: someId → open THAT buffer (windows share it, live-synced)
    bufferId: null,
    viewModel: (id) => taskEditViewModelProvider(bufferId: id),
    builder: (context, vm) => ...,
  )
  ```

- **`ReefBufferScope.of(context)`** — inherited access to the buffer id for
  descendants (layouts, dialogs, child scopes).
- Dropped from CIApp: the `applicationIdProvider` invalidate-self hack (identity
  is computed once in the window state, not via a provider), `ApplicationPage` /
  `WApplicationScope` / `IdentifiedConsumerWidget` (folded into `ReefWindow`),
  `keepWithPage` / `scoped<T>()` (deferred until a concrete need — e.g.
  EventCenter subscriptions).

### 4.5 Responsive layouts

`ScreenTypeLayout` (dependency-free): resolves the window class from
`MediaQuery` width with the Material breakpoints — compact (< 600) → mobile,
medium (600–839) → tablet, expanded (≥ 840) → desktop — and builds the
matching variant. Unspecified variants fall back tablet → mobile,
desktop → tablet → mobile. The `_layouts/` folder holds the variants; they
receive the bound viewmodel and render from its out-bindings.

### 4.6 Rendering async state — builders

Builders take **values**, not listenables — compose with
`ValueListenableBuilder` (§5: widgets are pure views):

- `AsyncBuilder<T>` — idle/pending render the layout fed with a `sample`
  (real layout, placeholder data; the CIApp `PendingBuilder` pattern without
  a skeleton dependency — wrap with your own), ready renders the value.
- `ResultBuilder<E, T>` — `Err` → error widget (default renders
  `ILocalizable.localize()`), `Ok` → builder.
- `AsyncResultBuilder<E, T>` — the universal surface `Async<Result<E, T>>`
  (§1) in one widget.

### 4.7 Infinite scroll behavior — in `reef_widgets`

`InfiniteScrollController<T, F, E>` (package `reef_widgets`) — paginated lists
over listenables only (CIApp's rxdart version re-expressed: `switchMap`/
`exhaustMap` → an explicit state machine, the `CancellationToken` → a
generation counter):

- `$filter: ValueListenable<Async<F>>` drives resets — a distinct ready
  filter restarts the machine (accumulation cleared, page 1 loaded).
- `loadPage → Future<Result<E, InfiniteScrollPage<T>>?>` — a `null` return
  signals the end; an `Err` keeps the accumulated list and allows a retry
  (deliberate divergence: CIApp cleared the list on error).
- `$state: ValueListenable<InfiniteScrollState<T>>`
  (`ScrollIdle`/`LoadingFirst`/`LoadingMore`/`ScrollLoaded`) with derived
  `$isLoadingMore`, guarded `loadMore()` and `reset()`.
- `InfiniteScrollWidget` — scroll-threshold → `loadMore`, builder slots for
  items/empty/idle/loading, and the injectable `refreshWrapper` for
  pull-to-refresh chrome (§5.7: the design system's choice, null = no pull
  gesture; loading slots default to nothing).

## 5. Sync contract — linking UI state and model state

Three state spaces: **model state** (serializable truth), **UI state** (ephemeral
objects), **derived state** (computed). The viewmodel is the only bridge.

1. **Sole ownership** — only the viewmodel mutates the model. UI objects are never a
   source of truth.
2. **In-channel (UI → model):** the viewmodel subscribes to the UI objects' own
   `Listenables` → applies the named model method → publishes.
3. **Out-channel (model → UI):** the viewmodel subscribes to field-level derived
   listenables (`$model.map(...)`) → writes into the UI object.
4. **Loop-breaking: transient unsubscription only.** While processing an in-event the
   out-listener is suppressed; while performing an out-write the in-listener is
   suppressed (listeners are *removed and re-added*, not paused — events during
   suppression are dropped, never buffered). No equality guards, no echo.
5. **Widgets are pure views** over `ValueListenables` and the UI objects the viewmodel
   hands them. No `onChanged` business wiring, no model access.
6. The repetition (seed + guarded in + guarded out + dispose) is encapsulated in
   **`bind()`** — reef's binding primitive:

```dart
// generic
vm.bind(
  modelValue: vm.$title,                       // out: derived from $model
  uiValue: titleController,                    // in: UI object as Listenable
  fromUi: (v) => v.text,                       // UI value -> model-space value
  toUi: (s) => TextEditingValue(text: s),      // model value -> UI value
  writeUi: (u) => titleController.value = u,   // out-write
  apply: (s) => model.title(s),                // in: fallible model transform
  via: vm.titleOp,                             // Operation<Unit, E> for failures
);

// convenience for text fields
vm.bindText(titleController, vm.$title, apply: (s) => model.title(s));
```

7. **Design-system-agnostic.** Reef and reef_widgets depend only on
   `package:flutter/widgets.dart` — no Material, no Cupertino. A design system
   is an **app-side choice**: `material_ui` / `cupertino_ui` (the standalone
   packages that replaced the SDK-bundled libraries in Flutter 3.47) are the
   sanctioned Material path (`dart fix --apply --code=migrate_design_widgets`),
   but the framework never forces one. Design-free apps run `WidgetsApp`
   (needs an explicit `color`; route types must be `RouteType.custom` —
   Material routes require `MaterialLocalizations`). Widgets that used to
   carry Material chrome take it as injection instead: `InfiniteScrollWidget`
   accepts a `refreshWrapper` (pull-to-refresh chrome, null = no gesture) and
   its loading slots default to nothing — bring your own indicators.

## 6. Formularium — the input tier

Formularium fields own **all input validation** — format, constraints **and
model-dependent invariants** — and provide `dirty/pure`, async validation, warnings,
autovalidate UX policy and localized messages (`ILocalizable`, context-free).

**Single source of truth for invariants:** the field's validator **delegates to the
model's domain method**. The rule is never encoded twice.

| Concern | Surface |
|---|---|
| Input validation (incl. model-dependent) | formularium field `$status` (`Valid`/`Invalid`/`Validating`/`Pending`) |
| Stale-apply race (model changed between validate & apply) | re-validate the field — self-healing loop |
| Non-field operations (save/submit/network) | `Operation` listenables (§6.1) |

### 6.1 Bridge primitives (reef, formularium untouched)

- **`toValidation()` adapter** — maps `Result<E, M>` → formularium `Validation<V>`;
  errors are converted to `ILocalizable` so field errors and domain errors render
  through one path:

```dart
late final dueDateField = FormulariumFormField<DateTime, DateTime>(
  validator: reefValidator(
    (d) => model.dueDate(d),                    // model method IS the validator
    localize: (e) => e.message,                 // E -> ILocalizable
  ),
);
```

- **Apply timing — two page styles:**
  - **Live pages** apply-on-`Valid`: field `$status` → `Valid(transformed)` → apply to
    model → publish. The model live-tracks the form (hibernation-friendly).
  - **Submit pages** always call `validate()` (full, not just dirty) at submission,
    then apply.
- **Stale-apply → re-validate:** if the apply fails although validation passed (model
  state moved), re-run the field's validation against the current model. No separate
  error surface.
- **Reconciliation:** a rejected in-binding ends with the UI object re-synced to model
  state (out-write with transient unsub).

### 6.2 Operation — everything that is not a field

```dart
class Operation<T, E> {
  ValueListenable<Async<Result<E, T>>> get $state => _state;

  Future<void> run(Future<Result<E, T>> Function() action) async {
    _state.value = const Async.pending();       // loading
    _state.value = Async.ready(await action()); // Ready(Ok) | Ready(Err)
  }

  void reset() => _state.value = const Async.idle();
  void fail(E error) => _state.value = Async.ready(Err(error));
}
```

- **Async path:** `saveOp.run(() => service.submit(model))` — model untouched, UI
  renders `$state` with the standard three-way builder.
- **Sync path (`edit`)** — every fallible model change funnels through one method on
  the ViewModel base:

```dart
void edit<E>(Result<E, M> result, {required Operation<Unit, E> via, List<VoidCallback> onFail}) {
  result.fold(
    (e) { via.fail(e); for (final r in onFail) r(); },      // failure: surface + reconcile
    (m) { via.reset(); publish(m); },                       // success: publish + clear
  );
}
```

  Sync operations carry failures only (the published model is the success signal);
  `Ready(Err)` ≡ the old concern shape, `Idle` ≡ cleared.

## 7. Lifecycle & restoration

- Create → bind → dispose. The provider (`ref.onDispose`) owns the lifetime.
- **Restore = Flutter native restoration.** The model is pure serializable data; its
  JSON travels through the restoration framework (`RestorationBucket`,
  page-scoped by id); the provider re-seeds the model on restore; the viewmodel
  constructor seeds ephemeral UI objects from the model.
- **Hibernation** is specified by the page-management model (§10) and shipped
  in Phase B: buffers auto-hibernate when their last window closes
  (`hibernateOnDispose`), pinned buffers stay materialized, and reopening a
  buffer id rematerializes from the store (`hibernatedSeed`). The
  requirement stands: *models must be serializable*.

## 8. DI stance — decided

**Riverpod (with code generation) is the composition root**, a direct dependency of
the reef core. `ReefWindow` watches buffer providers; app-scoped services/controllers
are `keepAlive` providers; buffer-scoped viewmodels are auto-dispose families keyed
by `BufferId` (§4.4, §10). `get_it` is dropped.

## 9. Open items (future sections)

- **Layers 4–6** — controller / service / repository: responsibilities, granularity,
  file placement, the hot/cold rule (`ValueListenable` for owned state,
  `Future<Result<E, T>>` for one-shot ops, streams never).
- **Mediator / offline-first contract** — injectable offline implementation, sync &
  outbox designed upfront; today's mediator (`OnlineAPI` hard-constructed, offline
  stub) is the problem statement, not the spec.
- **API-availability guards** — replacement for `Guard<Mediator, Bundle, State,
  Reason>`.
- **EventCenter** — event bus story (streams allowed internally? rebuilt on
  listenables?) — parked.

## 10. Page management — buffers, windows, tabs

The navigation model is **neovim**: buffers hold state, windows show buffers,
tabs arrange windows, OS windows host tabs. Decided 2026-09.

### 10.1 Vocabulary

| neovim | reef |
|---|---|
| Buffer (content, independent of views) | materialized buffer: `ViewModel` + `Model` + ephemeral UI objects, keyed by `BufferId`; the quartet defines the buffer *type*; the hibernation JSON is the "file" |
| Window (viewport on a buffer) | `ReefWindow` widget instance bound to one buffer id |
| Two splits, one buffer, live-synced edits | two windows, one buffer → same family viewmodel → same `ValueListenables`; sync comes free from the contract (§5) |
| Tab (window layout) | split-tree of windows: leaves = (bufferId, layout params), nodes = orientation + ratios; serializable (Phase C) |
| `:ls` buffer list | alive-buffer registry (Phase B, with the hibernation store) |
| Multi-window (OS) | one engine, one isolate, many windows (Phase D, shipped in W4): buffers are plain shared state — no protocol needed |

### 10.2 Buffer lifetime — hybrid (shipped, Phase B)

- **Default:** the last window on a buffer closing disposes its provider
  (auto-dispose family); the dispose hook (`hibernateOnDispose`) serializes
  the model JSON into the [HibernationStore]. Reopening the same id
  rematerializes from that JSON (`hibernatedSeed` feeds the provider's
  `initial`) — or fresh if none.
- **`pinned`** buffers stay materialized until an explicit close-buffer intent
  (the `:bd` equivalent). The [BufferRegistry] tracks the flag; keeping a
  pinned buffer alive is done app-side with a keepAlive anchor provider.
- Shipped pieces: `HibernationStore` (in-memory default, overridable
  `hibernationStoreProvider`; the interface is synchronous — disk-backed
  stores preload before the provider runs) and `BufferRegistry` (the `:ls`:
  alive buffers in creation order as a `ValueListenable`), wired via the
  `trackBuffer` provider hook. Seed priority: the hibernated JSON wins over
  any fresh-construction seed (`hibernatedSeed ?? initial`) — a
  rematerialized buffer restores its hibernated model.

### 10.3 Layering — on top of navigation (W5)

Windowing is router-agnostic: `WindowingRoot` renders the windowing doc
through the app's buffer builder (windowing design spec §5). The old
split-tree router adapter was deleted in W0; `reef_router` rebuilds deep
links (spec §9) on the windowing model (ADR 0003).

### 10.4 Multi-window (shells) — shipped (W4)

Upstream: `flutter/flutter#30701`. Flutter's windowing runs **one engine,
one isolate, many shells**: each shell is a `View` in the same
`ViewCollection`. The §7 serializable model stays persistence and
hibernation only, *not* a cross-shell protocol. The same buffer in two shells
is the same family viewmodel; live sync comes free from the contract (§5).

The spike graduated (windowing design spec §7). Reef core owns the
`ShellPlatform` seam, `ShellError`, `FakeShellPlatform`,
`controller.capabilities` and the `openShell` / `popOutTab` intents. The
`reef_multi_window` package holds the only imports of Flutter's internal
windowing library and exposes two things: `RealShellPlatform` and the root
widget `ShellViews`. The example app runs on it from its single `main`:
`runWidget(ProviderScope(WindowingRoot(child: ShellViews(...))))`.

**Native close** goes through the doc: with more than one shell the platform
close button calls `closeShell`, so an interceptor can veto it. The last
shell's close button exits the app without asking the interceptor.

**Enablement:** Flutter master channel; per-invocation env override
`FLUTTER_WINDOWING=true` (the tool's `environmentOverride` for the feature).
Do **not** use the global `flutter config --enable-windowing`: it injects the
flag into `flutter test` too, where the Win32 windowing owner FFI-initializes
inside `flutter_tester` and every widget test fails to load. The
`FLUTTER_ENABLED_FEATURE_FLAGS` dart-define is tool-reserved. Widget tests of
the adapter switch the flag on in-test over flutter_test's own windowing
owner (see `reef_multi_window/test/shell_views_test.dart`).

**Testing:** unit and widget tests over `FakeShellPlatform` and the in-test
flag; the example's integration flow without the flag (inline, no pop-out
controls); the manual multi-shell checklist (`docs/multi-shell-checklist.md`)
for what tests cannot see, including the multi-shell flow on real shells:
`flutter test integration_test` does not load with the flag set.

**Still open:** a veto for the last shell's close (confirm before quit), and
reopening real shells from a restored doc beyond what `ShellViews` does at
mount (W5).

### 10.5 Roadmap

- **Phase A — shipped.** `BufferId` (uuid v7), `ReefScope`,
  `ReefWindow` + `ReefBufferScope`, family-keyed buffer providers.
- **Phase B — shipped.** Hibernation store (in-memory default, overridable),
  pinned flag, alive-buffer registry (`:ls`), auto-hibernate + restore.
- **Phase C — replaced.** The split-tree layout and its auto_route adapter
  were superseded by the windowing model (shells, tabs, windows; see the
  windowing design spec) and deleted. Router deep links return in W5.
- **Phase D — shipped (W4).** Multi-shell on Flutter master (§10.4): buffers as
  plain shared state across shells, `ShellPlatform` in reef core and the
  `reef_multi_window` adapter.
