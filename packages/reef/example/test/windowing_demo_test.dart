import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reef/reef.dart';
import 'package:reef_example/features/windowing/windowing_demo.dart';
import 'package:reef_example/main_windowing.dart' as playground;

void main() {
  testWidgets('Undo and Redo buttons follow and drive the timeline',
      (tester) async {
    final undo = UndoController();
    final c = WindowingController(
        initial: playground.startingLayout(const BufferId.manual('b')),
        undo: undo);
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: WindowingDemo(controller: c, undo: undo)),
    ));
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
}
