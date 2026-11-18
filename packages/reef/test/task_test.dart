import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reef/features/operation/_implementations/operation.dart';
import 'package:reef/features/view_model/_implementations/view_model.dart';
import 'package:reef_fp/async.dart';

class _CounterViewModel extends ViewModel<int> {
  _CounterViewModel() : super(0);

  late final load = task<List<String>>();
}

void main() {
  group('Task', () {
    test('starts idle', () {
      final task = Task<List<String>>();
      expect(task.state, const Idle<List<String>>());
      expect(task.isPending, isFalse);
      task.dispose();
    });

    test('run transitions Pending → Ready with a non-Result value', () async {
      final task = Task<List<String>>();
      final gate = Completer<List<String>>();
      final states = <Async<List<String>>>[];
      task.$state.addListener(() => states.add(task.state));

      final future = task.run(() => gate.future);
      expect(task.isPending, isTrue);
      gate.complete(['a', 'b']);
      await future;

      expect(states, hasLength(2));
      expect(states.first, const Pending<List<String>>());
      expect(task.state, isA<Ready<List<String>>>().having((r) => r.value, 'value', ['a', 'b']));
      task.dispose();
    });

    test('reset returns to idle', () async {
      final task = Task<int>();
      await task.run(() async => 1);
      task.reset();
      expect(task.state, const Idle<int>());
      task.dispose();
    });

    test('viewmodel.task registers a task disposed with the viewmodel', () async {
      final vm = _CounterViewModel();
      await vm.load.run(() async => ['x']);
      expect(vm.load.state, isA<Ready<List<String>>>());
      vm.dispose();
      expect(() => vm.load.$state.addListener(() {}), throwsA(isA<Error>()));
    });

    testWidgets('a builder renders each state of a task', (tester) async {
      final task = Task<int>();
      addTearDown(task.dispose);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ValueListenableBuilder<Async<int>>(
            valueListenable: task.$state,
            builder: (context, state, _) => Text(switch (state) {
              Idle() => 'idle',
              Pending() => 'pending',
              Ready(:final value) => 'ready $value',
            }),
          ),
        ),
      );
      expect(find.text('idle'), findsOneWidget);

      final gate = Completer<int>();
      final run = task.run(() => gate.future);
      await tester.pump();
      expect(find.text('pending'), findsOneWidget);

      gate.complete(7);
      await run;
      await tester.pump();
      expect(find.text('ready 7'), findsOneWidget);
    });
  });
}
