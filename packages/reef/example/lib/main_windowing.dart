// The windowing playground: a WindowingController driven by the controls of
// WindowingDemo. Run: fvm flutter run -t lib/main_windowing.dart -d windows
import 'package:flutter/material.dart';
import 'package:reef/reef.dart';
import 'package:reef_example/features/windowing/windowing_demo.dart';

void main() {
  final undo = UndoController();
  final controller = WindowingController(undo: undo);
  final empty = controller.doc.value.shells.values.single.activeTabId;
  controller
    ..newTab(buffer: const BufferId.manual('welcome'))
    ..closeTab(empty);
  undo.clear(); // the starting layout is not an undo step
  runApp(MaterialApp(
    title: 'Reef windowing',
    theme: ThemeData(useMaterial3: true),
    home: Scaffold(body: WindowingDemo(controller: controller, undo: undo)),
  ));
}
