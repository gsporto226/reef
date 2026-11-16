---
name: reef-architecture
description: The reef app architecture — what reef owns (pages to viewmodels), its packages and its banned tools. Use before creating or changing a screen, viewmodel or provider in a Flutter app built on reef.
---

# Reef app architecture

Reef owns the presentation side of an app:

```
Page → ViewModel → (the app's own layers)
```

Everything the viewmodel calls is the app's design. Look for the app's own
rules (its `CLAUDE.md`/`AGENTS.md` and skills) before writing below the
viewmodel. The provider hands those dependencies to the viewmodel.

To build a screen, invoke `reef-screen`.

## Packages

| Package | Use it for |
|---|---|
| `reef` | `ViewModel`, `Operation`, `bind`/`bindText`/`bindField`, `ReefWindow`, `AsyncBuilder`/`ResultBuilder`/`AsyncResultBuilder`, `ScreenTypeLayout` |
| `reef_fp` | `Result` (`Ok`/`Err`), `Either`, `Optional`, `Async` (`Idle`/`Pending`/`Ready`), `Unit` |
| `listenable_plus` | Derived state: `map`, `select`, `where`, `distinct`, `debounceTime`, `combineWith`, `switchListen` |
| `formularium` | Every form field and its validation |
| `riverpod` (codegen) | Composition and lifetimes; the only DI |

## Hard rules

1. **Listenables, never streams.** State is `ValueListenable`; one-shot work is
   a `Future`. No rxdart, no `Stream` in an API the viewmodel sees, no
   `StreamBuilder`, no `get_it`.
2. **Async state is a value:** `ValueListenable<Async<Result<E, T>>>`.
3. **Errors are values:** fallible code returns `Result<E, T>`; widgets render
   state and never catch.
4. **The viewmodel mediates.** Widgets are pure views over listenables.

## Folders

Feature-first, underscore-prefixed folders. Screens live under
`lib/features/<feature>/_presentation/<screen>/`; the app decides the rest.
