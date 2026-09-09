import 'package:meta/meta.dart';

/// Represents the presence or absence of a value of type [T].
///
/// Distinguishes a missing value from a present value that is null.
sealed class Optional<T> {
  const Optional();

  /// The value [T] when this is a [Some], or [or] otherwise.
  T getOr(T or) => switch (this) {
    Some(:final value) => value,
    Empty() => or,
  };

  /// The value [T] when this is a [Some], or null when [Empty].
  T? getOrNull() => switch (this) {
    Some<T>(:final value) => value,
    Empty() => null,
  };

  /// Maps [T] to [R] when this is a [Some]; keeps [Empty].
  Optional<R> mapSome<R>(R Function(T) mapper) => switch (this) {
    Some(:final value) => Some(mapper(value)),
    Empty() => const Empty(),
  };

  /// True when this is a [Some].
  bool get isSome => switch (this) {
    Some() => true,
    Empty() => false,
  };
}

/// An [Optional] that holds a value.
@immutable
class Some<T> extends Optional<T> {
  /// Creates a [Some] holding [value].
  const Some(this.value);

  /// The stored [T] value.
  final T value;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Some && other.value == value;
  }

  @override
  int get hashCode => Object.hash('Some', value);
}

/// An [Optional] with no value.
@immutable
class Empty extends Optional<Never> {
  /// Creates an [Empty].
  const Empty();

  @override
  bool operator ==(Object other) => other is Empty;

  @override
  int get hashCode => Object.hash('Empty', 0);
}

/// Global empty optional.
const empty = Empty();
