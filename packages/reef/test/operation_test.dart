import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reef/features/operation/_implementations/operation.dart';
import 'package:reef_fp/async.dart';
import 'package:reef_fp/result.dart';
import 'package:reef_fp/unit.dart';

void main() {
  group('Operation', () {
    test('starts idle', () {
      final op = Operation<int, String>();
      expect(op.state, const Idle<Result<String, int>>());
      expect(op.isPending, isFalse);
      op.dispose();
    });

    test('run transitions Pending → Ready(Ok)', () async {
      final op = Operation<int, String>();
      final gate = Completer<Result<String, int>>();

      final future = op.run(() => gate.future);
      expect(op.state, const Pending<Result<String, int>>());
      expect(op.isPending, isTrue);

      gate.complete(const Ok(42));
      await future;

      expect(op.state, const Ready<Result<String, int>>(Ok(42)));
      expect(op.isPending, isFalse);
      op.dispose();
    });

    test('run transitions Pending → Ready(Err)', () async {
      final op = Operation<int, String>();
      await op.run(() async => const Err('boom'));
      expect(op.state, const Ready<Result<String, int>>(Err('boom')));
      op.dispose();
    });

    test('reset returns to idle', () async {
      final op = Operation<int, String>();
      await op.run(() async => const Ok(1));
      op.reset();
      expect(op.state, const Idle<Result<String, int>>());
      op.dispose();
    });

    test('fail surfaces a synchronous error as Ready(Err)', () {
      final op = Operation<Unit, String>();
      op.fail('bad input');
      expect(op.state, const Ready<Result<String, Unit>>(Err('bad input')));
      op.dispose();
    });

    test('listeners observe every transition', () async {
      final op = Operation<int, String>();
      final states = <Async<Result<String, int>>>[];
      op.$state.addListener(() => states.add(op.state));

      await op.run(() async => const Ok(1));
      expect(states, [
        const Pending<Result<String, int>>(),
        const Ready<Result<String, int>>(Ok(1)),
      ]);
      op.dispose();
    });
  });
}
