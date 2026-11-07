---
status: accepted
---

# Three test layers, 100% merged coverage

Every change ships with unit, widget, and integration tests. The combined line
coverage of the code the change touches must be 100%. We count coverage on the
merged lcov of all three layers instead of per layer. Each layer covers what it
is good at, and no layer has to duplicate another's work to reach a quota.

- **Unit** (`test/`, no Flutter bindings): pure logic such as reducers,
  controllers, and value types.
- **Widget** (`test/`, `testWidgets`): rendering units and how they interact
  with controllers.
- **Integration** (`integration_test/`, real device or desktop): end-to-end
  flows in the example app.

A line counts as covered if any layer hits it. An uncovered line gets a test,
never a coverage-ignore comment.

## Consequences

- A change with no UI still needs a thin widget test and one integration flow.
  Covering the lines is not enough; all three layers must exist.
- The merged lcov has to be produced and checked by a script, not by hand.
- Integration tests that need multi-window set `FLUTTER_WINDOWING=true` for
  that one invocation only. The global `flutter config --enable-windowing` flag
  breaks `flutter test` on Windows (`packages/reef/docs/blueprint.md` §10.4).
