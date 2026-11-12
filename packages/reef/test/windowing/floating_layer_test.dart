import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reef/reef.dart';

const _shell = ShellId.manual('s');
const _t1 = TabId.manual('t1');
const _t2 = TabId.manual('t2');
const _a = WindowId.manual('a');
const _c = WindowId.manual('c');
const _b = WindowId.manual('b');
const _f1 = WindowId.manual('f1');
const _f2 = WindowId.manual('f2');
const _f3 = WindowId.manual('f3');
const _f4 = WindowId.manual('f4');

WindowState _shows(String buffer) =>
    WindowState(history: BufferHistory(current: BufferId.manual(buffer)));

/// Tab 1 is `a` | `c`, tab 2 is `b`. Floating: `f1` over the shell (hinted
/// to the bottom right), `f2` and `f4` over tab 1, `f3` over window `a`.
WindowingDoc _doc() => WindowingDoc(
  shells: {
    _shell: ShellState(tabIds: [_t1, _t2], activeTabId: _t1),
  },
  tabs: {
    _t1: TabState(
      activeWindowId: _a,
      root: WindowBranch(
        axis: Axis.horizontal,
        ratios: [0.5, 0.5],
        children: const [WindowLeaf(_a), WindowLeaf(_c)],
      ),
    ),
    _t2: const TabState(root: WindowLeaf(_b), activeWindowId: _b),
  },
  windows: {
    for (final w in [_a, _b, _c, _f1, _f2, _f3, _f4]) w: _shows(w.value),
  },
  floating: {
    _f1: const FloatingState(
      scope: ShellScope(_shell),
      zIndex: 0,
      geometry: Rect.fromLTWH(500, 400, 200, 100),
    ),
    _f2: const FloatingState(scope: TabScope(_t1), zIndex: 0),
    _f4: const FloatingState(scope: TabScope(_t1), zIndex: 1),
    _f3: const FloatingState(scope: WindowScope(_a), zIndex: 0),
  },
  focusedShellId: _shell,
);

void main() {
  late UndoController undo;
  late WindowingController c;

  Future<void> pump(
    WidgetTester tester, {
    WindowingDelegate delegate = const WindowingDelegate(),
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    undo = UndoController();
    c = WindowingController(initial: () => _doc(), undo: undo);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: WindowingRoot(
          controller: c,
          bufferBuilder: (_, buffer) =>
              SizedBox.expand(key: ValueKey('page ${buffer.value}')),
          delegate: delegate,
          child: const ShellHost(_shell),
        ),
      ),
    );
  }

  Rect rect(WidgetTester tester, String buffer) =>
      tester.getRect(find.byKey(ValueKey('page $buffer')));

  testWidgets('each scope shows its floating windows, cascaded or hinted', (
    tester,
  ) async {
    await pump(tester);
    expect(rect(tester, 'f1'), const Rect.fromLTWH(500, 400, 200, 100));
    expect(rect(tester, 'f2'), const Rect.fromLTWH(40, 40, 280, 160));
    expect(rect(tester, 'f4'), const Rect.fromLTWH(72, 72, 280, 160));
    expect(rect(tester, 'f3'), const Rect.fromLTWH(40, 40, 280, 160));

    c.activateTab(_t2);
    await tester.pump();
    expect(find.byKey(const ValueKey('page f1')), findsOneWidget);
    expect(find.byKey(const ValueKey('page f2')), findsNothing);
    expect(find.byKey(const ValueKey('page f3')), findsNothing);
  });

  testWidgets('the top window takes the tap; tapping one raises it', (
    tester,
  ) async {
    await pump(tester);
    int z(WindowId w) => c.doc.value.floating[w]!.zIndex;

    await tester.tapAt(const Offset(100, 100)); // f4 covers f2 here
    expect((z(_f2), z(_f4)), (0, 1));
    // f3 (window scope) sits under the tab layer at (50, 50); f2 is on top.
    await tester.tapAt(const Offset(50, 50));
    await tester.pump();
    expect((z(_f2), z(_f4)), (2, 1));
    await tester.tapAt(const Offset(100, 100)); // now f2 covers f4
    await tester.pump();
    expect((z(_f2), z(_f4)), (2, 1));
  });

  testWidgets('a drag moves the window, clamped, as one undo step', (
    tester,
  ) async {
    await pump(tester);
    final gesture = await tester.startGesture(const Offset(50, 50));
    for (var i = 0; i < 5; i++) {
      await gesture.moveBy(const Offset(20, 10));
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();
    final moved = rect(tester, 'f2');
    expect(moved.topLeft, greaterThan(const Offset(100, 50)));
    expect(c.doc.value.floating[_f2]!.geometry, moved);

    await tester.drag(
      find.byKey(const ValueKey('page f2')),
      const Offset(2000, 0),
    );
    await tester.pump();
    expect(rect(tester, 'f2').right, 800);

    undo.undo();
    await tester.pump();
    expect(rect(tester, 'f2'), moved);
    undo.undo();
    await tester.pump();
    expect(c.doc.value.floating[_f2]!.geometry, isNull);
  });

  testWidgets('window-scoped floating windows stay within their window', (
    tester,
  ) async {
    await pump(tester);
    c.closeWindow(_f2); // the tab layer covers f3: clear it
    c.closeWindow(_f4);
    await tester.pump();
    await tester.drag(
      find.byKey(const ValueKey('page f3')),
      const Offset(2000, 2000),
    );
    await tester.pump();
    final window = rect(tester, 'a');
    expect(window.contains(rect(tester, 'f3').topLeft), isTrue);
    expect(rect(tester, 'f3').right, window.right);
    expect(rect(tester, 'f3').bottom, window.bottom);
  });

  testWidgets('the floating hook wraps each floating window', (tester) async {
    await pump(
      tester,
      delegate: WindowingDelegate(
        floating: (context, windowId, geometry, index, window) =>
            windowId == _f2 ? const SizedBox.shrink() : const Text('custom'),
      ),
    );
    expect(find.byKey(const ValueKey('page f2')), findsNothing);
    expect(find.text('custom'), findsNWidgets(3));
  });

  testWidgets('a shell float covers the chrome the surface builder draws', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final c = WindowingController(initial: () => _doc());
    addTearDown(c.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: WindowingRoot(
          controller: c,
          bufferBuilder: (_, _) => const SizedBox.expand(),
          delegate: WindowingDelegate(
            floating: (_, id, _, _, window) => id == _f1
                ? const SizedBox.expand(key: ValueKey('cover'))
                : const SizedBox.shrink(),
          ),
          child: ShellHost(
            _shell,
            surfaceBuilder: (_, _, canvas) => Column(
              children: [
                const SizedBox(height: 50),
                Expanded(child: canvas),
              ],
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('cover'))),
      const Rect.fromLTWH(0, 0, 800, 600),
    );
  });
}
