import 'dart:async';

import 'package:meta/meta.dart';

/// A value that is either [L] or [R].
///
/// Models a result that is either a failure ([Err]) or a success ([Ok]).
sealed class Result<L, R> {
  const Result();

  /// True when this is an [Err], meaning failure.
  bool get isErr => this is Err<L, R>;

  /// True when this is an [Ok], meaning success.
  bool get isOk => this is Ok<L, R>;

  /// Runs [errFn] on an [Err] value, or [okFn] on an [Ok] value.
  T fold<T>(T Function(L) errFn, T Function(R) okFn) {
    if (this is Err<L, R>) {
      return errFn((this as Err<L, R>).value);
    }
    return okFn((this as Ok<L, R>).value);
  }

  /// The [Ok] value, or [fallback] when this is an [Err].
  R getOrElse(R fallback) {
    if (this is Ok<L, R>) {
      return (this as Ok<L, R>).value;
    }
    return fallback;
  }

  /// The [Ok] value, or null when this is an [Err].
  R? getOrNull() {
    if (this is Ok<L, R>) {
      return (this as Ok<L, R>).value;
    }
    return null;
  }

  /// The [Err] value, or null when this is an [Ok].
  L? getErrOrNull() {
    if (this is Err<L, R>) {
      return (this as Err<L, R>).value;
    }
    return null;
  }

  /// True when both instances hold the same value.
  bool equals(Result<L, R> other) {
    final self = this;
    if (self is Err<L, R> && other is Err<L, R>) {
      return self.value == other.value;
    }
    if (self is Ok<L, R> && other is Ok<L, R>) {
      return self.value == other.value;
    }
    return false;
  }

  /// Maps this [Result<L, R>] to a [Result<NewErr, NewOk>].
  Result<NewErr, NewOk> map<NewOk, NewErr>(
    NewErr Function(L) mapErr,
    NewOk Function(R) mapOk,
  ) {
    switch (this) {
      case Err(:final value):
        return Err(mapErr(value));
      case Ok(:final value):
        return Ok(mapOk(value));
    }
  }

  /// Maps the [Ok] value with [mapper]; leaves [Err] untouched.
  Result<L, T> mapOk<T>(T Function(R) mapper) {
    switch (this) {
      case Err(:final value):
        return Err(value);
      case Ok(:final value):
        return Ok(mapper(value));
    }
  }

  /// Maps the [Err] value with [mapper]; leaves [Ok] untouched.
  Result<T, R> mapErr<T>(T Function(L) mapper) => switch (this) {
    Err(:final value) => Err(mapper(value)),
    Ok(:final value) => Ok(value),
  };

  /// Maps the [Ok] value with the async [mapper]; leaves [Err] untouched.
  FutureOr<Result<L, T>> mapOkAsync<T>(FutureOr<T> Function(R) mapper) async {
    switch (this) {
      case Err(:final value):
        return Err(value);
      case Ok(:final value):
        return Ok(await mapper(value));
    }
  }

  /// Runs [mapper] on the [Ok] value and returns the resulting result.
  Result<L, T> flatMapOk<T>(
    Result<L, T> Function(R) mapper,
  ) {
    switch (this) {
      case Err(:final value):
        return Err<L, T>(value);
      case Ok(:final value):
        return mapper(value);
    }
  }

  /// Runs the async [mapper] on the [Ok] value and returns the resulting result.
  FutureOr<Result<L, T>> flatMapOkAsync<T>(
    FutureOr<Result<L, T>> Function(R) mapper,
  ) async {
    switch (this) {
      case Err(:final value):
        return Err(value);
      case Ok(:final value):
        return await mapper(value);
    }
  }

  /// Maps [Err] and [Ok] values to a single type.
  MappedType mapInto<MappedType>(
    MappedType Function(L) errMapper,
    MappedType Function(R) okMapper,
  ) {
    switch (this) {
      case Err(:final value):
        return errMapper(value);
      case Ok(:final value):
        return okMapper(value);
    }
  }

  /// Maps [Err] and [Ok] values to a single type with async mappers.
  FutureOr<MappedType> mapIntoAsync<MappedType>(
    FutureOr<MappedType> Function(L) errMapper,
    FutureOr<MappedType> Function(R) okMapper,
  ) async => switch (this) {
    Err(:final value) => errMapper(value),
    Ok(:final value) => okMapper(value),
  };

  /// Runs [action] on the [Ok] value; does nothing on an [Err].
  void ifOk(void Function(R) action) {
    if (this is Ok<L, R>) {
      action((this as Ok<L, R>).value);
    }
  }

  /// Runs [action] on the [Err] value; does nothing on an [Ok].
  void ifErr(void Function(L) action) {
    if (this is Err<L, R>) {
      action((this as Err<L, R>).value);
    }
  }

  /// Runs [err] on an [Err] value, or [ok] on an [Ok] value.
  void tap(void Function(L) err, void Function(R) ok) {
    switch (this) {
      case Err(:final value):
        err(value);
      case Ok(:final value):
        ok(value);
    }
  }

  /// Runs [tap] on the [Ok] value.
  void tapOk(void Function(R) tap) {
    if (this is Ok<L, R>) {
      tap((this as Ok<L, R>).value);
    }
  }
}

/// Holds the failure value of type [L].
@immutable
class Err<L, R> extends Result<L, R> {
  /// Creates an [Err] with a value of type [L].
  const Err(this._value);

  final L _value;

  /// The stored [L] value.
  L get value => _value;

  @override
  int get hashCode => _value.hashCode;

  @override
  bool operator ==(Object other) => identical(this, other) || (other is Err && other._value == _value);
}

/// Holds the success value of type [R].
@immutable
class Ok<L, R> extends Result<L, R> {
  /// Creates an [Ok] with a value of type [R].
  const Ok(this._value);

  final R _value;

  /// The stored [R] value.
  R get value => _value;

  @override
  int get hashCode => _value.hashCode;

  @override
  bool operator ==(Object other) => identical(this, other) || (other is Ok && other._value == _value);
}
