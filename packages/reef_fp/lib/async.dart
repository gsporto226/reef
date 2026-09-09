import 'package:meta/meta.dart';

/// A value that may not be available yet: it can be idle (never started or
/// reset), pending (in flight, no payload yet) or ready (holding a value).
///
/// Replaces the old `Pending<T>`/`NotReady` pair, adding the [Idle] state so
/// "nothing requested yet" and "loading" can be told apart.
sealed class Async<T> {
  /// Creates an idle [Async] — nothing has been requested yet.
  const factory Async.idle() = Idle<T>;

  /// Creates a pending [Async] — work is in flight, no payload yet.
  const factory Async.pending() = Pending<T>;

  /// Creates a ready [Async] holding [value].
  const factory Async.ready(T value) = Ready<T>;

  const Async._();

  /// The value when ready, or null otherwise.
  T? getOrNull() => switch (this) {
    Ready<T>(:final value) => value,
    _ => null,
  };

  /// True when this is a [Ready].
  bool get isReady => this is Ready<T>;

  /// True when this is a [Pending].
  bool get isPending => this is Pending<T>;

  /// True when this is an [Idle].
  bool get isIdle => this is Idle<T>;

  /// Maps a ready value to a new type, keeping the idle/pending variant.
  Async<R> map<R>(R Function(T) mapper) => switch (this) {
    Idle<T>() => Async<R>.idle(),
    Pending<T>() => Async<R>.pending(),
    Ready<T>(:final value) => Async<R>.ready(mapper(value)),
  };

  /// The value inside the async, or [orElse] when idle or pending.
  T orElse(T orElse) => getOrNull() ?? orElse;

  /// Exhaustively maps each variant to a value of type [R].
  R when<R>({
    required R Function() idle,
    required R Function() pending,
    required R Function(T value) ready,
  }) => switch (this) {
    Idle<T>() => idle(),
    Pending<T>() => pending(),
    Ready<T>(:final value) => ready(value),
  };
}

/// Nothing has been requested yet, or the state was reset.
@immutable
class Idle<T> extends Async<T> {
  /// Creates the idle state.
  const Idle() : super._();

  @override
  bool operator ==(Object other) => identical(this, other) || other is Idle;

  @override
  int get hashCode => 0x1d3e;

  @override
  String toString() => 'Idle<$T>()';
}

/// Work is in flight; no payload available yet.
@immutable
class Pending<T> extends Async<T> {
  /// Creates the pending state.
  const Pending() : super._();

  @override
  bool operator ==(Object other) => identical(this, other) || other is Pending;

  @override
  int get hashCode => 0xabf33dc;

  @override
  String toString() => 'Pending<$T>()';
}

/// A value is available.
@immutable
class Ready<T> extends Async<T> {
  /// Creates the ready state holding [value].
  const Ready(this.value) : super._();

  /// The stored value.
  final T value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Ready<T> && other.value == value);

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Ready<$T>($value)';
}
