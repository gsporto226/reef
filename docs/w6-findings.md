# W6 findings

Issues in reef found while building the integration apps
(`docs/integration-apps.md`). Log here as you hit them; decide at the end of
W6 what becomes a fix, an ADR, a GitHub issue, or `wontfix`.

Rules:

- One entry per finding. Don't work around it silently in the app: if the
  app needs a workaround, note it in the entry and mark it in code with
  `// W6-<id>`.
- Log against reef, not the app. App bugs don't go here.
- Keep the repro minimal: the intent/call sequence and what happened.
- Save every repro as a test in the reef package it hits, at
  `packages/<pkg>/test/w6/w6_<id>_test.dart`. It asserts the expected
  behaviour and carries `skip: 'W6-<id>'` until fixed. The fix removes the
  skip. Prose-only repros are allowed for `spec` findings and for gaps whose
  API does not exist yet (a test could not compile); there the app's
  `// W6-<id>` workaround is the repro.

Kinds: `bug` (wrong behaviour), `gap` (public API can't express it),
`ergonomics` (possible but painful), `spec` (spec unclear or contradicts code),
`perf`.

Severity: `blocker` (acceptance flow can't pass), `major`, `minor`.

| ID | App | Kind | Severity | Package | Summary | Workaround | Decision |
|---|---|---|---|---|---|---|---|
| W6-1 | vim_editor, mail_client | ergonomics | minor | reef | `WindowingDoc.initial()` can't start with a buffer | doc built by hand | fixed: `initial(buffer:)`, `doc.applyAll(commands)` |
| W6-2 | vim_editor | gap | minor | reef | no query for the window beside another (left/below/…) | tree walked in app | fixed: `doc.neighbour(window, direction)` |
| W6-3 | vim_editor | spec | major | reef | buffer navigation is recorded on the undo timeline | none, `u` undoes `:e` | fixed: history-only batches don't record (spec §4) |
| W6-4 | mail_client | ergonomics | minor | reef | no `activeTab` / `activeWindowId` on the doc | re-derived in app | fixed: `doc.activeTab`, `doc.activeWindowId` |
| W6-5 | mail_client | gap | minor | reef | no "which window shows buffer X" lookup | scan in app | fixed: `doc.windowsShowing(buffer)`, `doc.tabOf(window)` |
| W6-6 | mail_client | gap | major | reef | app can't tell whether the doc was restored | peeks the store | fixed: `initial` is a callback, run only without a restore (spec §11) |
| W6-7 | mail_client | ergonomics | minor | reef | wrapping the root's default shell rebuilds it | none needed now | wontfix: no longer hit |
| W6-8 | mail_client | ergonomics | minor | reef | `BufferId` has no `kind` / `token` | splits the id in app | fixed: `BufferId.of`, `kind`, `token`; `LinkTable` uses them |
| W6-9 | mail_client | gap | minor | reef | `TabbedProjection` can't hide the tab strip; × on the last tab | custom projection policy | fixed: `showTabStrip`; default strip drops × on a last tab (mail keeps its own policy) |
| W6-10 | mail_client | gap | major | reef | `emptyBack` can't focus another window | `unhandled` + a button | fixed: `emptyBack` is a commands callback (spec §8) |
| W6-11 | mail_client | gap | minor | reef | any pointer down activates its window | tracks last non-nav window | fixed: `WindowHost(activateOnPointer:)` |
| W6-12 | mail_client | spec | minor | reef | `WindowHost` needs bounded constraints | fixed-size slot | doc: a window fills its slot |
| W6-13 | mail_client | ergonomics | minor | reef | no way to address a window by role | `mailWindows` re-derives | covered by W6-4 and W6-5 |

## Details

### W6-1: `WindowingDoc.initial()` can't start with a buffer

- **App / flow:** vim_editor, boot
- **Repro:** start a controller on one tab showing buffer `a`.
- **Expected:** `WindowingDoc.initial(buffer: a)` or similar.
- **Actual:** build shell/tab/window/history by hand, or (the example's
  `startingLayout`) run a throwaway controller with `newTab` + `closeTab`.
- **Workaround:** `apps/vim_editor/lib/vim.dart` `startingDoc`, W6-1

### W6-2: no query for the window beside another

- **App / flow:** vim_editor, `Ctrl-W h/j/k/l`
- **Repro:** in a tab split three ways, find the window left of the active one.
- **Expected:** a tree query (e.g. `neighbour(root, window, direction)`); any
  keyboard-driven tiling app needs it, not only vim.
- **Actual:** the app lays the tree out in a unit square from the ratios and
  compares rectangles (~40 lines).
- **Workaround:** `apps/vim_editor/lib/vim.dart` `neighbour`, W6-2

### W6-3: buffer navigation is recorded on the undo timeline

- **App / flow:** vim_editor, flow 3 (`u` goes through the one timeline)
- **Repro:** `packages/reef/test/w6/w6_3_test.dart`. `x`, `:e b.txt`, `u`.
- **Expected:** `u` undoes the `x`; `:e` stays (vim: navigation is not an
  edit). Spec §4 exempts only focus-only changes; it calls the doc entries
  "layout undo", and §8 treats window history as navigation, so the spec is
  ambiguous.
- **Actual:** any `PushBuffer`/`PopBuffer`/`ReplaceBuffer`/`NavigateForward`
  batch records a `WindowingDoc` entry, so `u` returns to `a.txt` and the
  `x` needs a second `u`. No per-batch opt-out exists.
- **Options:** treat history-only changes like focus-only ones (skip
  recording), or add `dispatchAll(..., record: false)`.
- **Workaround:** none; `apps/vim_editor/integration_test/vim_test.dart`
  skips the case.

### W6-4 to W6-13: mail client

Repros and workarounds: `apps/mail_client/API_NOTES.md` §2 to §11 on
`design/mail-client-spec`, in that order. The app uses the new API; its
`API_NOTES.md` Status table says what each fix replaced.

<!--
### W6-1: <summary>

- **App / flow:** vim_editor, flow 2
- **Repro:** ...
- **Expected:** ... (spec §x)
- **Actual:** ...
- **Workaround:** none | `apps/.../file.dart` W6-1
-->
