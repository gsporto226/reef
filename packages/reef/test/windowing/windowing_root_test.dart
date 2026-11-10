import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reef/reef.dart';

const _shell = ShellId.manual('s');
const _tab = TabId.manual('t');
const _a = WindowId.manual('a');
const _b = WindowId.manual('b');
const _c = WindowId.manual('c');

WindowState _shows(String buffer) =>
    WindowState(history: BufferHistory(current: BufferId.manual(buffer)));

/// One shell, one tab: `a` left (25%), `b` over `c` right (75%, halves).
WindowingDoc _mixed() => WindowingDoc(
  shells: {
    _shell: ShellState(tabIds: [_tab], activeTabId: _tab),
  },
  tabs: {
    _tab: TabState(
      activeWindowId: _a,
      root: WindowBranch(
        axis: Axis.horizontal,
        ratios: [0.25, 0.75],
        children: [
          const WindowLeaf(_a),
          WindowBranch(
            axis: Axis.vertical,
            ratios: [0.5, 0.5],
            children: const [WindowLeaf(_b), WindowLeaf(_c)],
          ),
        ],
      ),
    ),
  },
  windows: {_a: _shows('A'), _b: _shows('B'), _c: _shows('C')},
  focusedShellId: _shell,
);

/// A page with local state (a tap counter) that counts its builds.
class _Page extends StatefulWidget {
  const _Page(this.buffer);

  final BufferId buffer;

  static final builds = <String, int>{};

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  int taps = 0;

  @override
  Widget build(BuildContext context) {
    _Page.builds.update(widget.buffer.value, (n) => n + 1, ifAbsent: () => 1);
    return GestureDetector(
      onTap: () => setState(() => taps++),
      child: SizedBox.expand(child: Text('${widget.buffer.value}:$taps')),
    );
  }
}

Widget _root(WindowingController controller, {Widget? child}) => Directionality(
  textDirection: TextDirection.ltr,
  child: WindowingRoot(
    controller: controller,
    bufferBuilder: (_, buffer) => _Page(buffer),
    child: child,
  ),
);

Future<WindowingController> _pump(
  WidgetTester tester,
  WindowingDoc doc, {
  Widget? child,
}) async {
  _Page.builds.clear();
  await tester.binding.setSurfaceSize(const Size(800, 600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final controller = WindowingController(initial: doc);
  addTearDown(controller.dispose);
  await tester.pumpWidget(_root(controller, child: child));
  return controller;
}

Size _sizeOf(WidgetTester tester, String buffer) => tester.getSize(
  find.byWidgetPredicate((w) => w is _Page && w.buffer.value == buffer),
);

void main() {
  testWidgets('a unit with no root above fails with a clear error', (
    tester,
  ) async {
    await tester.pumpWidget(const TabCanvas(_tab));
    final error = tester.takeException();
    expect(error, isA<FlutterError>());
    expect('$error', contains('No WindowingRoot found'));
  });

  testWidgets('the root draws the focused shell\'s active tab under its '
      'tab strip, children sized by their ratios', (tester) async {
    await _pump(tester, _mixed());
    // Less the 14px tab strip, and the 8px resize handle between siblings.
    expect(find.text('Tab 1'), findsOneWidget);
    expect(_sizeOf(tester, 'A'), const Size(198, 586));
    expect(_sizeOf(tester, 'B'), const Size(594, 289));
    expect(_sizeOf(tester, 'C'), const Size(594, 289));
  });

  testWidgets('an empty tab renders a blank placeholder', (tester) async {
    await _pump(tester, WindowingDoc.initial());
    expect(find.byType(_Page), findsNothing);
  });

  testWidgets('ShellHost renders under the app\'s surface builder', (
    tester,
  ) async {
    await _pump(
      tester,
      _mixed(),
      child: ShellHost(
        _shell,
        surfaceBuilder: (_, shell, canvas) => Column(
          children: [
            Text('surface ${shell.value}'),
            Expanded(child: canvas),
          ],
        ),
      ),
    );
    expect(find.text('surface s'), findsOneWidget);
    expect(find.text('A:0'), findsOneWidget);
  });

  testWidgets('history moves swap the shown buffer', (tester) async {
    final c = await _pump(tester, _mixed());
    c.pushBuffer(_a, const BufferId.manual('X'));
    await tester.pump();
    expect(find.text('X:0'), findsOneWidget);
    c.popBuffer(_a);
    await tester.pump();
    expect(find.text('A:0'), findsOneWidget);
    c.navigateForward(_a);
    await tester.pump();
    expect(find.text('X:0'), findsOneWidget);
    c.replaceBuffer(_a, const BufferId.manual('Y'));
    await tester.pump();
    expect(find.text('Y:0'), findsOneWidget);
  });

  testWidgets('two windows on one buffer stay in live sync', (tester) async {
    final c = await _pump(tester, _mixed());
    c.replaceBuffer(_b, const BufferId.manual('A'));
    await tester.pump();
    expect(find.text('A:0'), findsNWidgets(2));
    c.pushBuffer(_a, const BufferId.manual('X'));
    await tester.pump();
    expect(find.text('A:0'), findsOneWidget);
    expect(find.text('X:0'), findsOneWidget);
  });

  testWidgets('a page keeps its state when a sibling splits, resizes and '
      'closes', (tester) async {
    final c = await _pump(tester, _mixed());
    await tester.tap(find.text('A:0'));
    await tester.pump();
    expect(find.text('A:1'), findsOneWidget);

    // Splitting `a` itself moves its page one level deeper.
    final d = c.splitWindow(_a, axis: Axis.vertical);
    await tester.pump();
    c.resizeWindow(_b, [0.4, 0.6]);
    await tester.pump();
    c.closeWindow(_b);
    await tester.pump();
    c.closeWindow(d);
    await tester.pump();
    expect(find.text('A:1'), findsOneWidget);
  });

  testWidgets('a new buffer builder on the root redraws the pages', (
    tester,
  ) async {
    final controller = await _pump(tester, _mixed());
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: WindowingRoot(
          controller: controller,
          bufferBuilder: (_, buffer) => Text('new ${buffer.value}'),
        ),
      ),
    );
    expect(find.text('new A'), findsOneWidget);
  });

  testWidgets('tapping a window activates it', (tester) async {
    final c = await _pump(tester, _mixed());
    await tester.tap(find.text('C:0'));
    expect(c.doc.value.tabs[_tab]!.activeWindowId, _c);
  });

  testWidgets('rebuilds follow per-entity selections', (tester) async {
    final other = ShellId.manual('s2');
    final c = await _pump(
      tester,
      _mixed(),
      child: Row(
        children: [
          const Expanded(child: ShellHost(_shell)),
          Expanded(child: ShellHost(other)),
        ],
      ),
    );
    c.dispatchAll([
      AttachShell(other, tabId: const TabId.manual('t2')),
      NewTab(
        shellId: other,
        tabId: const TabId.manual('t3'),
        buffer: (const WindowId.manual('o'), const BufferId.manual('O')),
      ),
    ]);
    await tester.pump();
    _Page.builds.clear();

    // A tab switch in the other shell leaves this shell's windows alone.
    c.activateTab(const TabId.manual('t2'));
    await tester.pump();
    expect(_Page.builds, isEmpty);

    // A history move rebuilds only that window.
    c.pushBuffer(_b, const BufferId.manual('X'));
    await tester.pump();
    expect(_Page.builds, {'X': 1});

    // An unchanged dispatch rebuilds nothing.
    _Page.builds.clear();
    c.popBuffer(_c);
    await tester.pump();
    expect(_Page.builds, isEmpty);
  });

  test('rendering units import the widgets library only', () {
    final dir = Directory('lib/features/windowing/_implementations');
    for (final file in dir.listSync().whereType<File>()) {
      final src = file.readAsStringSync();
      expect(
        src,
        isNot(contains('package:flutter/material.dart')),
        reason: file.path,
      );
      expect(
        src,
        isNot(contains('package:flutter/cupertino.dart')),
        reason: file.path,
      );
    }
  });

  group('interceptor ownership', () {
    CommandDecision own(WindowingDoc _, WindowingCommand _) =>
        const CommandDecision.approve();
    CommandDecision delegated(WindowingDoc _, WindowingCommand _) =>
        const CommandDecision.approve();

    Widget root(WindowingController c, WindowingDelegate delegate) =>
        Directionality(
          textDirection: TextDirection.ltr,
          child: WindowingRoot(
            controller: c,
            bufferBuilder: (_, _) => const SizedBox.expand(),
            delegate: delegate,
          ),
        );

    testWidgets("a delegate without one keeps the controller's", (
      tester,
    ) async {
      final c = WindowingController(initial: _mixed(), interceptor: own);
      addTearDown(c.dispose);
      await tester.pumpWidget(root(c, const WindowingDelegate()));
      expect(c.interceptor, own);
    });

    testWidgets("the delegate's is installed on mount and on change, and "
        'the previous one comes back on unmount', (tester) async {
      final c = WindowingController(initial: _mixed(), interceptor: own);
      addTearDown(c.dispose);
      await tester.pumpWidget(
        root(c, WindowingDelegate(interceptor: delegated)),
      );
      expect(c.interceptor, delegated);
      await tester.pumpWidget(root(c, const WindowingDelegate()));
      expect(c.interceptor, own);
      await tester.pumpWidget(
        root(c, WindowingDelegate(interceptor: delegated)),
      );
      expect(c.interceptor, delegated);
      await tester.pumpWidget(const SizedBox());
      expect(c.interceptor, own);
    });
  });
}
