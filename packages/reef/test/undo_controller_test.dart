import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:formularium/features/localization/localizable_interface.dart';
import 'package:reef/reef.dart';

class _Label implements ILocalizable {
  const _Label();
  @override
  String localize() => 'edit';
}

class _Host<S> implements UndoHost<S> {
  final calls = <String>[];
  @override
  void undo(S snapshotBefore) => calls.add('undo $snapshotBefore');
  @override
  void redo(S snapshotAfter) => calls.add('redo $snapshotAfter');
}

UndoEntry<S> _e<S>(S before, S after, {Object? key}) => UndoEntry<S>(
  label: const _Label(),
  snapshotBefore: before,
  snapshotAfter: after,
  coalesceKey: key,
);

void main() {
  late UndoController c;
  late _Host<int> ints;
  late _Host<String> strings;

  setUp(() {
    c = UndoController();
    ints = _Host<int>();
    strings = _Host<String>();
    c
      ..registerHost<int>(ints)
      ..registerHost<String>(strings);
  });

  test('undo/redo route to the host of the entry type', () {
    c.record<int>(_e(0, 1));
    c.record<String>(_e('a', 'b'));
    c.undo();
    c.undo();
    c.redo();
    expect(strings.calls, ['undo a']);
    expect(ints.calls, ['undo 0', 'redo 1']);
  });

  test('undo and redo are no-ops at the ends', () {
    c.undo();
    c.redo();
    c.record<int>(_e(0, 1));
    c.redo();
    c.undo();
    c.undo();
    expect(ints.calls, ['undo 0']);
  });

  test('recording for an unregistered type asserts', () {
    expect(
      () => c.record<double>(_e(0.0, 1.0)),
      throwsA(isA<AssertionError>()),
    );
  });

  test('record truncates the redo tail', () {
    c.record<int>(_e(0, 1));
    c.record<int>(_e(1, 2));
    c.undo();
    c.record<int>(_e(1, 9));
    expect(c.$canRedo.value, isFalse);
    c.undo();
    c.undo();
    expect(ints.calls, ['undo 1', 'undo 1', 'undo 0']);
  });

  test('equal non-null coalesceKey merges consecutive entries', () {
    c.record<int>(_e(0, 1, key: 'r'));
    c.record<int>(_e(1, 2, key: 'r'));
    c.record<int>(_e(2, 3, key: null));
    c.record<int>(_e(3, 4, key: null));
    c.undo();
    c.undo();
    c.undo();
    c.redo();
    expect(ints.calls, ['undo 3', 'undo 2', 'undo 0', 'redo 2']);
  });

  test('after an undo, a same-key entry does not merge into the applied '
      'entry before the cursor', () {
    c.record<int>(_e(0, 1, key: 'a'));
    c.record<int>(_e(1, 2, key: 'r'));
    c.undo(); // cursor after the a entry, which is applied
    c.record<int>(_e(1, 3, key: 'a'));
    c.undo();
    c.undo();
    expect(ints.calls, ['undo 1', 'undo 1', 'undo 0']);
  });

  test('coalescing back to the start drops the entry', () {
    c.record<int>(_e(0, 1, key: 'r'));
    c.record<int>(_e(1, 0, key: 'r'));
    expect(c.$canUndo.value, isFalse);
  });

  test('keeps at most 64 entries, dropping the oldest', () {
    for (var i = 0; i < 70; i++) {
      c.record<int>(_e(i, i + 1));
    }
    while (c.$canUndo.value) {
      c.undo();
    }
    expect(ints.calls.length, 64);
    expect(ints.calls.last, 'undo 6');
  });

  test('clearHost drops only that type and keeps the cursor in place', () {
    c.record<int>(_e(0, 1));
    c.record<String>(_e('a', 'b'));
    c.record<int>(_e(1, 2));
    c.record<String>(_e('b', 'c'));
    c.undo(); // undo b
    c.clearHost<int>();
    c.undo();
    c.redo();
    c.redo();
    expect(strings.calls, ['undo b', 'undo a', 'redo b', 'redo c']);
    expect(ints.calls, isEmpty);
    c.clearHost<String>();
    expect((c.$canUndo.value, c.$canRedo.value), (false, false));
  });

  test('sealCoalescing ends a run: the next same-key entry is a new step', () {
    c.record<int>(_e(0, 1, key: (#r, 1)));
    c.sealCoalescing();
    c.record<int>(_e(1, 2, key: (#r, 1)));
    c.record<int>(_e(2, 3, key: (#r, 1)));
    c.undo();
    c.undo();
    expect(ints.calls, ['undo 1', 'undo 0']);
  });

  test('labels lists every entry label, oldest first', () {
    c.record<int>(_e(0, 1));
    c.record<String>(_e('a', 'b'));
    c.undo();
    expect(c.labels.map((l) => l.localize()), ['edit', 'edit']);
    expect(const UndoLabel('Edit').localize(), 'Edit');
  });

  test('canUndo/canRedo publish only on change', () {
    var undoHits = 0, redoHits = 0;
    c.$canUndo.addListener(() => undoHits++);
    c.$canRedo.addListener(() => redoHits++);
    c.record<int>(_e(0, 1));
    c.record<int>(_e(1, 2));
    expect((undoHits, redoHits), (1, 0));
    c.undo();
    c.undo();
    expect((undoHits, redoHits), (2, 1));
  });

  testWidgets('widget listens to canUndo', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ValueListenableBuilder<bool>(
          valueListenable: c.$canUndo,
          builder: (_, can, _) => Text(can ? 'can' : 'cannot'),
        ),
      ),
    );
    expect(find.text('cannot'), findsOneWidget);
    c.record<int>(_e(0, 1));
    await tester.pump();
    expect(find.text('can'), findsOneWidget);
  });
}
