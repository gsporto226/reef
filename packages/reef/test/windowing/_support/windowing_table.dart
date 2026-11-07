import 'package:flutter_test/flutter_test.dart';
import 'package:reef/reef.dart';

/// Fails when [doc] breaks a windowing invariant (spec §2): the focus chain,
/// each tab in exactly one shell, and window membership.
void expectInvariants(WindowingDoc doc) {
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
    expect(tab.activeWindowId, tab.root,
        reason: 'active window is in the tab (single-window tree)');
    if (tab.root case final root?) members.add(root);
  }
  expect(members.toSet().length, members.length,
      reason: 'a window belongs to one tab');
  expect(members.toSet(), doc.windows.keys.toSet(),
      reason: 'every window is a member of a tab and vice versa');
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
