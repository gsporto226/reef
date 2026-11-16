---
status: accepted
---

# Multi-window is experimental

Flutter's windowing API is unstable: it needs the master channel and a
per-invocation `FLUTTER_WINDOWING=true`, its test binding has no real
windows, and it lacks window placement, z-order and touch capture. Reef's
real multi-window support is rough as a result. We mark it experimental and
develop it as the Flutter API matures, instead of holding reef's stable
surface and the integration apps to it.

## Decision

- **Stable:** the multi-shell doc model in reef core (shells, `ShellPlatform`,
  `FakeShellPlatform`, `canPopOut`, the last-tab rule) and docking within
  one view (ADR 0012). Apps test multi-shell behaviour over
  `FakeShellPlatform`.
- **Experimental:** `reef_multi_window` (`RealShellPlatform`, `ShellViews`)
  and docking across platform windows (`ShellPlatform.viewOrigin`). Their
  public API is annotated `@experimental` and may change without a
  superseding ADR.
- Apps use real multi-window only when launched with
  `FLUTTER_WINDOWING=true`. Without it they run one platform window and
  their pop-out UI hides (`canPopOut` is false).
- Integration flows that need real platform windows are experimental flows.
  They do not count toward an app being done (`docs/integration-apps.md`)
  or toward the merged coverage gate (amends ADR 0001). They still run,
  with `FLUTTER_WINDOWING=true`, to track the Flutter API.

## Consequences

- Each multi-shell acceptance flow needs a widget test over
  `FakeShellPlatform`, which is what proves it.
- Lines only reachable with real platform windows are excluded from the
  merged gate by file, not by coverage-ignore comments.
