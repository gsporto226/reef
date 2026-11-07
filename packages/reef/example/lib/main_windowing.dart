// The windowing playground: a WindowingController driven by the controls of
// WindowingDemo. Run: fvm flutter run -t lib/main_windowing.dart -d windows
import 'package:flutter/material.dart';
import 'package:reef/reef.dart';
import 'package:reef_example/features/windowing/windowing_demo.dart';

/// One shell with one tab showing [buffer]. Built on a throwaway controller so
/// the starting layout is not an undo step.
WindowingDoc startingLayout(BufferId buffer) {
  final seed = WindowingController();
  final empty = seed.doc.value.shells.values.single.activeTabId;
  seed
    ..newTab(buffer: buffer)
    ..closeTab(empty);
  final doc = seed.doc.value;
  seed.dispose();
  return doc;
}

void main() {
  final undo = UndoController();
  final controller = WindowingController(
      initial: startingLayout(const BufferId.manual('welcome')), undo: undo);
  runApp(MaterialApp(
    title: 'Reef windowing',
    theme: ThemeData(useMaterial3: true),
    home: Scaffold(body: WindowingDemo(controller: controller, undo: undo)),
  ));
}
