import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:formularium/features/localization/localizable_interface.dart';
import 'package:reef/features/builders/_implementations/async_result_builders.dart';
import 'package:reef_fp/async.dart';
import 'package:reef_fp/result.dart';

sealed class FakeError implements Exception {
  const FakeError();
}

final class Boom extends FakeError {
  const Boom();

  @override
  String toString() => 'boom';
}

Widget _host(Widget child) => WidgetsApp(
      color: const Color(0xFF00695C),
      builder: (_, _) => child,
    );

void main() {
  group('AsyncBuilder', () {
    testWidgets('idle and pending render the sample layout', (tester) async {
      await tester.pumpWidget(_host(AsyncBuilder<int>(
        value: const Async<int>.idle(),
        sample: 0,
        builder: (_, v) => Text('value: $v'),
      )));
      expect(find.text('value: 0'), findsOneWidget);

      await tester.pumpWidget(_host(AsyncBuilder<int>(
        value: const Async<int>.pending(),
        sample: 0,
        builder: (_, v) => Text('value: $v'),
      )));
      expect(find.text('value: 0'), findsOneWidget);
    });

    testWidgets('ready renders the real value', (tester) async {
      await tester.pumpWidget(_host(AsyncBuilder<int>(
        value: const Async<int>.ready(42),
        sample: 0,
        builder: (_, v) => Text('value: $v'),
      )));
      expect(find.text('value: 42'), findsOneWidget);
    });

    testWidgets('pending slot overrides the sample layout', (tester) async {
      await tester.pumpWidget(_host(AsyncBuilder<int>(
        value: const Async<int>.pending(),
        sample: 0,
        pending: (_) => const Text('loading…'),
        builder: (_, v) => Text('value: $v'),
      )));
      expect(find.text('loading…'), findsOneWidget);
    });
  });

  group('ResultBuilder', () {
    testWidgets('Ok renders the builder', (tester) async {
      await tester.pumpWidget(_host(ResultBuilder<FakeError, int>(
        value: const Ok<FakeError, int>(7),
        builder: (_, v) => Text('ok: $v'),
      )));
      expect(find.text('ok: 7'), findsOneWidget);
    });

    testWidgets('Err renders the custom error builder when given',
        (tester) async {
      await tester.pumpWidget(_host(ResultBuilder<FakeError, int>(
        value: const Err<FakeError, int>(Boom()),
        errorBuilder: (_, e) => Text('custom: $e'),
        builder: (_, v) => Text('ok: $v'),
      )));
      expect(find.text('custom: boom'), findsOneWidget);
    });

    testWidgets('Err renders a localized default error otherwise',
        (tester) async {
      await tester.pumpWidget(_host(ResultBuilder<BoomLocalizable, int>(
        value: const Err<BoomLocalizable, int>(BoomLocalizable()),
        builder: (_, v) => Text('ok: $v'),
      )));
      expect(find.text('boom (localized)'), findsOneWidget);
    });
  });

  group('AsyncResultBuilder', () {
    testWidgets('idle renders the sample, Ready(Ok) the value', (tester) async {
      await tester.pumpWidget(_host(AsyncResultBuilder<FakeError, int>(
        value: const Async<Result<FakeError, int>>.idle(),
        sample: 0,
        builder: (_, v) => Text('value: $v'),
      )));
      expect(find.text('value: 0'), findsOneWidget);

      await tester.pumpWidget(_host(AsyncResultBuilder<FakeError, int>(
        value: const Async<Result<FakeError, int>>.ready(Ok(3)),
        sample: 0,
        builder: (_, v) => Text('value: $v'),
      )));
      expect(find.text('value: 3'), findsOneWidget);
    });

    testWidgets('Ready(Err) renders the error path', (tester) async {
      await tester.pumpWidget(_host(AsyncResultBuilder<FakeError, int>(
        value: const Async<Result<FakeError, int>>.ready(Err(Boom())),
        sample: 0,
        errorBuilder: (_, e) => Text('custom: $e'),
        builder: (_, v) => Text('value: $v'),
      )));
      expect(find.text('custom: boom'), findsOneWidget);
    });
  });
}

final class BoomLocalizable implements Exception, ILocalizable {
  const BoomLocalizable();

  @override
  String localize() => 'boom (localized)';
}
