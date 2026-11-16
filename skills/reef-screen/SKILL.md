---
name: reef-screen
description: How to build a screen in a reef app — the Page/Model/ViewModel/Provider quartet, bindings, forms and async builders. Use when creating or changing a screen, dialog, form or viewmodel.
---

# Building a reef screen

A screen is four files plus its layouts:

```
_presentation/<screen>/
  <screen>_page.dart
  <screen>_model.dart
  <screen>_viewmodel.dart
  <screen>_provider.dart   (+ .g.dart)
  _layouts/                responsive variants
  _widgets/
```

Done when: every file exists, each holds only what its row below allows, and
the screen's tests pass.

| File | Holds | Never holds |
|---|---|---|
| Page | `ReefWindow` + `ScreenTypeLayout`; passes the viewmodel to the layout | State, logic |
| Model | `@freezed` immutable domain state with `fromJson` | `Async`/`Result`/`Optional` fields, Flutter types, I/O |
| ViewModel | The model, UI objects, every `Operation`, all async and error state | Layout |
| Provider | Builds model → viewmodel, hands it the app's dependencies, `ref.onDispose` | Business logic |

## Model

- Change state through pure named methods `with<Field>(value)` returning the
  new model. A change that can fail returns `Result<E, Model>`.
- `copyWith` only for mechanical field diffs. Rules and invariants live in the
  named methods, once.
- Multi-state domains are freezed unions, switched exhaustively.
- Serializable, because buffers hibernate as JSON.

## ViewModel

Extends `ViewModel<M>`.

- Out-bindings carry a `$` prefix and derive from `$model` with
  `listenable_plus` (`$model.select((m) => m.title)`).
- In-bindings are intents: `onSave()`, `onSelect(id)`.
- Only `publish`/`edit` replace the model. Fallible changes go through
  `edit(result, via: op)`.
- Owns `TextEditingController`, `FocusNode` and formularium fields, seeded from
  the model in the constructor.
- Link UI and model with `bind`, `bindText` or `bindField`; they break echo
  loops themselves.
- Run one-shot work with `op.run(() => dependency.action(...))`. Expose a
  dependency's `ValueListenable` as an out-binding.

## Forms

Every validated input is a formularium field.

- The field's validator calls the model's named method, so a rule exists in
  one place.
- Live screens bind with `bindField` and apply on `Valid`.
- Submit screens call `validate()` on every field, then run the save.

## Rendering

- Wrap listenables in `ValueListenableBuilder`; builders take values.
- `AsyncResultBuilder` renders `Async<Result<E, T>>`: idle and pending show the
  real layout fed with a `sample`, wrapped in the app's skeleton widget; `Err`
  shows the localized error.
- `ScreenTypeLayout` picks the variant: < 600 mobile, 600–839 tablet, ≥ 840
  desktop.

## Provider

A buffer-keyed auto-dispose family:

```dart
@riverpod
TaskEditViewModel taskEditViewModel(Ref ref, {required BufferId bufferId, TaskEditModel? initial}) {
  final vm = TaskEditViewModel(
    initial ?? const TaskEditModel(),
    saveTask: ref.watch(saveTaskProvider),
  );
  ref.onDispose(vm.dispose);
  return vm;
}
```
