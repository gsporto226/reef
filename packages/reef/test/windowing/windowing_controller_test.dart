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
const b1 = BufferId.manual('b1');

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
            t: TabState(root: windows[t], activeWindowId: windows[t]),
      },
      windows: {for (final w in windows.values) w: showing(b1)},
      focusedShellId: focused,
    );

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
    expect(const TabState(root: w1, activeWindowId: w1).hashCode,
        const TabState(root: w1, activeWindowId: w1).hashCode);
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
      final window = controller.doc.value.tabs[withBuffer]!.root!;
      expect(controller.doc.value.windows[window], showing(b1));

      controller.activateTab(empty);
      expect(controller.doc.value.shells[s1]!.activeTabId, empty);

      controller.closeTab(empty);
      expect(controller.doc.value.shells[s1]!.tabIds, [t1, withBuffer]);
      expectInvariants(controller.doc.value);
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
