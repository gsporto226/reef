import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reef/reef.dart';

const s1 = ShellId.manual('s1');
const t1 = TabId.manual('t1');
const t2 = TabId.manual('t2');
const w1 = WindowId.manual('w1');
const w2 = WindowId.manual('w2');
const w3 = WindowId.manual('w3');
const w4 = WindowId.manual('w4');
const b1 = BufferId.manual('b1');
const b2 = BufferId.manual('b2');
const b3 = BufferId.manual('b3');

/// Shell s1: tab t1 split into w1 (b0 then b1), w2 (b2) and w3 (b3), w2
/// active; tab t2 holds only w4 (b3). t1 is active.
final doc = WindowingDoc(
  shells: {s1: ShellState(tabIds: [t1, t2], activeTabId: t1)},
  tabs: {
    t1: TabState(
      root: WindowBranch(
        axis: Axis.horizontal,
        children: [WindowLeaf(w1), WindowLeaf(w2), WindowLeaf(w3)],
        ratios: [0.25, 0.5, 0.25],
      ),
      activeWindowId: w2,
    ),
    t2: TabState(root: WindowLeaf(w4), activeWindowId: w4),
  },
  windows: {
    w1: WindowState(
        history: BufferHistory(back: [BufferId.manual('b0')], current: b1)),
    w2: WindowState(history: BufferHistory(current: b2)),
    w3: WindowState(history: BufferHistory(current: b3)),
    w4: WindowState(history: BufferHistory(current: b3)),
  },
  focusedShellId: s1,
);

void main() {
  late UndoController undo;
  late List<WindowingCommand> seen;
  late int publishes;

  WindowingController controller(
      [WindowingFocusPolicy policy = const WindowingFocusPolicy()]) {
    final c = WindowingController(
      initial: doc,
      undo: undo,
      focusPolicy: policy,
      interceptor: (_, command) {
        seen.add(command);
        return const CommandDecision.approve();
      },
    );
    c.doc.addListener(() => publishes++);
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    undo = UndoController();
    seen = [];
    publishes = 0;
  });

  WindowingDoc d(WindowingController c) => c.doc.value;
  TabId activeTab(WindowingController c) =>
      d(c).shells[s1]!.activeTabId;
  WindowId? active(WindowingController c) =>
      d(c).tabs[activeTab(c)]!.activeWindowId;

  group('split', () {
    test('takes focus by default', () {
      final c = controller();
      final created = c.splitWindow(w2, axis: Axis.vertical);
      expect(active(c), created);
    });

    test('can leave focus on the original window, in one batch and one '
        'undo step the interceptor sees whole', () {
      final c = controller(const WindowingFocusPolicy(splitTakesFocus: false));
      c.splitWindow(w2, axis: Axis.vertical);
      expect(d(c).windows.length, 5);
      expect(active(c), w2);
      expect(publishes, 1);
      expect(undo.labels.length, 1);
      expect(seen, [isA<SplitWindow>(), isA<ActivateWindow>()]);
      undo.undo();
      expect(d(c), doc);
    });
  });

  group('closing the last tree window of a tab', () {
    test('leaves the tab empty by default', () {
      final c = controller()..activateTab(t2)..closeWindow(w4);
      expect(d(c).shells[s1]!.tabIds, [t1, t2]);
      expect(d(c).tabs[t2]!.root, isNull);
    });

    test('can close the tab, in one batch and one undo step', () {
      final c = controller(const WindowingFocusPolicy(closeEmptyTab: true))
        ..closeWindow(w4);
      expect(d(c).shells[s1]!.tabIds, [t1]);
      expect(d(c).windows.containsKey(w4), isFalse);
      expect(publishes, 1);
      expect(undo.labels.length, 1);
      expect(seen, [isA<CloseWindow>(), isA<CloseTab>()]);
    });

    test('closing a window that leaves others keeps the tab', () {
      final c = controller(const WindowingFocusPolicy(closeEmptyTab: true))
        ..closeWindow(w2);
      expect(d(c).shells[s1]!.tabIds, [t1, t2]);
      expect(seen, [isA<CloseWindow>()]);
    });
  });

  group('focus after a close', () {
    test("goes to the reducer's neighbour by default", () {
      final c = controller()..closeWindow(w2);
      expect(active(c), w1);
    });

    test('goes where the policy picks, against the doc before the close', () {
      WindowingDoc? before;
      final c = controller(WindowingFocusPolicy(focusAfterClose: (d, closed) {
        before = d;
        expect(closed, w2);
        return w3;
      }))
        ..closeWindow(w2);
      expect(before, doc);
      expect(active(c), w3);
      expect(publishes, 1);
      expect(seen, [isA<CloseWindow>(), isA<ActivateWindow>()]);
    });

    test('a null pick keeps the neighbour, and closing an inactive window '
        'asks nothing', () {
      var asked = 0;
      final c = controller(WindowingFocusPolicy(focusAfterClose: (_, _) {
        asked++;
        return null;
      }))
        ..closeWindow(w2);
      expect(active(c), w1);
      expect(asked, 1);
      c.closeWindow(w3);
      expect(asked, 1);
    });
  });

  group('back', () {
    test('pops the active window and reports it handled', () {
      final c = controller()..activateWindow(w1);
      expect(c.back(), isTrue);
      expect(d(c).windows[w1]!.history.current, BufferId.manual('b0'));
      expect(d(c).windows[w1]!.history.forward, [b1]);
    });

    test('on an empty back stack does nothing by default, handled', () {
      final c = controller();
      expect(c.back(), isTrue);
      expect(d(c), doc);
    });

    test('on an empty back stack can close the window', () {
      final c = controller(
          const WindowingFocusPolicy(emptyBack: EmptyBackAction.closeWindow));
      expect(c.back(), isTrue);
      expect(d(c).windows.containsKey(w2), isFalse);
    });

    test('closing on back runs the close policy in the same batch', () {
      final c = controller(const WindowingFocusPolicy(
          emptyBack: EmptyBackAction.closeWindow, closeEmptyTab: true))
        ..activateTab(t2);
      expect(c.back(), isTrue);
      expect(d(c).shells[s1]!.tabIds, [t1]);
    });

    test('on an empty back stack can report unhandled', () {
      final c = controller(
          const WindowingFocusPolicy(emptyBack: EmptyBackAction.unhandled));
      expect(c.back(), isFalse);
      expect(d(c), doc);
    });

    test('in an empty tab follows the empty back stack setting', () {
      final c = controller(
          const WindowingFocusPolicy(emptyBack: EmptyBackAction.unhandled))
        ..activateTab(t2)
        ..closeWindow(w4);
      expect(c.back(), isFalse);
      c.focusPolicy = const WindowingFocusPolicy();
      expect(c.back(), isTrue);
    });
  });
}
