import 'package:flutter/painting.dart' show Axis, AxisDirection;
import 'package:flutter_test/flutter_test.dart';
import 'package:reef/reef.dart';

// Fixes for the friction the mail client and vim editor hit (W6).
void main() {
  const a = BufferId.manual('a'), b = BufferId.manual('b');
  const c = BufferId.manual('c');

  // Three windows: w1 left of a column of w2 over w3.
  final (w1, w2, w3) =
      (WindowId.manual('w1'), WindowId.manual('w2'), WindowId.manual('w3'));
  final start = WindowingDoc.initial();
  final doc = start.applyAll([
    NewTab(shellId: start.focusedShellId, tabId: TabId.manual('t'),
        buffer: (w1, a)),
    SplitWindow(w1, newWindowId: w2, axis: Axis.horizontal, buffer: b),
    SplitWindow(w2, newWindowId: w3, axis: Axis.vertical, buffer: c),
  ]);

  test('applyAll builds a layout; the queries read it', () {
    expect(doc.activeWindowId, w3);
    expect(doc.activeTab.root!.windowIds, [w1, w2, w3]);
    expect(doc.windowsShowing(b), [w2]);
    expect(doc.tabOf(w2), TabId.manual('t'));
    expect(doc.neighbour(w2, AxisDirection.left), w1);
    expect(doc.neighbour(w2, AxisDirection.down), w3);
    expect(doc.neighbour(w3, AxisDirection.up), w2);
    expect(doc.neighbour(w1, AxisDirection.right), isNotNull);
    expect(doc.neighbour(w1, AxisDirection.left), isNull);
  });

  test('initial runs only when nothing was restored', () {
    final store = InMemoryHibernationStore();
    var runs = 0;
    WindowingDoc? build() => (runs++, doc).$2;
    // The store saves on the first published change.
    WindowingController(store: store, initial: build).activateWindow(w1);
    WindowingController(store: store, initial: build);
    expect(runs, 1);
  });

  test('BufferId.of has a kind and a token', () {
    const id = BufferId.of('thread', '42/x');
    expect((id.id, id.kind, id.token), ('thread:42/x', 'thread', '42/x'));
    expect((a.kind, a.token), (null, null));
  });

  test('emptyBack can focus another window', () {
    final controller = WindowingController(
      initial: () => doc.applyAll([ActivateWindow(w1)]),
      focusPolicy: WindowingFocusPolicy(
          emptyBack: (doc) => [ActivateWindow(doc.windowsShowing(c).first)]),
    );
    expect(controller.back(), isTrue);
    expect(controller.doc.value.activeWindowId, w3);
  });
}
