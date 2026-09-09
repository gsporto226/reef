import 'dart:async';

import 'package:meta/meta.dart';
import 'package:reef_fp/identity.dart';

/// A value that is either [L] or [R].
///
/// Models a result that is either a failure ([Left]) or a success ([Right]).
sealed class Either<L, R> {
  const Either();

  /// True when this is a [Left], meaning failure.
  bool get isLeft => this is Left<L, R>;

  /// True when this is a [Right], meaning success.
  bool get isRight => this is Right<L, R>;

  /// Runs [leftFn] on a [Left] value, or [rightFn] on a [Right] value.
  T fold<T>(T Function(L) leftFn, T Function(R) rightFn) {
    if (this is Left<L, R>) {
      return leftFn((this as Left<L, R>).value);
    }
    return rightFn((this as Right<L, R>).value);
  }

  /// The [Right] value, or [fallback] when this is a [Left].
  R getOrElse(R fallback) {
    if (this is Right<L, R>) {
      return (this as Right<L, R>).value;
    }
    return fallback;
  }

  /// The [Right] value, or null when this is a [Left].
  R? getOrNull() {
    if (this is Right<L, R>) {
      return (this as Right<L, R>).value;
    }
    return null;
  }

  /// The [Left] value, or null when this is a [Right].
  L? getLeftOrNull() {
    if (this is Left<L, R>) {
      return (this as Left<L, R>).value;
    }
    return null;
  }

  /// True when both instances hold the same value.
  bool equals(Either<L, R> other) {
    final self = this;
    if (self is Left<L, R> && other is Left<L, R>) {
      return self.value == other.value;
    }
    if (self is Right<L, R> && other is Right<L, R>) {
      return self.value == other.value;
    }
    return false;
  }

  /// Maps this [Either<L, R>] to an [Either<NewLeft, NewRight>].
  Either<NewLeft, NewRight> map<NewRight, NewLeft>(
    NewLeft Function(L) mapLeft,
    NewRight Function(R) mapRight,
  ) {
    switch (this) {
      case Left(:final value):
        return Left(mapLeft(value));
      case Right(:final value):
        return Right(mapRight(value));
    }
  }

  /// Maps the [Right] value with [mapper]; leaves [Left] untouched.
  Either<L, T> mapRight<T>(T Function(R) mapper) => map(identity, mapper);

  /// Maps the [Left] value with [mapper]; leaves [Right] untouched.
  Either<T, R> mapLeft<T>(T Function(L) mapper) => map(mapper, identity);

  /// Maps the [Right] value with the async [mapper]; leaves [Left] untouched.
  Future<Either<L, T>> mapRightAsync<T>(FutureOr<T> Function(R) mapper) async {
    switch (this) {
      case Left(:final value):
        return Left(value);
      case Right(:final value):
        return Right(await mapper(value));
    }
  }

  /// Runs the async [mapper] on the [Right] value and returns the resulting either.
  FutureOr<Either<L, T>> flatMapRightAsync<T>(
    FutureOr<Either<L, T>> Function(R) mapper,
  ) async {
    switch (this) {
      case Left(:final value):
        return Left(value);
      case Right(:final value):
        return await mapper(value);
    }
  }

  /// Runs [mapper] on the [Right] value and returns the resulting either.
  Either<L, T> flatMapRight<T>(Either<L, T> Function(R) mapper) {
    switch (this) {
      case Left(:final value):
        return Left(value);
      case Right(:final value):
        return mapper(value);
    }
  }

  /// Maps [Left] and [Right] values to a single type.
  MappedType mapInto<MappedType>(
    MappedType Function(L) leftMapper,
    MappedType Function(R) rightMapper,
  ) {
    switch (this) {
      case Left(:final value):
        return leftMapper(value);
      case Right(:final value):
        return rightMapper(value);
    }
  }

  /// Maps [Left] and [Right] values to a single type with async mappers.
  FutureOr<MappedType> mapIntoAsync<MappedType>(
    FutureOr<MappedType> Function(L) leftMapper,
    FutureOr<MappedType> Function(R) rightMapper,
  ) async => switch (this) {
    Left(:final value) => leftMapper(value),
    Right(:final value) => rightMapper(value),
  };

  /// Runs [action] on the [Right] value; does nothing on a [Left].
  void ifRight(void Function(R) action) {
    if (this case Right(:final value)) {
      action(value);
    }
  }

  /// Runs [action] on the [Left] value; does nothing on a [Right].
  void ifLeft(void Function(L) action) {
    if (this case Left(:final value)) {
      action(value);
    }
  }

  /// Runs [left] on a [Left] value, or [right] on a [Right] value.
  void tap(void Function(L) left, void Function(R) right) {
    switch (this) {
      case Left(:final value):
        left(value);
      case Right(:final value):
        right(value);
    }
  }

  /// Runs [tap] on the [Right] value.
  void tapRight(void Function(R) tap) {
    if (this is Right<L, R>) {
      tap((this as Right<L, R>).value);
    }
  }
}

/// Holds the failure value of type [L].
@immutable
class Left<L, R> extends Either<L, R> {
  /// Creates a [Left] with a value of type [L].
  const Left(this._value);

  final L _value;

  /// The stored [L] value.
  L get value => _value;

  @override
  int get hashCode => _value.hashCode;

  @override
  bool operator ==(Object other) => identical(this, other) || (other is Left && other._value == _value);
}

/// Holds the success value of type [R].
@immutable
class Right<L, R> extends Either<L, R> {
  /// Creates a [Right] with a value of type [R].
  const Right(this._value);

  final R _value;

  /// The stored [R] value.
  R get value => _value;

  @override
  int get hashCode => _value.hashCode;

  @override
  bool operator ==(Object other) => identical(this, other) || (other is Right && other._value == _value);
}
