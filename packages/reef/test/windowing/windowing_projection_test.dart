import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reef/reef.dart';

const _shell = ShellId.manual('s');
const _t1 = TabId.manual('t1');
const _t2 = TabId.manual('t2');
const _a = WindowId.manual('a');
const _b = WindowId.manual('b');
const _f = WindowId.manual('f');

WindowState _shows(String buffer) =>
    WindowState(history: BufferHistory(current: BufferId.manual(buffer)));

/// Tab `t1`: `a` beside `b`, `a` active, a floating `f`. Tab `t2`: empty.
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
        children: const [WindowLeaf(_a), WindowLeaf(_b)],
      ),
    ),
    _t2: const TabState(),
  },
  windows: {_a: _shows('A'), _b: _shows('B'), _f: _shows('F')},
  floating: {_f: const FloatingState(scope: TabScope(_t1), zIndex: 0)},
  focusedShellId: _shell,
);

Future<WindowingController> _pump(
  WidgetTester tester, {
  double width = 1000,
  WindowingDelegate delegate = const WindowingDelegate(),
  Widget? child,
}) async {
  tester.view.physicalSize = Size(width, 600) * tester.view.devicePixelRatio;
  final controller = WindowingController(initial: _doc());
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: WindowingRoot(
        controller: controller,
        delegate: delegate,
        bufferBuilder: (_, buffer) => Text('page ${buffer.value}'),
        child: child,
      ),
    ),
  );
  return controller;
}

Future<void> _resize(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 600) * tester.view.devicePixelRatio;
  await tester.pump();
}

void main() {
  testWidgets('an expanded screen gets the desktop projection: tab strip and '
      'tiled windows', (tester) async {
    await _pump(tester);
    expect(find.byType(DesktopProjection), findsOneWidget);
    expect(find.text('Tab 1'), findsOneWidget);
    expect(find.text('page A'), findsOneWidget);
    expect(find.text('page B'), findsOneWidget);
  });

  testWidgets('medium and compact screens get the tabbed projection: tab bar, '
      'the focused window only, floating windows still drawn', (tester) async {
    for (final width in [700.0, 400.0]) {
      await _pump(tester, width: width);
      expect(find.byType(TabbedProjection), findsOneWidget);
      expect(find.text('Tab 1'), findsOneWidget);
      expect(find.text('page A'), findsOneWidget);
      expect(find.text('page B'), findsNothing);
      expect(find.text('page F'), findsOneWidget);
    }
  });

  testWidgets('focusedOnly shows the window activated next', (tester) async {
    final c = await _pump(
      tester,
      delegate: const WindowingDelegate(
        windowArrangement: WindowArrangement.focusedOnly,
      ),
      child: const ShellHost(_shell),
    );
    expect(find.text('page B'), findsNothing);
    c.activateWindow(_b);
    await tester.pump();
    expect(find.text('page A'), findsNothing);
    expect(find.text('page B'), findsOneWidget);
  });

  testWidgets('without a delegate arrangement, a bare canvas follows the '
      'screen class', (tester) async {
    await _pump(tester, child: const ShellHost(_shell));
    expect(find.text('page B'), findsOneWidget);
    await _resize(tester, 700);
    expect(find.text('page B'), findsNothing);
  });

  testWidgets('resizing across the breakpoint switches projection over an '
      'unchanged doc; resizing back restores the picture', (tester) async {
    final c = await _pump(tester);
    final doc = c.doc.value;
    final before = tester.getRect(find.text('page B'));

    await _resize(tester, 700);
    expect(find.byType(TabbedProjection), findsOneWidget);
    expect(find.text('page B'), findsNothing);
    expect(c.doc.value, doc);

    await _resize(tester, 1000);
    expect(find.byType(DesktopProjection), findsOneWidget);
    expect(tester.getRect(find.text('page B')), before);
    expect(c.doc.value, doc);
  });

  testWidgets('the policy can be replaced, e.g. always tabs', (tester) async {
    await _pump(
      tester,
      delegate: WindowingDelegate(
        projectionPolicy: (_, _, _) =>
            (_, _, shellId) => TabbedProjection(shellId),
      ),
    );
    expect(find.text('page A'), findsOneWidget);
    expect(find.text('page B'), findsNothing);
  });

  testWidgets('a projection\'s tab strip slot can be swapped or dropped', (
    tester,
  ) async {
    await _pump(
      tester,
      child: TabbedProjection(
        _shell,
        tabBar: (_, shellId) => Text('bar ${shellId.value}'),
      ),
    );
    expect(find.text('bar s'), findsOneWidget);
    expect(find.text('Tab 1'), findsNothing);

    await _pump(
      tester,
      child: DesktopProjection(
        _shell,
        tabStrip: (_, shellId) => Text('strip ${shellId.value}'),
      ),
    );
    expect(find.text('strip s'), findsOneWidget);

    await _pump(
      tester,
      child: const DesktopProjection(_shell, showTabStrip: false),
    );
    expect(find.text('Tab 1'), findsNothing);
    expect(find.text('page B'), findsOneWidget);
  });
}
