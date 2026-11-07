import 'package:flutter_test/flutter_test.dart';
import 'package:reef/reef.dart';

/// Fails when [doc] breaks a windowing invariant (spec §2): the focus chain,
/// each tab in exactly one shell, and window membership.
void expectInvariants(WindowingDoc doc) {
  expect(doc.shells, isNotEmpty, reason: 'the last shell never closes');
  final shell = doc.shells[doc.focusedShellId];
  expect(shell, isNotNull, reason: 'focused shell exists');

  final owners = <TabId, int>{};
  for (final s in doc.shells.values) {
    expect(s.tabIds, isNotEmpty, reason: 'a shell always has a tab');
    expect(s.tabIds, contains(s.activeTabId), reason: 'active tab is owned');
    for (final t in s.tabIds) {
      owners[t] = (owners[t] ?? 0) + 1;
    }
  }
  expect(owners.keys.toSet(), doc.tabs.keys.toSet(),
      reason: 'every tab belongs to a shell');
  expect(owners.values.every((n) => n == 1), isTrue,
      reason: 'no tab belongs to two shells');

  final members = <WindowId>[];
  for (final tab in doc.tabs.values) {
    final ids = tab.root?.windowIds.toList() ?? const <WindowId>[];
    if (tab.root case final root?) _expectTree(root);
    if (ids.isEmpty) {
      expect(tab.activeWindowId, isNull, reason: 'an empty tab has no focus');
    } else {
      expect(ids, contains(tab.activeWindowId),
          reason: 'active window is in the tab');
    }
    members.addAll(ids);
  }
  expect(members.toSet().length, members.length,
      reason: 'a window belongs to one tab');
  expect(members.toSet().intersection(doc.floating.keys.toSet()), isEmpty,
      reason: 'a window is in a tree or floating, not both');
  expect({...members, ...doc.floating.keys}, doc.windows.keys.toSet(),
      reason: 'every window is a tree or floating window and vice versa');
  for (final MapEntry(key: w, value: f) in doc.floating.entries) {
    expect(
        switch (f.scope) {
          ShellScope(:final id) => doc.shells.containsKey(id),
          TabScope(:final id) => doc.tabs.containsKey(id),
          WindowScope(:final id) => doc.windows.containsKey(id) && id != w,
        },
        isTrue,
        reason: "a floating window's scope exists");
  }
}

/// One table row: a start doc, the commands dispatched as one batch, and the
/// expected doc, or `null` when the start doc must come back unchanged.
typedef Row = ({
  String name,
  WindowingDoc start,
  List<WindowingCommand> commands,
  WindowingDoc? expected,
});

/// Runs every row through a [WindowingController] and checks the result and
/// the invariants.
void runTable(String name, List<Row> rows) {
  group(name, () {
    for (final row in rows) {
      test(row.name, () {
        expectInvariants(row.start);
        final controller = WindowingController(initial: row.start);
        controller.dispatchAll(row.commands);
        final result = controller.doc.value;
        if (row.expected case final expected?) {
          expect(result, expected);
        } else {
          expect(identical(result, row.start), isTrue,
              reason: 'invalid commands return the same doc instance');
        }
        expectInvariants(result);
      });
    }
  });
}

/// A branch has at least two children and one positive ratio per child,
/// summing to one.
void _expectTree(WindowNode node) {
  if (node is! WindowBranch) return;
  expect(node.children.length, greaterThanOrEqualTo(2),
      reason: 'a branch with one child collapses');
  expect(node.ratios.length, node.children.length,
      reason: 'one ratio per child');
  expect(node.ratios.every((r) => r > 0), isTrue, reason: 'ratios positive');
  expect(node.ratios.fold<double>(0, (a, b) => a + b), closeTo(1, 1e-9),
      reason: 'ratios sum to one');
  node.children.forEach(_expectTree);
}
