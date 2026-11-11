# Multi-shell manual checklist

Automated tests cannot see real shells: flutter_test's windowing owner stands
in for the platform in widget tests, and `flutter test integration_test`
fails to load any suite when `FLUTTER_WINDOWING=true` is set (checked on
Flutter master `ee0e68f2e1`, Windows). Run this checklist by hand before
merging a change to `reef_multi_window`, the shell intents, or the example
app's shell controls.

## Start the example

Set the flag for this one process only. Never enable windowing through the
global Flutter config.

```powershell
$env:FLUTTER_WINDOWING = "true"
cd packages/reef/example
fvm flutter run -d windows
```

The app opens one shell on the task list, with the "New shell", "Pop out
tab" and "Close shell" controls at the top.

## Checks

1. **Open.** Tap "Buy milk", then "Open in window" in the editor. A second
   shell opens, focused, showing the "Buy milk" editor. Tap "New shell": a
   third shell opens with an empty tab.
2. **Move to another monitor.** Drag the second shell to another monitor.
   It draws at that monitor's scale and stays responsive.
3. **Live edit across shells.** In the second shell, change the title to
   "Buy bread". The editor in the first shell shows "Buy bread" as you type.
   Undo in either shell reverts both.
4. **Close from the chrome.** Tap "Close shell" in the third shell. It
   closes; the other shells stay.
5. **Pop out tab.** In a shell with two tabs, tap "Pop out tab". The active
   tab leaves the shell with its windows and opens in a new shell. In a
   shell with one tab, nothing happens.
6. **Native close.** With two or more shells open, click the platform close
   button on a secondary shell. It closes; the others stay.
7. **Vetoed close.** In the example, set `controller.interceptor` to return
   `CommandDecision.veto(...)` for `CloseShell` and approve everything else,
   then hot restart. Click the platform close button on a secondary shell.
   It stays open. Remove the interceptor afterwards.
8. **Last-shell close quits.** Close shells until one is left, then click
   its platform close button. The app exits.

## Restore on real shells

The example saves its layout and its buffers to
`reef_example_hibernation.json` next to the executable.

1. **Restore.** Open a second shell with "Open in window", split or open a
   task in the first shell, then close the app from the last shell's
   platform close button. Start it again. Both shells open with the same
   tabs, windows, focus and task titles.
2. **Edited buffers.** Change a task title, quit, and start again. The
   editor shows the changed title.
3. **Reset layout.** Tap "Reset layout". The app shows the first-run
   layout, one shell on the task list. Quit and start again: the first-run
   layout comes back.

## Launch-argument link

Start the example with a task path as its first argument:

```powershell
fvm flutter run -d windows -a "/tasks/Buy milk/edit"
```

The saved layout restores first. Then the "Buy milk" editor opens beside
the list, or its window is focused if a window already shows it. A path
that matches no template changes nothing.

## Browser pass for URL sync

Run the example on web (no flag needed; web has one shell):

```powershell
fvm flutter run -d chrome
```

1. **Push.** Tap "Buy milk". The address bar shows `/tasks/Buy%20milk/edit`
   and the browser history gets a new entry.
2. **Replace on focus.** Open a second task, then click the window of the
   first one. The address bar shows the first task's path, and no new
   history entry is added.
3. **Typed URL.** Type `/tasks/Walk dog/edit` in the address bar. The "Walk
   dog" editor opens.
4. **Unknown path.** Load `/nowhere`. The address bar changes to the
   focused task's path, or stays unchanged when the focused buffer has no
   path (the task list has none).
5. **Browser back.** Press browser back. The previous entry's task opens or
   is focused. Window histories are not traversed (spec §9).

## Windowing playground

Start it with the flag set as above:

```powershell
fvm flutter run -t lib/main_windowing.dart -d windows
```

On a first run it opens one shell showing the "welcome" buffer, with "New
shell" in the shell bar and "Pop out tab" in the tab bar. Later runs restore
the saved layout from `reef_playground_hibernation.json` next to the
executable. Delete that file to start from the first-run layout.

1. **New shell.** Tap "New shell". A second shell opens with an empty tab,
   and both shells show "Close shell".
2. **Pop out keeps the tab.** In the first shell, tap "Open new buffer",
   "Split right", then "Float" > "Float over tab" on one window, then
   "New tab" and go back to tab 1. Tap "Pop out tab". Tab 1 opens in a new
   shell with its split, its floating window and its Back history.
3. **Projection by size.** Make the popped-out shell narrow: it switches to
   the tabbed projection while the wide shells stay on desktop.
4. **Vetoed close.** In a shell with two tabs, tap "Close shell", then click
   its platform close button. Each time it stays open and the status bar
   shows "Vetoed: Close the shell's other tabs first".
5. **Close.** Close a one-tab shell from "Close shell" and another from the
   platform close button. Each closes without a "Window has been destroyed"
   error in the console.
6. **Without the flag.** Run without `FLUTTER_WINDOWING`. The focused shell
   draws inline, and "New shell" and "Pop out tab" are gone.
