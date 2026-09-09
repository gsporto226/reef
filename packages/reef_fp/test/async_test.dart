import 'package:reef_fp/async.dart';
import 'package:reef_fp/result.dart';
import 'package:test/test.dart';

void main() {
  group('Async variants', () {
    test('factories produce the right variants', () {
      expect(const Async<int>.idle(), isA<Idle<int>>());
      expect(const Async<int>.pending(), isA<Pending<int>>());
      expect(const Async<int>.ready(1), isA<Ready<int>>());
    });

    test('getOrNull returns value only when ready', () {
      expect(const Async<int>.idle().getOrNull(), isNull);
      expect(const Async<int>.pending().getOrNull(), isNull);
      expect(const Async<int>.ready(7).getOrNull(), 7);
    });

    test('predicates', () {
      expect(const Async<int>.idle().isIdle, isTrue);
      expect(const Async<int>.idle().isPending, isFalse);
      expect(const Async<int>.idle().isReady, isFalse);

      expect(const Async<int>.pending().isIdle, isFalse);
      expect(const Async<int>.pending().isPending, isTrue);
      expect(const Async<int>.pending().isReady, isFalse);

      expect(const Async<int>.ready(1).isIdle, isFalse);
      expect(const Async<int>.ready(1).isPending, isFalse);
      expect(const Async<int>.ready(1).isReady, isTrue);
    });
  });

  group('Async equality', () {
    test('same variants with same value are equal', () {
      expect(const Async<int>.idle(), const Async<int>.idle());
      expect(const Async<int>.pending(), const Async<int>.pending());
      expect(const Async<int>.ready(1), const Async<int>.ready(1));
    });

    test('different variants or values are not equal', () {
      expect(const Async<int>.idle(), isNot(const Async<int>.pending()));
      expect(const Async<int>.pending(), isNot(const Async<int>.ready(1)));
      expect(const Async<int>.ready(1), isNot(const Async<int>.ready(2)));
    });
  });

  group('Async map', () {
    test('maps ready values', () {
      expect(const Async<int>.ready(2).map((v) => v * 2), const Async<int>.ready(4));
    });

    test('preserves idle and pending variants', () {
      expect(const Async<int>.idle().map((v) => v * 2), const Async<int>.idle());
      expect(const Async<int>.pending().map((v) => v * 2), const Async<int>.pending());
    });
  });

  group('Async orElse and when', () {
    test('orElse falls back when not ready', () {
      expect(const Async<int>.idle().orElse(9), 9);
      expect(const Async<int>.pending().orElse(9), 9);
      expect(const Async<int>.ready(1).orElse(9), 1);
    });

    test('when is exhaustive', () {
      const values = <Async<int>>[Async<int>.idle(), Async<int>.pending(), Async<int>.ready(3)];
      final out = values
          .map((v) => v.when(idle: () => 'idle', pending: () => 'pending', ready: (v) => 'ready'))
          .toList();
      expect(out, ['idle', 'pending', 'ready']);
    });
  });

  group('Async with Result', () {
    test('carries results as values', () {
      const ok = Async<Result<String, int>>.ready(Ok(1));
      const err = Async<Result<String, int>>.ready(Err('boom'));

      expect(ok.getOrNull()?.getOrNull(), 1);
      expect(err.getOrNull()?.getErrOrNull(), 'boom');
    });
  });
}
