import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reef/reef.dart';
import 'package:reef_fp/result.dart';
import 'package:reef_fp/unit.dart';

class _Vm extends ViewModel<String> with UndoableModel<String> {
  _Vm(BufferUndoHost host, BufferId id, [super.initial = '']) {
    attachUndo(host, id);
    bindText(controller, $model,
        apply: (v) => Ok<Never, String>(v), via: op, coalesceKey: #text);
  }

  final controller = TextEditingController();
  late final op = operation<Unit, Never>();
  void set(String v, [Object? key]) => publish(v, coalesceKey: key);
}

void main() {
  const id = BufferId.manual('b');
  late UndoController undo;
  late BufferUndoHost host;

  setUp(() {
    undo = UndoController();
    host = BufferUndoHost(undo);
  });

  test('BufferSnapshot carries buffer id and model; equal by value', () {
    const s = BufferSnapshot(id, 'x');
    expect((s.bufferId, s.model), (id, 'x'));
    expect(BufferSnapshot(id, 'x'.toString()), s);
    expect(BufferSnapshot(id, 'x').hashCode, s.hashCode);
    expect(s, isNot(const BufferSnapshot(id, 'y')));
  });

  test('entries are labelled Edit', () {
    _Vm(host, id).set('a');
    expect(undo.labels.single.localize(), 'Edit');
  });

  test('same-key edits of one buffer coalesce; a new key breaks the run', () {
    final vm = _Vm(host, id)
      ..set('a', #f)
      ..set('ab', #f)
      ..set('abc', #g);
    // Same key, other buffer: no merge.
    _Vm(host, const BufferId.manual('other')).set('o', #g);
    undo
      ..undo()
      ..undo();
    expect(vm.model, 'ab');
    undo.undo();
    expect(vm.model, '');
  });

  test('a coalesced run that returns to its start drops the entry', () {
    _Vm(host, id)
      ..set('a', #f)
      ..set('', #f);
    expect(undo.$canUndo.value, isFalse);
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

  test('undo and redo while hibernated are adopted on re-attach', () {
    _Vm(host, id)
      ..set('x')
      ..set('xy')
      ..dispose();
    undo
      ..undo()
      ..undo()
      ..redo();
    expect(_Vm(host, id, 'xy').model, 'x');
    expect(_Vm(host, id, 'xy').model, 'xy', reason: 'adopted only once');
  });

  testWidgets('typing records one step; undo rewrites the text field',
      (tester) async {
    final vm = _Vm(host, id);
    await tester.pumpWidget(MaterialApp(
        home: Material(child: TextField(controller: vm.controller))));
    await tester.enterText(find.byType(TextField), 'h');
    await tester.enterText(find.byType(TextField), 'hi');
    undo.undo();
    await tester.pump();
    expect(find.text('hi'), findsNothing);
    expect(vm.controller.text, '');
  });
}
