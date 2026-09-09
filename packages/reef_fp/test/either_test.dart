import 'package:mocktail/mocktail.dart';
import 'package:reef_fp/either.dart';
import 'package:test/test.dart';

void main() {
  group('Either', () {
    group('constructors', () {
      test('Left', () {
        const left = Left<bool, dynamic>(true);
        expect(left, isNotNull);
        expect(left.value, isTrue);
      });

      test('Right', () {
        const right = Right<dynamic, bool>(true);
        expect(right, isNotNull);
        expect(right.value, isTrue);
      });
    });

    const Either<bool, int> left = Left(true);
    const Either<bool, int> right = Right(1);

    test('isLeft', () {
      expect(left.isLeft, isTrue);
    });

    test('isRight', () {
      expect(right.isRight, isTrue);
    });

    test('getOrElse', () {
      expect(right.getOrElse(2), equals(1));
      expect(left.getOrElse(2), equals(2));
    });

    test('fold', () {
      expect(right.fold((b) => b, (_) => null), isNull);
      expect(left.fold((b) => b, (_) => null), isTrue);
    });

    test('getOrNull', () {
      expect(right.getOrNull(), equals(1));
      expect(left.getOrNull(), isNull);
    });

    test('getLeftOrNull', () {
      expect(right.getLeftOrNull(), isNull);
      expect(left.getLeftOrNull(), isTrue);
    });

    test('equals', () {
      expect(right.equals(left), isFalse);
      expect(left.equals(right), isFalse);
      expect(left.equals(left), isTrue);
      expect(right.equals(right), isTrue);
    });

    test('map', () {
      expect(left.map((_) => 1, (_) => 2).equals(const Left(1)), true);
      expect(right.map((_) => 1, (_) => 2).equals(const Right(2)), true);
    });

    test('mapRight', () {
      expect((right.mapRight((_) => 2) as Right<bool, int>).value, equals(2));
      expect((left.mapRight((_) => 2) as Left<bool, int>).value, isTrue);
    });

    test('mapInto', () {
      expect(right.mapInto((_) => 0, (_) => 1), equals(1));
      expect(left.mapInto((_) => 0, (_) => 1), equals(0));
    });

    test('mapIntoAsync', () async {
      expect(
        await right.mapIntoAsync((_) async => 0, (_) async => 1),
        equals(1),
      );
      expect(
        await left.mapIntoAsync((_) async => 0, (_) async => 1),
        equals(0),
      );
    });

    test('ifLeft', () {
      final callbackMock = CallbackMock();
      right.ifLeft((_) => callbackMock.callback());
      verifyNever(callbackMock.callback);
      left.ifLeft((_) => callbackMock.callback());
      verify(callbackMock.callback).called(1);
    });

    test('ifRight', () {
      final callbackMock = CallbackMock();
      left.ifRight((_) => callbackMock.callback());
      verifyNever(callbackMock.callback);
      right.ifRight((_) => callbackMock.callback());
      verify(callbackMock.callback).called(1);
    });
  });
}

class CallbackMock extends Mock {
  void callback();
}
