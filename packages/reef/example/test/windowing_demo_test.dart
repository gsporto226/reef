import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reef/reef.dart';
import 'package:reef_example/features/windowing/windowing_demo.dart';
import 'package:reef_example/main_windowing.dart' as playground;
import 'package:reef_example/undo_providers.dart';
import 'package:reef_fp/result.dart';

void main() {
  late UndoController undo;
  late WindowingController c;

  /// Draws [shellId] (the first shell by default) in the playground.
  Future<void> show(WidgetTester tester, [ShellId? shellId]) =>
      tester.pumpWidget(
        ProviderScope(
          overrides: [undoControllerProvider.overrideWithValue(undo)],
          child: WindowingPlayground(
            controller: c,
            child: PlaygroundShell(
              shellId ?? c.doc.value.shells.keys.first,
              key: ValueKey(shellId),
            ),
          ),
        ),
      );

  Future<void> pump(WidgetTester tester, {bool canPopOut = true}) async {
    undo = UndoController();
    c = WindowingController(
      initial: () => playground.startingLayout(const BufferId.manual('b')),
      undo: undo,
      platform: FakeShellPlatform(isSupported: canPopOut),
    );
    addTearDown(c.dispose);
    tester.view.physicalSize =
        const Size(1200, 800) * tester.view.devicePixelRatio;
    addTearDown(tester.view.reset);
    await show(tester);
  }

  testWidgets('Undo and Redo buttons follow and drive the timeline', (
    tester,
  ) async {
    await pump(tester);
    bool enabled(IconData icon) =>
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, icon))
            .onPressed !=
        null;
    int tabs() => c.doc.value.tabs.length;

    expect((enabled(Icons.undo), enabled(Icons.redo)), (false, false));
    c.newTab();
    await tester.pump();
    expect((enabled(Icons.undo), enabled(Icons.redo)), (true, false));

    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();
    expect(tabs(), 1);
    expect((enabled(Icons.undo), enabled(Icons.redo)), (false, true));

    await tester.tap(find.byTooltip('Redo'));
    await tester.pump();
    expect(tabs(), 2);
  });

  testWidgets('two drags on one divider are two undo steps', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('Split right'));
    await tester.pumpAndSettle();
    final split = c.doc.value;
    final divider = find.byType(WindowResizeHandle);

    await tester.drag(divider, const Offset(60, 0));
    await tester.pumpAndSettle();
    final afterFirst = c.doc.value;
    await tester.drag(divider, const Offset(60, 0));
    await tester.pumpAndSettle();

    undo.undo();
    expect(c.doc.value, afterFirst);
    undo.undo();
    expect(c.doc.value, split);
  });

  testWidgets('the projection switch forces tabs or desktop over the screen '
      'class', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('Split right'));
    await tester.pumpAndSettle();
    Finder windows() => find.byTooltip('Close window');
    Future<void> project(String item) async {
      await tester.tap(find.byTooltip('Projection'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item).last);
      await tester.pumpAndSettle();
    }

    expect(windows(), findsNWidgets(2));
    await project('Tabbed');
    expect(windows(), findsOneWidget);

    tester.view.physicalSize =
        const Size(700, 800) * tester.view.devicePixelRatio;
    await project('Desktop');
    expect(windows(), findsNWidgets(2));
    await project('Auto');
    expect(windows(), findsOneWidget);
    expect(c.restoration.claimChild('playground').read('projection'), 'auto');
  });

  testWidgets('the projection switch is saved in a restoration bucket and restored from it', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byTooltip('Split right'));
    await tester.tap(find.byTooltip('Projection'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tabbed').last);
    await tester.pumpAndSettle();
    expect(c.restoration.claimChild('playground').read('projection'), 'tabbed');

    await tester.pumpWidget(const SizedBox());
    await show(tester);
    expect(find.byTooltip('Close window'), findsOneWidget);
  });

  testWidgets('New shell and Pop out tab are absent when shells cannot pop '
      'out', (tester) async {
    await pump(tester, canPopOut: false);
    expect(find.byTooltip('New shell'), findsNothing);
    expect(find.byTooltip('Pop out tab'), findsNothing);
  });

  testWidgets('New shell opens a second shell, which brings Close shell', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byTooltip('Close shell'), findsNothing);
    await tester.tap(find.byTooltip('New shell'));
    await tester.pumpAndSettle();
    expect(c.doc.value.shells, hasLength(2));
    expect(find.byTooltip('Close shell'), findsOneWidget);

    final first = c.doc.value.shells.keys.first;
    await tester.tap(find.byTooltip('Close shell'));
    await show(tester, c.doc.value.shells.keys.single);
    expect(c.doc.value.shells.keys, isNot(contains(first)));
  });

  testWidgets('Pop out tab moves the tab to a new shell with its window '
      'tree, floating windows and histories', (tester) async {
    await pump(tester);
    final window = c.doc.value.windows.keys.single;
    c.pushBuffer(window, const BufferId.manual('next'));
    await tester.pump();
    await tester.tap(find.byTooltip('Split right'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Float').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Float over tab'));
    await tester.pumpAndSettle();
    c.newTab();
    final popped = c.doc.value.shells.values.single.tabIds.first;
    c.activateTab(popped);
    await tester.pump();

    await tester.tap(find.byTooltip('Pop out tab'));
    await tester.pumpAndSettle();
    final shell = c.doc.value.shells.keys.last;
    expect(c.doc.value.shells[shell]!.tabIds, [popped]);

    await show(tester, shell);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Close window'), findsNWidgets(2));
    expect(find.text('Dock'), findsNothing);
    expect(find.byTooltip('Dock'), findsOneWidget);
    expect(find.text('next'), findsWidgets);
    expect(find.text('back: b\nforward: '), findsWidgets);
  });

  testWidgets('a vetoed shell close shows in the status bar', (tester) async {
    await pump(tester);
    final first = c.doc.value.shells.keys.single;
    final second = (await c.openShell() as Ok<ShellError, ShellId>).value;
    c
      ..activateShell(first)
      ..newTab();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close shell'));
    await tester.pump();
    expect(
      find.text("Vetoed: Close the shell's other tabs first"),
      findsOneWidget,
    );

    // What ShellViews dispatches on the platform close button.
    c
      ..activateShell(second)
      ..newTab()
      ..closeShell(second);
    await tester.pump();
    expect(c.doc.value.shells, hasLength(2));
  });
}
