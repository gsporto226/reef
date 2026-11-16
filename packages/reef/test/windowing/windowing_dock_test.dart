import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reef/reef.dart';

const s1 = ShellId.manual('s1');
const s2 = ShellId.manual('s2');
const t1 = TabId.manual('t1');
const t2 = TabId.manual('t2');
const t3 = TabId.manual('t3');
const w1 = WindowId.manual('w1');
const w2 = WindowId.manual('w2');
const w3 = WindowId.manual('w3');
const w4 = WindowId.manual('w4');
const w5 = WindowId.manual('w5');

WindowState shows(String buffer, {Map<String, String> arguments = const {}}) =>
    WindowState(
      history: BufferHistory(
        current: HistoryEntry(BufferId.manual(buffer), arguments: arguments),
      ),
    );

/// s1 holds t1 (w1 | w2) and empty t2; s2 holds t3 (w3). w4 floats over t1,
/// w5 over w1. w1 and w3 show the same page.
WindowingDoc fixture() => WindowingDoc(
  shells: {
    s1: ShellState(tabIds: [t1, t2], activeTabId: t1),
    s2: ShellState(tabIds: [t3], activeTabId: t3),
  },
  tabs: {
    t1: TabState(
      root: WindowBranch(
        axis: Axis.horizontal,
        children: const [WindowLeaf(w1), WindowLeaf(w2)],
        ratios: const [0.5, 0.5],
      ),
      activeWindowId: w1,
    ),
    t2: const TabState(),
    t3: const TabState(root: WindowLeaf(w3), activeWindowId: w3),
  },
  windows: {
    w1: shows('A', arguments: {'q': '1'}),
    w2: shows('B'),
    w3: shows('A', arguments: {'q': '1'}),
    w4: shows('C'),
    w5: shows('D'),
  },
  floating: const {
    w4: FloatingState(scope: TabScope(t1), zIndex: 0),
    w5: FloatingState(scope: WindowScope(w1), zIndex: 0),
  },
  focusedShellId: s1,
);

WindowingDoc dock(Dockable d, DockTarget t) {
  final doc = fixture();
  final next = doc.applyAll(dockCommands(doc, d, t));
  expect(next.isValid, isTrue);
  return next;
}

void expectEmpty(Dockable d, DockTarget t) =>
    expect(dockCommands(fixture(), d, t), isEmpty);

void main() {
  test("DockArea.tab picks the slot on the pointer's side of the tab", () {
    final pick = DockArea.tab(s1, 2);
    const size = Size(100, 30);
    expect(pick(const Offset(10, 5), size), const TabStripTarget(s1, 2));
    expect(pick(const Offset(60, 5), size), const TabStripTarget(s1, 3));
  });

  group('dockCommands, a tab', () {
    test('reorders within its strip', () {
      expect(
        dock(
          const TabDockable(t1),
          const TabStripTarget(s1, 2),
        ).shells[s1]!.tabIds,
        [t2, t1],
      );
      expect(
        dock(
          const TabDockable(t2),
          const TabStripTarget(s1, 0),
        ).shells[s1]!.tabIds,
        [t2, t1],
      );
    });

    test('dropped on either side of itself is a no-op', () {
      expectEmpty(const TabDockable(t1), const TabStripTarget(s1, 0));
      expectEmpty(const TabDockable(t1), const TabStripTarget(s1, 1));
    });

    test("moves into another shell's strip at the slot, focusing it", () {
      final doc = dock(const TabDockable(t1), const TabStripTarget(s2, 0));
      expect(doc.shells[s2]!.tabIds, [t1, t3]);
      expect(doc.shells[s1]!.tabIds, [t2]);
      expect(doc.focusedShellId, s2);
      expect(doc.windows.keys, containsAll([w1, w2, w4, w5]));
    });

    test("a shell's last tab moves out and its shell closes", () {
      final doc = dock(const TabDockable(t3), const TabStripTarget(s1, 1));
      expect(doc.shells.keys, [s1]);
      expect(doc.shells[s1]!.tabIds, [t1, t3, t2]);
      expect(doc.tabs[t3]!.root, const WindowLeaf(w3));
    });

    test('docks only onto tab strips', () {
      expectEmpty(const TabDockable(t1), const WindowCentreTarget(w3));
      expectEmpty(
        const TabDockable(t1),
        const WindowEdgeTarget(w3, AxisDirection.left),
      );
      expectEmpty(const TabDockable(t1), const EmptyTabTarget(t2));
      expectEmpty(const TabDockable(t1), const FloatTarget(ShellScope(s2)));
    });

    test('unknown tab or shell is a no-op', () {
      expectEmpty(
        const TabDockable(TabId.manual('x')),
        const TabStripTarget(s1, 0),
      );
      expectEmpty(
        const TabDockable(t1),
        const TabStripTarget(ShellId.manual('x'), 0),
      );
    });
  });

  group('dockCommands, a window', () {
    test('on an edge splits the target on that side, across shells', () {
      final doc = dock(
        const WindowDockable(w2),
        const WindowEdgeTarget(w3, AxisDirection.left),
      );
      final root = doc.tabs[t3]!.root! as WindowBranch;
      expect(root.axis, Axis.horizontal);
      expect(root.windowIds, [w2, w3]);
      expect(doc.tabs[t1]!.root, const WindowLeaf(w1));
      expect(doc.activeWindowId, w2);
    });

    test('top and bottom edges split vertically', () {
      final up = dock(
        const WindowDockable(w2),
        const WindowEdgeTarget(w3, AxisDirection.up),
      );
      expect((up.tabs[t3]!.root! as WindowBranch).axis, Axis.vertical);
      expect(up.tabs[t3]!.root!.windowIds, [w2, w3]);
      final down = dock(
        const WindowDockable(w2),
        const WindowEdgeTarget(w3, AxisDirection.down),
      );
      expect(down.tabs[t3]!.root!.windowIds, [w3, w2]);
    });

    test('within its own tab, moves to the other side', () {
      final doc = dock(
        const WindowDockable(w2),
        const WindowEdgeTarget(w1, AxisDirection.left),
      );
      expect(doc.tabs[t1]!.root!.windowIds, [w2, w1]);
    });

    test('a floating window docks into the tree', () {
      final doc = dock(
        const WindowDockable(w4),
        const WindowEdgeTarget(w3, AxisDirection.right),
      );
      expect(doc.tabs[t3]!.root!.windowIds, [w3, w4]);
      expect(doc.floating.containsKey(w4), isFalse);
    });

    test('on its own edge or centre is a no-op', () {
      expectEmpty(
        const WindowDockable(w1),
        const WindowEdgeTarget(w1, AxisDirection.left),
      );
      expectEmpty(const WindowDockable(w1), const WindowCentreTarget(w1));
    });

    test('on the edge of a floating window is a no-op', () {
      expectEmpty(
        const WindowDockable(w2),
        const WindowEdgeTarget(w4, AxisDirection.left),
      );
    });

    test('on a centre pushes its entry onto the target and closes', () {
      final doc = dock(const WindowDockable(w2), const WindowCentreTarget(w3));
      final history = doc.windows[w3]!.history;
      expect(history.current.buffer, const BufferId.manual('B'));
      expect(history.back.single.buffer, const BufferId.manual('A'));
      expect(doc.windows.containsKey(w2), isFalse);
      expect(doc.activeWindowId, w3);
      expect(doc.focusedShellId, s2);
    });

    test('the pushed entry keeps its arguments', () {
      final doc = dock(const WindowDockable(w1), const WindowCentreTarget(w2));
      expect(doc.windows[w2]!.history.current.arguments, {'q': '1'});
      expect(
        doc.windows.containsKey(w5),
        isFalse,
        reason: 'what floats over the closed window closes with it',
      );
    });

    test('on a target already showing that page only closes', () {
      final doc = dock(const WindowDockable(w3), const WindowCentreTarget(w1));
      expect(doc.windows[w1], fixture().windows[w1]);
      expect(doc.windows.containsKey(w3), isFalse);
      expect(doc.tabs[t3]!.root, isNull);
    });

    test('the same buffer with other arguments is another page: it pushes', () {
      final base = fixture();
      final doc = base.copyWith(windows: {...base.windows, w2: shows('A')});
      final next = doc.applyAll(
        dockCommands(
          doc,
          const WindowDockable(w2),
          const WindowCentreTarget(w1),
        ),
      );
      expect(next.windows[w1]!.history.back, hasLength(1));
      expect(next.windows[w1]!.history.current.arguments, isEmpty);
    });

    test('onto a window floating over it is a no-op', () {
      expectEmpty(const WindowDockable(w1), const WindowCentreTarget(w5));
    });

    test('on an empty tab becomes its root', () {
      final doc = dock(const WindowDockable(w2), const EmptyTabTarget(t2));
      expect(doc.tabs[t2]!.root, const WindowLeaf(w2));
      expectEmpty(const WindowDockable(w2), const EmptyTabTarget(t3));
    });

    test('a floating one on an empty tab docks there', () {
      final doc = dock(const WindowDockable(w4), const EmptyTabTarget(t2));
      expect(doc.tabs[t2]!.root, const WindowLeaf(w4));
      expect(doc.floating.containsKey(w4), isFalse);
    });

    test('on a float layer floats; a floating one does not', () {
      final doc = dock(
        const WindowDockable(w2),
        const FloatTarget(ShellScope(s2)),
      );
      expect(doc.floating[w2]!.scope, const ShellScope(s2));
      expect(doc.tabs[t1]!.root, const WindowLeaf(w1));
      expectEmpty(const WindowDockable(w4), const FloatTarget(ShellScope(s2)));
    });

    test('on a tab strip becomes a new tab at that slot', () {
      final doc = dock(const WindowDockable(w2), const TabStripTarget(s2, 0));
      final tabs = doc.shells[s2]!.tabIds;
      expect(tabs, hasLength(2));
      expect(tabs.last, t3);
      expect(doc.tabs[tabs.first]!.root, const WindowLeaf(w2));
      expect(doc.shells[s2]!.activeTabId, tabs.first);
    });

    test('unknown window is a no-op', () {
      expectEmpty(
        const WindowDockable(WindowId.manual('x')),
        const WindowCentreTarget(w1),
      );
    });
  });

  group('wouldApply', () {
    const reason = UndoLabel('No');

    test('asks the interceptor without dispatching', () {
      final seen = <WindowingCommand>[];
      final c = WindowingController(
        initial: fixture,
        interceptor: (doc, command) {
          seen.add(command);
          return command is MoveTab
              ? const CommandDecision.veto(reason)
              : const CommandDecision.approve();
        },
      );
      addTearDown(c.dispose);
      final vetoes = <CommandVeto?>[];
      c.vetoes.addListener(() => vetoes.add(c.vetoes.value));
      final before = c.doc.value;

      expect(
        c.wouldApply(
          dockCommands(
            before,
            const TabDockable(t1),
            const TabStripTarget(s2, 0),
          ),
        ),
        isFalse,
      );
      expect(
        c.wouldApply(
          dockCommands(
            before,
            const WindowDockable(w2),
            const WindowCentreTarget(w3),
          ),
        ),
        isTrue,
      );
      expect(seen, isNotEmpty);
      expect(c.doc.value, same(before));
      expect(vetoes, isEmpty);
    });

    test('a batch that changes nothing would not apply', () {
      final c = WindowingController(initial: fixture);
      addTearDown(c.dispose);
      expect(c.wouldApply(const []), isFalse);
      expect(c.wouldApply(const [ActivateTab(t1)]), isFalse);
    });
  });

  group('popOutWindow', () {
    test('moves a tree window into a new shell as its only tab', () async {
      final platform = FakeShellPlatform();
      final c = WindowingController(initial: fixture, platform: platform);
      addTearDown(c.dispose);
      final shell = (await c.popOutWindow(w2)).getOrNull()!;
      final doc = c.doc.value;
      expect(platform.opened, [shell]);
      expect(
        doc.tabs[doc.shells[shell]!.tabIds.single]!.root,
        const WindowLeaf(w2),
      );
      expect(doc.focusedShellId, shell);
    });

    test('docks a floating window into it', () async {
      final c = WindowingController(
        initial: fixture,
        platform: FakeShellPlatform(),
      );
      addTearDown(c.dispose);
      final shell = (await c.popOutWindow(w4)).getOrNull()!;
      final doc = c.doc.value;
      expect(doc.floating.containsKey(w4), isFalse);
      expect(
        doc.tabs[doc.shells[shell]!.tabIds.single]!.root,
        const WindowLeaf(w4),
      );
    });
  });

  group('a drag session', () {
    late FakeShellPlatform platform;
    late UndoController undo;
    late WindowingController c;

    /// Both shells side by side in the one test view, each under its own
    /// tab strip; tabs are labelled by id and windows show their buffer.
    Future<void> pump(
      WidgetTester tester, {
      WindowingInterceptor? interceptor,
    }) async {
      platform = FakeShellPlatform();
      undo = UndoController();
      c = WindowingController(
        initial: fixture,
        platform: platform,
        undo: undo,
        interceptor: interceptor,
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: WindowingRoot(
            controller: c,
            bufferBuilder: (_, buffer) => Text(buffer.value),
            delegate: WindowingDelegate(
              labels: WindowingLabels(tab: (id) => UndoLabel(id.value)),
              // A grip per window, its drag handle.
              windowChrome: (_, id, _, page) => Column(
                children: [
                  DockSource(
                    dockable: WindowDockable(id),
                    child: Text('grip ${id.value}'),
                  ),
                  Expanded(child: page),
                ],
              ),
            ),
            child: const Row(
              children: [
                Expanded(child: DesktopProjection(s1)),
                Expanded(child: DesktopProjection(s2)),
              ],
            ),
          ),
        ),
      );
    }

    Future<TestGesture> drag(
      WidgetTester tester,
      Finder from,
      Offset to,
    ) async {
      final gesture = await tester.startGesture(tester.getCenter(from));
      await gesture.moveBy(const Offset(20, 0));
      await gesture.moveTo(to);
      await tester.pump();
      return gesture;
    }

    Iterable<Color> tints(WidgetTester tester) => tester
        .widgetList<ColoredBox>(find.byType(ColoredBox))
        .map((b) => b.color)
        .where((c) => c.a < 1); // the splitter's line is opaque

    testWidgets('drops a tab on another shell\'s strip as one undo step', (
      tester,
    ) async {
      await pump(tester);
      final gesture = await drag(
        tester,
        find.text('t1'),
        tester.getRect(find.text('t3')).centerRight - const Offset(1, 0),
      );
      expect(tints(tester), contains(const Color(0x442196F3)));
      await gesture.up();
      await tester.pump();

      expect(c.doc.value.shells[s2]!.tabIds, [t3, t1]);
      expect(tints(tester), isEmpty);
      undo.undo();
      expect(c.doc.value, fixture());
    });

    testWidgets('a vetoed drop shows red while hovering and changes nothing', (
      tester,
    ) async {
      await pump(
        tester,
        interceptor: (_, command) => command is MoveTab
            ? const CommandDecision.veto(UndoLabel('No'))
            : const CommandDecision.approve(),
      );
      final gesture = await drag(
        tester,
        find.text('t1'),
        tester.getCenter(find.text('t3')),
      );
      expect(tints(tester), [const Color(0x44F44336)]);
      await gesture.up();
      await tester.pump();
      expect(c.doc.value, fixture());
    });

    testWidgets('a tap on a tab still activates it', (tester) async {
      await pump(tester);
      await tester.tap(find.text('t2'));
      expect(c.doc.value.shells[s1]!.activeTabId, t2);
    });

    testWidgets('drops a window on the edge of a window in another shell', (
      tester,
    ) async {
      await pump(tester);
      final target = tester.getRect(find.text('A').last);
      final gesture = await drag(
        tester,
        find.text('grip w2'),
        target.centerLeft + const Offset(5, 0),
      );
      await gesture.up();
      await tester.pump();
      expect(c.doc.value.tabs[t3]!.root!.windowIds, [w2, w3]);
    });

    testWidgets('drops a window on a centre: the target pushes its page', (
      tester,
    ) async {
      await pump(tester);
      final gesture = await drag(
        tester,
        find.text('grip w2'),
        tester.getCenter(find.text('A').last) + const Offset(0, 100),
      );
      await gesture.up();
      await tester.pump();
      expect(
        c.doc.value.windows[w3]!.history.current.buffer,
        const BufferId.manual('B'),
      );
      expect(c.doc.value.windows.containsKey(w2), isFalse);
    });

    testWidgets('a drop outside the view pops the tab out', (tester) async {
      await pump(tester);
      final gesture = await drag(
        tester,
        find.text('t1'),
        const Offset(-40, -40),
      );
      await gesture.up();
      await tester.pump();
      expect(platform.opened, hasLength(1));
      expect(c.doc.value.shells[platform.opened.single]!.tabIds, [t1]);
    });

    testWidgets('without pop-out, a drop outside the view is cancelled', (
      tester,
    ) async {
      await pump(tester);
      platform.isSupported = false;
      final gesture = await drag(
        tester,
        find.text('t1'),
        const Offset(-40, -40),
      );
      await gesture.up();
      await tester.pump();
      expect(c.doc.value, fixture());
    });
  });
}
