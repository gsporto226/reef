import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reef/reef.dart';

const _key = BufferId.manual('restoration:');

final _intList = RestorableCodec<List<int>>(
  encode: (v) => v,
  decode: (json) => [for (final e in json! as List) e as int],
);

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> with ReefRestorationMixin {
  final count = ReefRestorableValue(0);

  @override
  String get restorationId => 'counter';

  @override
  void restoreState() => registerForRestoration(count, 'count');

  @override
  void dispose() {
    count.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Text('${count.value}', textDirection: TextDirection.ltr);
}

void main() {
  late InMemoryHibernationStore store;

  setUp(() => store = InMemoryHibernationStore());

  WindowingController controller() {
    final c = WindowingController(store: store);
    addTearDown(c.dispose);
    return c;
  }

  testWidgets('a controller-claimed value round-trips, saved once per frame', (
    tester,
  ) async {
    final first = controller();
    final ids = ReefRestorableValue(const <int>[], codec: _intList);
    first.claimBucket('app').register('ids', ids);
    expect(ids.value, isEmpty);
    ids.value = [1];
    ids.value = [1, 2];
    expect(store.load(_key), isNull, reason: 'not saved before the frame');
    await tester.pump();
    expect(store.load(_key), isNotNull);

    final again = ReefRestorableValue(const <int>[], codec: _intList);
    controller().claimBucket('app').register('ids', again);
    expect(again.value, [1, 2]);
  });

  testWidgets('a value that fails to decode drops its bucket to defaults', (
    tester,
  ) async {
    final first = controller();
    final bucket = first.claimBucket('app');
    bucket.register('name', ReefRestorableValue('x')..value = 'kept');
    bucket.register('bad', ReefRestorableValue<Object?>(null)..value = 'oops');
    first.claimBucket('other').register('n', ReefRestorableValue(0)..value = 7);
    await tester.pump();

    final c = controller();
    final name = ReefRestorableValue('x');
    final b = c.claimBucket('app')..register('name', name);
    expect(name.value, 'kept');
    final bad = ReefRestorableValue(const <int>[], codec: _intList);
    b.register('bad', bad);
    expect(bad.value, isEmpty);
    expect(name.value, 'x', reason: 'the whole bucket is dropped');
    final n = ReefRestorableValue(0);
    c.claimBucket('other').register('n', n);
    expect(n.value, 7, reason: 'other buckets are kept');
  });

  testWidgets('a malformed record restores defaults', (tester) async {
    store.save(_key, {'values': 'nope'});
    final n = ReefRestorableValue(3);
    controller().claimBucket('app').register('n', n);
    expect(n.value, 3);
  });

  testWidgets('a widget claims a bucket through the mixin', (tester) async {
    Widget app(WindowingController c) => WindowingRoot(
      controller: c,
      bufferBuilder: (_, _) => const SizedBox(),
      child: const _Counter(),
    );
    await tester.pumpWidget(app(controller()));
    tester.state<_CounterState>(find.byType(_Counter)).count.value = 5;
    await tester.pump();
    expect(find.text('0'), findsOneWidget, reason: 'the app rebuilds itself');

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(controller()));
    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('extra is a value in a reserved bucket', (tester) async {
    final first = controller();
    // ignore: deprecated_member_use_from_same_package
    first.extra = {'projection': 'tabbed'};
    await tester.pump();
    // ignore: deprecated_member_use_from_same_package
    expect(controller().extra, {'projection': 'tabbed'});
  });
}
