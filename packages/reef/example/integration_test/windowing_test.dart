import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reef/reef.dart';
import 'package:reef_example/features/windowing/windowing_demo.dart';
import 'package:reef_example/main_windowing.dart' as playground;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<WindowingController> pump(WidgetTester tester,
      {BufferId? buffer}) async {
    final undo = UndoController();
    final controller = WindowingController(undo: undo);
    if (buffer != null) {
      final empty = controller.doc.value.shells.values.single.activeTabId;
      controller
        ..newTab(buffer: buffer)
        ..closeTab(empty);
      undo.clear();
    }
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: WindowingDemo(controller: controller, undo: undo)),
    ));
    return controller;
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> menu(WidgetTester tester, String tooltip, String item) async {
    await tap(tester, find.byTooltip(tooltip).first);
    await tap(tester, find.text(item));
  }

  Finder status(String text) => find.textContaining(text);

  List<double> rootRatios(WindowingController c) {
    final shell = c.doc.value.shells[c.doc.value.focusedShellId]!;
    return (c.doc.value.tabs[shell.activeTabId]!.root! as WindowBranch).ratios;
  }

  testWidgets('playground entrypoint opens a welcome window', (tester) async {
    playground.main();
    await tester.pumpAndSettle();
    expect(status('Focus: Shell 1 > Tab 1 > welcome'), findsOneWidget);
  });

  testWidgets('new tab, activate, close', (tester) async {
    await pump(tester);
    expect(find.textContaining('Empty tab'), findsOneWidget);

    await tap(tester, find.byTooltip('New tab'));
    expect(find.text('Tab 2'), findsOneWidget);
    expect(status('Focus: Shell 1 > Tab 2 > buffer 1'), findsOneWidget);

    await tap(tester, find.text('Tab 1'));
    expect(status('Focus: Shell 1 > Tab 1    '), findsOneWidget);

    await tap(tester, find.byTooltip('Close tab 2'));
    expect(find.text('Tab 2'), findsNothing);
  });

  testWidgets('split, resize, close window', (tester) async {
    final c = await pump(tester, buffer: const BufferId.manual('b'));

    await tap(tester, find.byTooltip('Split right'));
    expect(status('windows in tab: 2'), findsOneWidget);
    expect(rootRatios(c), [0.5, 0.5]);

    await tester.drag(find.byKey(const ValueKey('divider')), const Offset(120, 0));
    await tester.pumpAndSettle();
    expect(rootRatios(c).first, greaterThan(0.5));

    await tap(tester, find.byTooltip('Split down').first);
    await tester.drag(
        find.byKey(const ValueKey('divider')).first, const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(status('windows in tab: 3'), findsOneWidget);

    // Root children all branches: its divider resizes through a nested leaf.
    await tap(tester, find.byTooltip('Split down').last);
    final before = rootRatios(c).first;
    // Depth-first order: left branch's divider, root's divider, right's.
    await tester.drag(
        find.byKey(const ValueKey('divider')).at(1), const Offset(80, 0));
    await tester.pumpAndSettle();
    expect(rootRatios(c).first, greaterThan(before));

    for (var n = 4; n > 0; n--) {
      await tap(tester, find.byTooltip('Close window').first);
    }
    expect(find.textContaining('Empty tab'), findsOneWidget);
  });

  testWidgets('activate, push, back, forward', (tester) async {
    await pump(tester, buffer: const BufferId.manual('b'));
    await tap(tester, find.byTooltip('Open new buffer'));
    expect(find.text('buffer 1'), findsOneWidget);

    await tap(tester, find.byTooltip('Back'));
    expect(find.text('b'), findsOneWidget);
    await tap(tester, find.byTooltip('Forward'));
    expect(find.text('buffer 1'), findsOneWidget);

    await tap(tester, find.byTooltip('Split right'));
    await tap(tester, find.byTooltip('Open new buffer').last);
    expect(status('> buffer 2'), findsOneWidget);
    await tap(tester, find.textContaining('back:').first);
    expect(status('> buffer 1'), findsOneWidget);
  });

  testWidgets('shells, move tab, move window', (tester) async {
    await pump(tester, buffer: const BufferId.manual('b'));

    await tap(tester, find.byTooltip('New shell'));
    expect(status('Focus: Shell 2 > Tab 1'), findsOneWidget);
    expect(find.textContaining('Empty tab'), findsOneWidget);

    await tap(tester, find.text('Shell 1'));
    await tap(tester, find.byTooltip('New tab'));
    await menu(tester, 'Move tab to shell', 'To shell 2');
    expect(status('Focus: Shell 2 > Tab 2 > buffer 1'), findsOneWidget);

    await menu(tester, 'Move to tab', 'To Shell 2, tab 1');
    expect(status('Focus: Shell 2 > Tab 1 > buffer 1'), findsOneWidget);

    await tap(tester, find.byTooltip('Close shell 1'));
    expect(find.text('Shell 2'), findsNothing);
    expect(find.text('b'), findsNothing);
    expect(find.text('buffer 1'), findsOneWidget);
  });

  testWidgets('undo and redo a split, focus changes not recorded',
      (tester) async {
    final undo = UndoController();
    final c = WindowingController(undo: undo)
      ..newTab(buffer: const BufferId.manual('b'));
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: WindowingDemo(controller: c, undo: undo)),
    ));

    await tap(tester, find.byTooltip('Split right'));
    expect(status('windows in tab: 2'), findsOneWidget);
    await tap(tester, find.text('Tab 1'));
    await tap(tester, find.text('Tab 2'));

    undo.undo();
    await tester.pumpAndSettle();
    expect(status('windows in tab: 1'), findsOneWidget);

    undo.redo();
    await tester.pumpAndSettle();
    expect(status('windows in tab: 2'), findsOneWidget);
  });

  testWidgets('undo/redo buttons: split, close, drag', (tester) async {
    final c = await pump(tester, buffer: const BufferId.manual('b'));
    bool enabled(String tooltip) => tester
            .widget<IconButton>(find.widgetWithIcon(IconButton,
                tooltip == 'Undo' ? Icons.undo : Icons.redo))
            .onPressed !=
        null;
    expect(enabled('Undo'), isFalse);
    expect(enabled('Redo'), isFalse);

    await tap(tester, find.byTooltip('Split right'));
    await tap(tester, find.byTooltip('Close window').first);
    expect(status('windows in tab: 1'), findsOneWidget);

    await tap(tester, find.byTooltip('Undo'));
    expect(status('windows in tab: 2'), findsOneWidget);
    await tap(tester, find.byTooltip('Undo'));
    expect(status('windows in tab: 1'), findsOneWidget);
    expect(enabled('Undo'), isFalse);
    await tap(tester, find.byTooltip('Redo'));
    expect(status('windows in tab: 2'), findsOneWidget);

    // One drag, many ResizeWindow updates: one undo step.
    final gesture = await tester
        .startGesture(tester.getCenter(find.byKey(const ValueKey('divider'))));
    for (var i = 0; i < 5; i++) {
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(rootRatios(c).first, greaterThan(0.5));
    await tap(tester, find.byTooltip('Undo'));
    expect(rootRatios(c), [0.5, 0.5]);
    expect(status('windows in tab: 2'), findsOneWidget);
  });

  testWidgets('float, drag, raise, dock', (tester) async {
    final c = await pump(tester, buffer: const BufferId.manual('b'));
    await tap(tester, find.byTooltip('Split right'));
    await tap(tester, find.byTooltip('Open new buffer').last);

    await menu(tester, 'Float', 'Float over tab');
    await menu(tester, 'Float', 'Float over tab');
    expect(status('floating: 2'), findsOneWidget);
    expect(find.textContaining('Empty tab'), findsOneWidget);

    // 'b' floated first, so it sits below; tapping it raises it.
    await tester.drag(find.text('buffer 1'), const Offset(300, 200));
    await tester.pumpAndSettle();
    await tap(tester, find.text('b'));
    expect(c.doc.value.floating.values.map((f) => f.zIndex), contains(2));

    await menu(tester, 'Dock', 'Dock left');
    await menu(tester, 'Dock', 'Dock bottom');
    expect(status('floating: 0'), findsOneWidget);
    expect(status('windows in tab: 2'), findsOneWidget);
  });
}
