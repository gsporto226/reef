# Reef API notes from the mail client

Friction found while building this app on reef's public API: weird usage,
missing features, workarounds. Each entry says what the app had to do and
what reef could offer instead.

## 1. No way to build a starting layout without a controller

To start on a layout other than `WindowingDoc.initial()`, an app builds a
throwaway `WindowingController`, runs intents on it, reads `doc.value`, and
disposes it (`startingLayout` in the example does the same). The intents
need ids that only the controller generates.

Could offer: a doc builder or `WindowingDoc.apply(commands)`, so a layout is
a fold of commands without a controller.

## 2. Writing an open policy means re-deriving private helpers

`defaultOpenPolicy` and friends use the private `_activeTab(doc)`. An app's
own `WindowingOpenPolicy` has to rebuild "the focused shell's active tab"
from `doc.shells[doc.focusedShellId]!.activeTabId`.

Could offer: `doc.activeTab` / `doc.activeWindowId` getters on
`WindowingDoc`.

## 3. No "which window shows buffer X" lookup

Finding the window that shows a buffer (here, the folder list) means
scanning `doc.windows` by `history.current`. `defaultLinkPolicy` does the
same scan inline.

Could offer: `doc.windowsShowing(buffer)`.

## 4. The app can't ask whether the doc was restored

A cold-start notification on a fresh install should build its window into
an empty doc, while a normal first run gets the app's default layout. The
controller picks restore over `initial` internally and does not report
which one it used, so the app peeks `store.load(WindowingController.hibernationKey)`
before constructing the controller.

Could offer: `controller.restored`, or `initial` as a callback that only
runs when nothing was restored.

## 5. Wrapping the root's default shell means rebuilding it

Without a `child`, `WindowingRoot` draws the focused shell. Adding
`WindowingSystemBack` around it means passing a `child`, which drops that
default. The app re-creates it with a `ValueListenableBuilder` over the doc
picking `focusedShellId`, and rebuilds on every doc change where the root
uses a private selector.

Could offer: a public `FocusedShellProjection` widget, or a `wrap` hook on
the root.

## 6. Buffer kinds are a string convention with no accessors

`LinkTable` defines buffer ids as `kind:token`, but `BufferId` has no
`kind` or `token`. The app's `bufferBuilder` splits `buffer.id` at the first
`:` itself, and builds ids with `BufferId.manual('thread:$id')`, a format
reef owns but doesn't expose.

Could offer: `BufferId.of(kind, token)` with `kind` / `token` getters, used
by `LinkTable` too.

## 7. The default tab strip can't be hidden on compact

The app has one tab, so the default strip ("Tab 1 ×") is noise. 
`DesktopProjection` takes `showTabStrip: false`; `TabbedProjection` has no
switch, so hiding it means a custom `projectionPolicy` that re-states
`defaultWindowingProjection`'s breakpoint. The `×` also offers to close the
shell's only tab, which `CloseTab` refuses anyway.

Could offer: `showTabStrip` on `TabbedProjection` (or on the delegate), and
a default strip that hides the close button on a shell's last tab.

## 8. An app-wide focus policy only does half of "back on compact"

On compact, the folder list and the detail window are siblings in one tab.
Back at the bottom of the detail history should go to the folder list, but
`EmptyBackAction` only offers nothing, close window, or unhandled. The app
uses `unhandled` and gives the thread list a "Folders" button instead.

Could offer: `EmptyBackAction.focusPrevious` (the window focused before),
or `emptyBack` as a callback returning commands, like `focusAfterClose`.
