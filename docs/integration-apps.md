# Integration apps

Five small apps under `apps/<name>/` that validate reef's windowing in real use.
Each app exercises one part of the windowing spec
(`packages/reef/docs/specs/2026-09-02-windowing-design.md`). Each one is part
of the workspace and has its own `integration_test/`. Coverage from these
tests counts toward the merged gate (ADR 0001).

Rules for every app:

- Build only on reef's public API. If an app needs an internal, that is an API
  gap: fix reef, not the app.
- Keep scope to what the app's column validates. Features listed as out of
  scope stay out.
- An app is done when its acceptance flows run green as integration tests.
- The apps are planned for phase W6. Start an app when the phases it
  depends on have landed.

| App | Folder | Depends on | Validates |
|---|---|---|---|
| Vim editor | `apps/vim_editor` | W1–W3 | splits, one buffer in many windows, window history, layout and content undo, keyboard-only control |
| Mail client | `apps/mail_client` | W3, W5 | layout switch by screen class over one doc, back = window back, notification deep links |
| Design inspector | `apps/design_inspector` | W1–W3 | floating windows at all three scopes, dock with target and side, z-order |
| Terminal multiplexer | `apps/multiplexer` | W1, W4, W5 | moving windows and tabs across shells, pop-out, layout restore after restart |
| Browser | `apps/browser` | W1–W5 | all windowing features against real web pages: typed links, guards, history, splits, floats, pop-out, undo, restore |

## Vim editor

A modal plain-text editor. Its vim commands are app code built on reef
intents. Reef exposes no vim idioms (spec §1), so this app proves the intents
are enough.

In scope: normal and insert modes; `h j k l w b 0 $ gg G`; `i a o x dd u
Ctrl-R`; `:e`, `:w`, `:q`, `:split`, `:vsplit`, `:tabnew`, `:tabn`, `:tabp`,
`:ls`, `:b`; `Ctrl-W h/j/k/l/c/o`; `Ctrl-O`, `Ctrl-I`. Files come from an
in-memory file system seeded at boot.

Out of scope: visual mode, registers, macros, search, syntax highlighting,
plugins, real disk access.

Acceptance flows:

1. `:vsplit` shows the same buffer in two windows; typing in one updates the
   other live.
2. `:split` copies the window history: `Ctrl-O` in the new window returns to
   the same previous buffer as in the original.
3. `u` after `:vsplit` undoes the split; `u` after an edit undoes the edit;
   both go through the one global timeline.
4. `:q` on a tab's last window leaves the tab empty (spec §2), and `:tabn`
   still cycles.
5. `:e` on a buffer already open elsewhere reuses it (`openPolicy`).

## Mail client

Folders, a thread list, and threads. One doc, two layouts.

In scope: folder list, thread list, thread view, compose draft sent to a
local Sent folder; search as a buffer on the list window; desktop
master-detail and compact stack; a simulated push notification.

Out of scope: networking, accounts, attachments, rich text.

Acceptance flows:

1. Resizing the shell from expanded to compact switches desktop to tabbed
   projection without changing the doc.
2. On compact, system back pops the window history; on an empty history,
   `focusPolicy` decides.
3. A notification for `/threads/42` on a fresh install builds shell → tab →
   window showing that thread.
4. The same notification on a restored doc focuses or pushes, per
   `linkPolicy`, without losing the restored layout.

## Design inspector

A canvas of shapes with layers, properties, and color panels.

In scope: canvas buffer; layers and properties panels as floating windows
scoped to the shell, the tab, or the canvas window; float, dock, raise; panel
positions as geometry hints.

Out of scope: real drawing tools, export, multi-select, snapping beyond what
the delegate example needs.

Acceptance flows:

1. Floating a tree window and docking it beside a target on each side lands it
   in the right tree slot.
2. Docking into an empty tab makes the window the whole tree.
3. Raising a panel changes its z-order only within its own scope.
4. Closing the canvas window removes the panels scoped to it, and nothing
   else.
5. A veto from the interceptor (max panels) leaves the doc untouched.

## Terminal multiplexer

Fake terminal sessions arranged tmux-style. The sessions are scripted output,
not real processes.

In scope: sessions as buffers; split, move windows and tabs between tabs and
shells; pop a tab out into a new shell; quit and relaunch with the layout
restored.

Out of scope: real PTYs, shell integration, scrollback search.

Acceptance flows:

1. Moving a window to a tab in another shell is one undo step.
2. Popping out a tab opens the real shell before the doc claims it; on a
   platform without multi-shell support the doc stays untouched.
3. Closing a shell keeps buffers that are also shown in another shell alive.
4. Quitting and relaunching restores shells, tabs, trees, ratios, and focus.

## Browser

A web browser on Windows: real pages rendered by `flutter_inappwebview`
(WebView2) inside reef windows. reef owns every navigation and all history;
the webview only renders the current history entry. Each browser tab is a
reef tab, and each shell's address bar is that shell's
`RouteInformationProvider` (per-shell `WindowingLinkSync`).

In scope: `WebPage` at `/web/{scheme}/{host}/**` with the site's whole query
as one opaque argument; internal pages `/` (new tab, fresh), `/history`,
`/bookmarks`, `/settings` (guarded) and a root `/**` not-found; link click,
redirect, `pushState`/`replaceState` and `target=_blank` mapped onto reef's
verbs; tabs, splits, independent and mirror views, PiP, find and downloads
floats, dock, pop-out, undo and session restore.

Out of scope: cookies and profiles, incognito, real downloads, devtools,
extensions, password autofill, scroll and form state across back/forward,
Linux, macOS, mobile, Flutter web, a separate history or bookmarks store.

Acceptance flows (against an in-test localhost server, never the internet):

1. A link click pushes, a 302 replaces and `pushState` pushes. Back and
   forward land on the right entry in each case.
2. Each shell's address bar follows its focused window, and typing into one
   shell's bar leaves the other's unchanged.
3. Opening an already-open URL focuses it, and Ctrl+click makes an
   independent view.
4. In a mirror split, scrolling or typing in one view updates the other live.
5. Dragging a tab out makes a new shell with its own bar and history, and
   dragging it back restores it.
6. Ctrl+Shift+T reopens a closed tab through the global undo.
7. The `/settings` guard redirects while locked and re-checks when the lock
   clears.
8. Restart restores the session, and a cold-start URL opens on top.
9. A PiP float docks left or right, and z-order holds at all three scopes.
