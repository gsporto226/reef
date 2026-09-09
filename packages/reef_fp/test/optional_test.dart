import 'package:reef_fp/optional.dart';
import 'package:test/test.dart';

void main() {
  group('Optional', () {
    const some = Some(1);
    const Optional<int> emptyValue = Empty();

    group('constructors', () {
      test('Some', () {
        expect(some.value, 1);
        expect(some.isSome, isTrue);
      });

      test('Empty', () {
        expect(emptyValue.isSome, isFalse);
      });
    });

    test('getOr', () {
      expect(some.getOr(2), 1);
    });

    test('getOrNull', () {
      expect(some.getOrNull(), 1);
      expect(emptyValue.getOrNull(), isNull);
    });

    test('mapSome', () {
      expect(some.mapSome((v) => v + 1), const Some(2));
      expect(emptyValue.mapSome((v) => v + 1), const Empty());
    });

    test('==', () {
      expect(const Some(1) == const Some(1), isTrue);
      expect(const Some(1) == const Some(2), isFalse);
      expect(const Empty() == const Empty(), isTrue);
      expect(emptyValue == const Some(1), isFalse);
    });

    test('global empty constant', () {
      expect(empty, const Empty());
    });
  });
}
