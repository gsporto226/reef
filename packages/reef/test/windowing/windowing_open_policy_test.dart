import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reef/reef.dart';

const s1 = ShellId.manual('s1');
const t1 = TabId.manual('t1');
const w1 = WindowId.manual('w1');
const w2 = WindowId.manual('w2');
const b1 = BufferId.manual('b1');
const b2 = BufferId.manual('b2');
const b3 = BufferId.manual('b3');

WindowState showing(BufferId buffer) =>
    WindowState(history: BufferHistory(current: buffer));

/// Shell s1 with tab t1 split into w1 (b1) and w2 (b2), w1 active.
final split = WindowingDoc(
  shells: {s1: ShellState(tabIds: [t1], activeTabId: t1)},
  tabs: {
    t1: TabState(
      root: WindowBranch(
        axis: Axis.horizontal,
        children: [WindowLeaf(w1), WindowLeaf(w2)],
        ratios: [0.5, 0.5],
      ),
      activeWindowId: w1,
    ),
  },
  windows: {w1: showing(b1), w2: showing(b2)},
  focusedShellId: s1,
);

/// Shell s1 with an empty active tab t1.
final empty = WindowingDoc(
  shells: {s1: ShellState(tabIds: [t1], activeTabId: t1)},
  tabs: {t1: TabState()},
  windows: const {},
  focusedShellId: s1,
);

void main() {
  late UndoController undo;
  late List<WindowingCommand> seen;

  WindowingController controller(WindowingDoc initial,
      [WindowingOpenPolicy? policy]) {
    final c = WindowingController(
      initial: initial,
      undo: undo,
      interceptor: (_, command) {
        seen.add(command);
        return const CommandDecision.approve();
      },
    );
    if (policy != null) c.openPolicy = policy;
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    undo = UndoController();
    seen = [];
  });

  WindowingDoc d(WindowingController c) => c.doc.value;
  WindowId active(WindowingController c) =>
      d(c).tabs[d(c).shells[s1]!.activeTabId]!.activeWindowId!;

  group('default policy', () {
    test('a window of the active tab showing the buffer gets focus', () {
      final c = controller(split)..openBuffer(b2);
      expect(active(c), w2);
      expect(d(c).windows.length, 2);
      expect(seen, [isA<ActivateWindow>()]);
    });

    test('otherwise the buffer is pushed onto the active window', () {
      final c = controller(split)..openBuffer(b3);
      expect(d(c).windows[w1]!.history.current, b3);
      expect(d(c).windows[w1]!.history.back, [b1]);
    });

    test('an empty tab gets its first window, in one batch and one undo '
        'step, and the interceptor sees every command', () {
      var publishes = 0;
      final c = controller(empty);
      c.doc.addListener(() => publishes++);
      c.openBuffer(b1);
      expect(d(c).shells[s1]!.tabIds, [t1]);
      expect(d(c).windows[active(c)]!.history.current, b1);
      expect(publishes, 1);
      expect(undo.labels.length, 1);
      expect(seen.length, greaterThan(1));
      undo.undo();
      expect(d(c), empty);
    });
  });

  group('shipped policies', () {
    test('push pushes even when a window already shows the buffer', () {
      final c = controller(split, pushOpenPolicy)..openBuffer(b2);
      expect(d(c).windows[w1]!.history.current, b2);
    });

    test('push gives an empty tab its first window', () {
      final c = controller(empty, pushOpenPolicy)..openBuffer(b1);
      expect(d(c).windows[active(c)]!.history.current, b1);
    });

    test('split beside opens a new window next to the active one', () {
      final c = controller(split, splitBesideOpenPolicy)..openBuffer(b3);
      expect(d(c).windows.length, 3);
      expect(d(c).windows[active(c)]!.history.current, b3);
      expect(d(c).windows[w1]!.history.current, b1);
    });

    test('split beside gives an empty tab its first window', () {
      final c = controller(empty, splitBesideOpenPolicy)..openBuffer(b1);
      expect(d(c).windows[active(c)]!.history.current, b1);
    });

    test('new tab opens a tab in the focused shell showing the buffer', () {
      final c = controller(split, newTabOpenPolicy)..openBuffer(b3);
      expect(d(c).shells[s1]!.tabIds.length, 2);
      expect(d(c).windows[active(c)]!.history.current, b3);
    });
  });

  test('a policy is a plain function of doc and buffer', () {
    final c = controller(
        split, (doc, buffer) => [ReplaceBuffer(w2, buffer)])
      ..openBuffer(b3);
    expect(d(c).windows[w2]!.history.current, b3);
    expect(seen, [isA<ReplaceBuffer>()]);
  });
}
