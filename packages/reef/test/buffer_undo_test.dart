import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reef/reef.dart';
import 'package:reef_fp/result.dart';
import 'package:reef_fp/unit.dart';

class _Vm extends ViewModel<String> with UndoableModel<String> {
  _Vm(BufferUndoHost host, BufferId id, [super.initial = '']) {
    attachUndo(host, id);
    bindText(controller, $model,
        apply: (v) => Ok<Never, String>(v), via: op);
  }

  final controller = TextEditingController();
  late final op = operation<Unit, Never>();
  void set(String v) => publish(v);
}

void main() {
  const id = BufferId.manual('b');
  late UndoController undo;
  late BufferUndoHost host;

  setUp(() {
    undo = UndoController();
    host = BufferUndoHost(undo);
  });

  test('BufferSnapshot carries buffer id and model', () {
    const s = BufferSnapshot(id, 'x');
    expect((s.bufferId, s.model), (id, 'x'));
    expect(const BufferEdit().localize(), 'Edit');
  });

  test('records each change; undo and redo restore without recording', () {
    final vm = _Vm(host, id)
      ..set('a')
      ..set('a') // unchanged: not recorded
      ..set('ab');
    undo.undo();
    expect(vm.model, 'a');
    expect(undo.$canRedo.value, isTrue);
    undo.undo();
    expect(vm.model, '');
    expect(undo.$canUndo.value, isFalse);
    undo.redo();
    expect(vm.model, 'a');
    expect(undo.$canRedo.value, isTrue); // redo did not truncate
  });

  test('undo reaches the rematerialized view model after hibernation', () {
    _Vm(host, id)
      ..set('edited')
      ..dispose();
    final reborn = _Vm(host, id, 'edited');
    undo.undo();
    expect(reborn.model, '');
  });

  test('a stale view model disposing keeps the live one attached', () {
    final old = _Vm(host, id);
    final live = _Vm(host, id)..set('x');
    old.dispose();
    undo.undo();
    expect(live.model, '');
  });

  test('undo for a buffer with no live view model is a no-op', () {
    _Vm(host, id)
      ..set('x')
      ..dispose();
    undo.undo();
    expect(undo.$canRedo.value, isTrue);
  });

  testWidgets('typing records; undo rewrites the text field', (tester) async {
    final vm = _Vm(host, id);
    await tester.pumpWidget(MaterialApp(
        home: Material(child: TextField(controller: vm.controller))));
    await tester.enterText(find.byType(TextField), 'hi');
    undo.undo();
    await tester.pump();
    expect(find.text('hi'), findsNothing);
    expect(vm.controller.text, '');
  });
}
