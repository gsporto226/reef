import 'package:flutter_test/flutter_test.dart';
import 'package:reef/reef.dart';

// W6-3: buffer navigation lands on the layout undo timeline.
void main() {
  test('pushing a buffer records no undo entry', () {
    final undo = UndoController();
    final c = WindowingController(undo: undo)
      ..newTab(buffer: const BufferId.manual('a'));
    undo.clearHost<WindowingDoc>();
    final window = c.doc.value.windows.keys.single;

    c.pushBuffer(window, const BufferId.manual('b'));

    expect(undo.$canUndo.value, isFalse);
  });
}
