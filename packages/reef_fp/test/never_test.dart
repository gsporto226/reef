import 'package:reef_fp/never.dart';
import 'package:test/test.dart';

void main() {
  group('never', () {
    test('throws AssertionError', () {
      expect(never, throwsA(isA<AssertionError>()));
    });

    test('throws AssertionError with message', () {
      expect(() => never('boom'), throwsA(isA<AssertionError>()));
    });

    test('never1 throws AssertionError', () {
      expect(() => never1(1), throwsA(isA<AssertionError>()));
    });
  });
}
