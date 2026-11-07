import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reef/reef.dart';

import '_support/windowing_table.dart';

const s1 = ShellId.manual('s1');
const s2 = ShellId.manual('s2');
const t1 = TabId.manual('t1');
const t2 = TabId.manual('t2');
const t3 = TabId.manual('t3');
const w1 = WindowId.manual('w1');
const w2 = WindowId.manual('w2');
const w3 = WindowId.manual('w3');
const b1 = BufferId.manual('b1');
const b2 = BufferId.manual('b2');
const b3 = BufferId.manual('b3');
const l1 = WindowLeaf(w1);
const l2 = WindowLeaf(w2);
const l3 = WindowLeaf(w3);

WindowState showing(BufferId buffer) =>
    WindowState(history: BufferHistory(current: buffer));

/// A doc whose shells are given as `{shell: (tabs, active)}`; tabs listed in
/// [windows] hold that one window, the others are empty.
WindowingDoc doc(
  Map<ShellId, (List<TabId>, TabId)> shells, {
  ShellId focused = s1,
  Map<TabId, WindowId> windows = const {},
}) =>
    WindowingDoc(
      shells: {
        for (final MapEntry(key: id, value: (tabs, active)) in shells.entries)
          id: ShellState(tabIds: tabs, activeTabId: active),
      },
      tabs: {
        for (final (tabs, _) in shells.values)
          for (final t in tabs)
            t: TabState(
                root: windows[t] == null ? null : WindowLeaf(windows[t]!),
                activeWindowId: windows[t]),
      },
      windows: {for (final w in windows.values) w: showing(b1)},
      focusedShellId: focused,
    );

WindowBranch h(List<WindowNode> children, [List<double>? ratios]) =>
    WindowBranch(
        axis: Axis.horizontal,
        children: children,
        ratios: ratios ?? [for (final _ in children) 1 / children.length]);

WindowBranch v(List<WindowNode> children, [List<double>? ratios]) =>
    WindowBranch(
        axis: Axis.vertical,
        children: children,
        ratios: ratios ?? [for (final _ in children) 1 / children.length]);

/// One shell `s1` with tab `t1` holding [root]; every window shows [b1]
/// unless [windows] says otherwise.
WindowingDoc tree(WindowNode? root, WindowId? active,
        {Map<WindowId, WindowState> windows = const {}}) =>
    WindowingDoc(
      shells: {s1: ShellState(tabIds: [t1], activeTabId: t1)},
      tabs: {t1: TabState(root: root, activeWindowId: active)},
      windows: {
        for (final w in root?.windowIds ?? const <WindowId>[])
          w: windows[w] ?? showing(b1),
      },
      focusedShellId: s1,
    );

final history = WindowState(
    history: BufferHistory(back: [b2], current: b1, forward: [b2]));

void main() {
  test('a fresh doc is one focused shell with one empty tab', () {
    final fresh = WindowingController().doc.value;
    expect(fresh.shells, hasLength(1));
    final shell = fresh.shells[fresh.focusedShellId]!;
    expect(shell.tabIds, [shell.activeTabId]);
    expect(fresh.tabs[shell.activeTabId], const TabState());
    expect(fresh.windows, isEmpty);
    expectInvariants(fresh);
  });

  test('the doc is immutable and has value equality', () {
    final a = doc({s1: ([t1], t1)}, windows: {t1: w1});
    final b = doc({s1: ([t1], t1)}, windows: {t1: w1});
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(doc({s1: ([t1], t1)})));
    expect(() => a.shells[s2] = a.shells[s1]!, throwsUnsupportedError);
    expect(() => a.shells[s1]!.tabIds.add(t2), throwsUnsupportedError);
    expect(() => a.tabs.clear(), throwsUnsupportedError);
    expect(() => a.windows.clear(), throwsUnsupportedError);
    expect(() => (showing(b1).history.back as List).add(b1),
        throwsUnsupportedError);
    expect(showing(b1), showing(b1));
    expect(showing(b1).hashCode, showing(b1).hashCode);
    expect(ShellState(tabIds: [t1], activeTabId: t1).hashCode,
        ShellState(tabIds: [t1], activeTabId: t1).hashCode);
    expect(const TabState(root: l1, activeWindowId: w1).hashCode,
        const TabState(root: l1, activeWindowId: w1).hashCode);
    expect(l1.hashCode, const WindowLeaf(w1).hashCode);
    expect(h([l1, l2]), h([l1, l2]));
    expect(h([l1, l2]).hashCode, h([l1, l2]).hashCode);
    expect(h([l1, l2]), isNot(v([l1, l2])));
    expect(() => h([l1, l2]).ratios.add(0), throwsUnsupportedError);
    expect(() => h([l1, l2]).children.add(l3), throwsUnsupportedError);
  });

  runTable('NewTab', [
    (
      name: 'appends an empty tab and activates it',
      start: doc({s1: ([t1], t1)}),
      commands: [const NewTab(shellId: s1, tabId: t2)],
      expected: doc({s1: ([t1, t2], t2)}),
    ),
    (
      name: 'with a buffer, creates the first window with a window history',
      start: doc({s1: ([t1], t1)}),
      commands: [const NewTab(shellId: s1, tabId: t2, buffer: (w1, b1))],
      expected: doc({s1: ([t1, t2], t2)}, windows: {t2: w1}),
    ),
    (
      name: 'opening in an unfocused shell focuses it',
      start: doc({s1: ([t1], t1), s2: ([t2], t2)}),
      commands: [const NewTab(shellId: s2, tabId: t3)],
      expected: doc({s1: ([t1], t1), s2: ([t2, t3], t3)}, focused: s2),
    ),
    (
      name: 'unknown shell is unchanged',
      start: doc({s1: ([t1], t1)}),
      commands: [const NewTab(shellId: s2, tabId: t2)],
      expected: null,
    ),
    (
      name: 'existing tab id is unchanged',
      start: doc({s1: ([t1], t1)}),
      commands: [const NewTab(shellId: s1, tabId: t1)],
      expected: null,
    ),
    (
      name: 'existing window id is unchanged',
      start: doc({s1: ([t1], t1)}, windows: {t1: w1}),
      commands: [const NewTab(shellId: s1, tabId: t2, buffer: (w1, b1))],
      expected: null,
    ),
  ]);

  runTable('ActivateTab', [
    (
      name: 'activates a tab in its shell',
      start: doc({s1: ([t1, t2], t2)}),
      commands: [const ActivateTab(t1)],
      expected: doc({s1: ([t1, t2], t1)}),
    ),
    (
      name: 'a tab in another shell focuses that shell',
      start: doc({s1: ([t1], t1), s2: ([t2, t3], t3)}),
      commands: [const ActivateTab(t2)],
      expected: doc({s1: ([t1], t1), s2: ([t2, t3], t2)}, focused: s2),
    ),
    (
      name: 'the already active tab is unchanged',
      start: doc({s1: ([t1, t2], t1)}),
      commands: [const ActivateTab(t1)],
      expected: null,
    ),
    (
      name: 'unknown tab is unchanged',
      start: doc({s1: ([t1], t1)}),
      commands: [const ActivateTab(t3)],
      expected: null,
    ),
  ]);

  runTable('CloseTab', [
    (
      name: 'closing the active tab activates its left neighbour',
      start: doc({s1: ([t1, t2, t3], t2)}),
      commands: [const CloseTab(t2)],
      expected: doc({s1: ([t1, t3], t1)}),
    ),
    (
      name: 'closing the first active tab activates the next one',
      start: doc({s1: ([t1, t2], t1)}),
      commands: [const CloseTab(t1)],
      expected: doc({s1: ([t2], t2)}),
    ),
    (
      name: 'closing an inactive tab keeps the active one and drops windows',
      start: doc({s1: ([t1, t2], t1)}, windows: {t2: w2}),
      commands: [const CloseTab(t2)],
      expected: doc({s1: ([t1], t1)}),
    ),
    (
      name: "a shell's last tab is unchanged",
      start: doc({s1: ([t1], t1)}),
      commands: [const CloseTab(t1)],
      expected: null,
    ),
    (
      name: 'unknown tab is unchanged',
      start: doc({s1: ([t1], t1)}),
      commands: [const CloseTab(t3)],
      expected: null,
    ),
  ]);

  runTable('SplitWindow', [
    (
      name: 'shows the same buffer, copies the history and takes focus',
      start: tree(l1, w1, windows: {w1: history}),
      commands: [const SplitWindow(w1, newWindowId: w2, axis: Axis.horizontal)],
      expected: tree(h([l1, l2]), w2, windows: {w1: history, w2: history}),
    ),
    (
      name: 'with a buffer, the new window pushes it onto the copied history',
      start: tree(l1, w1, windows: {w1: history}),
      commands: [
        const SplitWindow(w1, newWindowId: w2, axis: Axis.vertical, buffer: b2)
      ],
      expected: tree(v([l1, l2]), w2, windows: {
        w1: history,
        w2: WindowState(history: BufferHistory(back: [b2, b1], current: b2)),
      }),
    ),
    (
      name: 'splitting a nested window nests a branch in its place',
      start: tree(h([l1, l2], [0.25, 0.75]), w1),
      commands: [const SplitWindow(w2, newWindowId: w3, axis: Axis.vertical)],
      expected: tree(h([l1, v([l2, l3])], [0.25, 0.75]), w3),
    ),
    (
      name: 'splitting a window in an inactive tab activates the tab',
      start: doc({s1: ([t1, t2], t2)}, windows: {t1: w1}),
      commands: [const SplitWindow(w1, newWindowId: w2, axis: Axis.horizontal)],
      expected: WindowingDoc(
        shells: {s1: ShellState(tabIds: [t1, t2], activeTabId: t1)},
        tabs: {
          t1: TabState(root: h([l1, l2]), activeWindowId: w2),
          t2: const TabState(),
        },
        windows: {w1: showing(b1), w2: showing(b1)},
        focusedShellId: s1,
      ),
    ),
    (
      name: 'unknown window is unchanged',
      start: tree(l1, w1),
      commands: [const SplitWindow(w3, newWindowId: w2, axis: Axis.horizontal)],
      expected: null,
    ),
    (
      name: 'existing new window id is unchanged',
      start: tree(h([l1, l2]), w1),
      commands: [const SplitWindow(w1, newWindowId: w2, axis: Axis.horizontal)],
      expected: null,
    ),
  ]);

  runTable('CloseWindow', [
    (
      name: 'collapses a branch left with one child, focus goes left',
      start: tree(h([l1, l2]), w2),
      commands: [const CloseWindow(w2)],
      expected: tree(l1, w1),
    ),
    (
      name: 'closing the first window focuses the next one',
      start: tree(h([l1, l2]), w1),
      commands: [const CloseWindow(w1)],
      expected: tree(l2, w2),
    ),
    (
      name: 'remaining ratios are renormalized',
      start: tree(h([l1, l2, l3], [0.5, 0.25, 0.25]), w1),
      commands: [const CloseWindow(w1)],
      expected: tree(h([l2, l3], [0.5, 0.5]), w2),
    ),
    (
      name: 'focus moves into the neighbour subtree',
      start: tree(h([v([l1, l2]), l3]), w3),
      commands: [const CloseWindow(w3)],
      expected: tree(v([l1, l2]), w1),
    ),
    (
      name: 'closing an inactive nested window keeps focus',
      start: tree(h([l1, v([l2, l3])]), w1),
      commands: [const CloseWindow(w3)],
      expected: tree(h([l1, l2]), w1),
    ),
    (
      name: "closing the tab's last window leaves the tab empty",
      start: tree(l1, w1),
      commands: [const CloseWindow(w1)],
      expected: tree(null, null),
    ),
    (
      name: 'unknown window is unchanged',
      start: tree(l1, w1),
      commands: [const CloseWindow(w2)],
      expected: null,
    ),
  ]);

  runTable('ResizeWindow', [
    (
      name: "sets the ratios of the window's branch",
      start: tree(h([l1, v([l2, l3])]), w1),
      commands: [const ResizeWindow(w3, [0.25, 0.75])],
      expected: tree(h([l1, v([l2, l3], [0.25, 0.75])]), w1),
    ),
    for (final (name, ratios) in [
      ('a zero ratio', [0.0, 1.0]),
      ('a negative ratio', [-0.5, 1.5]),
      ('the wrong count', [0.25, 0.25, 0.5]),
      ('ratios not summing to one', [0.25, 0.5]),
    ])
      (
        name: '$name is unchanged',
        start: tree(h([l1, l2]), w1),
        commands: [ResizeWindow(w1, ratios)],
        expected: null,
      ),
    (
      name: 'a root window has no branch and is unchanged',
      start: tree(l1, w1),
      commands: [const ResizeWindow(w1, [1.0])],
      expected: null,
    ),
    (
      name: 'unknown window is unchanged',
      start: tree(h([l1, l2]), w1),
      commands: [const ResizeWindow(w3, [0.5, 0.5])],
      expected: null,
    ),
  ]);

  WindowState hist(List<BufferId> back, BufferId current,
          [List<BufferId> forward = const []]) =>
      WindowState(
          history:
              BufferHistory(back: back, current: current, forward: forward));

  runTable('AttachBuffer', [
    (
      name: 'points a window at a buffer with a fresh history',
      start: tree(l1, w1, windows: {w1: history}),
      commands: [const AttachBuffer(w1, b3)],
      expected: tree(l1, w1, windows: {w1: showing(b3)}),
    ),
    (
      name: 'two windows can show the same buffer',
      start: tree(h([l1, l2]), w1, windows: {w2: showing(b2)}),
      commands: [const AttachBuffer(w2, b1)],
      expected: tree(h([l1, l2]), w1),
    ),
    (
      name: 'unknown window is unchanged',
      start: tree(l1, w1),
      commands: [const AttachBuffer(w2, b2)],
      expected: null,
    ),
  ]);

  runTable('PushBuffer', [
    (
      name: 'moves current to back, clears forward, sets the new current',
      start: tree(l1, w1, windows: {w1: hist([b3], b1, [b2])}),
      commands: [const PushBuffer(w1, b2)],
      expected: tree(l1, w1, windows: {w1: hist([b3, b1], b2)}),
    ),
    (
      name: 'unknown window is unchanged',
      start: tree(l1, w1),
      commands: [const PushBuffer(w2, b2)],
      expected: null,
    ),
  ]);

  runTable('PopBuffer', [
    (
      name: 'moves current to forward and restores the top of back',
      start: tree(l1, w1, windows: {w1: hist([b3, b2], b1, [b3])}),
      commands: [const PopBuffer(w1)],
      expected: tree(l1, w1, windows: {w1: hist([b3], b2, [b3, b1])}),
    ),
    (
      name: 'an empty back stack is unchanged',
      start: tree(l1, w1, windows: {w1: hist([], b1, [b2])}),
      commands: [const PopBuffer(w1)],
      expected: null,
    ),
    (
      name: 'unknown window is unchanged',
      start: tree(l1, w1),
      commands: [const PopBuffer(w2)],
      expected: null,
    ),
  ]);

  runTable('NavigateForward', [
    (
      name: 'moves current to back and restores the top of forward',
      start: tree(l1, w1, windows: {w1: hist([b3], b2, [b3, b1])}),
      commands: [const NavigateForward(w1)],
      expected: tree(l1, w1, windows: {w1: hist([b3, b2], b1, [b3])}),
    ),
    (
      name: 'undoes a PopBuffer',
      start: tree(l1, w1, windows: {w1: hist([b2], b1)}),
      commands: [const PopBuffer(w1), const NavigateForward(w1)],
      expected: null,
    ),
    (
      name: 'an empty forward stack is unchanged',
      start: tree(l1, w1, windows: {w1: hist([b2], b1)}),
      commands: [const NavigateForward(w1)],
      expected: null,
    ),
    (
      name: 'unknown window is unchanged',
      start: tree(l1, w1),
      commands: [const NavigateForward(w2)],
      expected: null,
    ),
  ]);

  runTable('ReplaceBuffer', [
    (
      name: 'swaps current and leaves both stacks untouched',
      start: tree(l1, w1, windows: {w1: hist([b2], b1, [b3])}),
      commands: [const ReplaceBuffer(w1, b3)],
      expected: tree(l1, w1, windows: {w1: hist([b2], b3, [b3])}),
    ),
    (
      name: 'the same buffer is unchanged',
      start: tree(l1, w1),
      commands: [const ReplaceBuffer(w1, b1)],
      expected: null,
    ),
    (
      name: 'unknown window is unchanged',
      start: tree(l1, w1),
      commands: [const ReplaceBuffer(w2, b2)],
      expected: null,
    ),
  ]);

  runTable('dispatchAll', [
    (
      name: 'applies a batch in order',
      start: doc({s1: ([t1], t1)}),
      commands: [
        const NewTab(shellId: s1, tabId: t2),
        const NewTab(shellId: s1, tabId: t3),
        const ActivateTab(t1),
      ],
      expected: doc({s1: ([t1, t2, t3], t1)}),
    ),
    (
      name: 'a batch that ends where it started is unchanged',
      start: doc({s1: ([t1], t1)}),
      commands: [const NewTab(shellId: s1, tabId: t2), const CloseTab(t2)],
      expected: null,
    ),
  ]);

  group('publishing', () {
    test('dispatchAll publishes once, and never for an unchanged doc', () {
      final controller = WindowingController(initial: doc({s1: ([t1], t1)}));
      var published = 0;
      controller.doc.addListener(() => published++);

      controller.dispatchAll(const [
        NewTab(shellId: s1, tabId: t2),
        NewTab(shellId: s1, tabId: t3),
      ]);
      expect(published, 1);

      controller.dispatch(const ActivateTab(t3));
      controller.dispatchAll(const []);
      expect(published, 1);

      controller.dispatch(const CloseTab(t3));
      expect(published, 2);
    });
  });

  group('intent methods', () {
    test('generate ids and dispatch', () {
      final controller = WindowingController(initial: doc({s1: ([t1], t1)}));

      final empty = controller.newTab();
      expect(controller.doc.value.shells[s1]!.tabIds, [t1, empty]);
      expect(controller.doc.value.tabs[empty], const TabState());

      final withBuffer = controller.newTab(buffer: b1);
      final window = controller.doc.value.tabs[withBuffer]!.activeWindowId!;
      expect(controller.doc.value.windows[window], showing(b1));

      controller.activateTab(empty);
      expect(controller.doc.value.shells[s1]!.activeTabId, empty);

      controller.closeTab(empty);
      expect(controller.doc.value.shells[s1]!.tabIds, [t1, withBuffer]);
      expectInvariants(controller.doc.value);
    });

    test('split, resize and close windows', () {
      final controller = WindowingController(initial: tree(l1, w1));
      final w = controller.splitWindow(w1, axis: Axis.horizontal);
      expect(controller.doc.value, tree(h([l1, WindowLeaf(w)]), w));
      controller.resizeWindow(w, [0.25, 0.75]);
      expect(
          controller.doc.value, tree(h([l1, WindowLeaf(w)], [0.25, 0.75]), w));
      controller.closeWindow(w);
      expect(controller.doc.value, tree(l1, w1));
      final other = controller.splitWindow(w1, axis: Axis.vertical, buffer: b2);
      expect(controller.doc.value.windows[other]!.history.current, b2);
    });

    test('navigate window history', () {
      final controller = WindowingController(initial: tree(l1, w1));
      controller.pushBuffer(w1, b2);
      controller.popBuffer(w1);
      controller.navigateForward(w1);
      controller.replaceBuffer(w1, b3);
      expect(controller.doc.value.windows[w1], hist([b1], b3));
      controller.attachBuffer(w1, b2);
      expect(controller.doc.value.windows[w1], showing(b2));
    });

    test('newTab opens in the given shell', () {
      final controller = WindowingController(
          initial: doc({s1: ([t1], t1), s2: ([t2], t2)}));
      final tab = controller.newTab(shellId: s2);
      expect(controller.doc.value.shells[s2]!.tabIds, [t2, tab]);
      expect(controller.doc.value.focusedShellId, s2);
    });
  });
}
