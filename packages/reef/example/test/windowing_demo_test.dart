import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reef/reef.dart';
import 'package:reef_example/features/windowing/windowing_demo.dart';
import 'package:reef_example/main_windowing.dart' as playground;
import 'package:reef_example/undo_providers.dart';

void main() {
  late UndoController undo;
  late WindowingController c;

  Future<void> pump(WidgetTester tester) async {
    undo = UndoController();
    c = WindowingController(
        initial: playground.startingLayout(const BufferId.manual('b')),
        undo: undo);
    tester.view.physicalSize =
        const Size(1200, 800) * tester.view.devicePixelRatio;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [undoControllerProvider.overrideWithValue(undo)],
      child: MaterialApp(
        home: Scaffold(body: WindowingDemo(controller: c)),
      ),
    ));
  }

  testWidgets('Undo and Redo buttons follow and drive the timeline',
      (tester) async {
    await pump(tester);
    bool enabled(IconData icon) =>
        tester.widget<IconButton>(find.widgetWithIcon(IconButton, icon))
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
  });
}
