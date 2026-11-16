---
status: accepted
---

# App entrypoints are outside the coverage gate

Amends ADR 0001 and extends ADR 0013. Once the gate collects app packages,
an app's `main()` and the branch that mounts real platform windows
(`RealShellPlatform`, `ShellViews`) fail it: tests build the app with a
fake platform, and real windows are experimental. We exclude these lines
by file: each app keeps them in `lib/entry.dart`, which only wires the real
platform and calls `runWidget`, and the gate skips `apps/*/lib/entry.dart`.

## Decision

- `lib/entry.dart` holds `main()` and the real-platform wiring, and nothing
  a test could reach. Everything else stays gated.
- Code that only runs in a live webview stays gated and is covered by the
  app's integration tests.
- There are still no coverage-ignore comments.
