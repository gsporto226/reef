import 'package:flutter/foundation.dart';
import 'package:reef_fp/async.dart';
import 'package:reef_fp/result.dart';

/// Owns the async state of an action whose value has any shape [V].
///
/// The state surface is `ValueListenable<Async<V>>`: [Idle] → placeholder,
/// [Pending] → loading, [Ready] → render the value.
class Task<V> {
  final ValueNotifier<Async<V>> _state = ValueNotifier(const Idle());

  /// Reactive state of the task.
  ValueListenable<Async<V>> get $state => _state;

  /// Current state value.
  Async<V> get state => _state.value;

  /// True while a [run] is in flight.
  bool get isPending => _state.value is Pending<V>;

  /// Runs [action], transitioning `Pending` → `Ready(value)`.
  Future<void> run(Future<V> Function() action) async {
    _state.value = const Pending();
    _state.value = Ready(await action());
  }

  /// Returns to [Idle] — never ran / success acknowledged.
  void reset() => _state.value = const Idle();

  /// Releases the state notifier.
  void dispose() => _state.dispose();
}

/// A [Task] whose value is a `Result<E, T>`: the async/error state of a
/// non-field operation (save, submit, fetch...).
///
/// - Async path: [run] — `Idle`/`Ready` → `Pending` → `Ready(Result)`.
/// - Sync path (model edits): [fail] on rejection, [reset] on success — sync
///   operations carry failures only; the published model is the success signal.
class Operation<T, E> extends Task<Result<E, T>> {
  /// Surfaces a synchronous failure as `Ready(Err(error))`.
  void fail(E error) => _state.value = Ready(Err(error));
}
