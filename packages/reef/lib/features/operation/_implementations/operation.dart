import 'package:flutter/foundation.dart';
import 'package:reef_fp/async.dart';
import 'package:reef_fp/result.dart';

/// Owns the async/error state of a non-field operation (save, submit, fetch...).
///
/// The state surface is `ValueListenable<Async<Result<E, T>>>` — consumed with
/// the standard three-way builder: [Idle] → placeholder, [Pending] → loading,
/// [Ready] → render the [Result].
///
/// - Async path: [run] — `Idle`/`Ready` → `Pending` → `Ready(Result)`.
/// - Sync path (model edits): [fail] on rejection, [reset] on success — sync
///   operations carry failures only; the published model is the success signal.
class Operation<T, E> {
  final ValueNotifier<Async<Result<E, T>>> _state = ValueNotifier(const Idle());

  /// Reactive state of the operation.
  ValueListenable<Async<Result<E, T>>> get $state => _state;

  /// Current state value.
  Async<Result<E, T>> get state => _state.value;

  /// True while a [run] is in flight.
  bool get isPending => _state.value is Pending<Result<E, T>>;

  /// Runs [action], transitioning `Pending` → `Ready(Result)`.
  Future<void> run(Future<Result<E, T>> Function() action) async {
    _state.value = const Pending();
    _state.value = Ready(await action());
  }

  /// Returns to [Idle] — never ran / success acknowledged.
  void reset() => _state.value = const Idle();

  /// Surfaces a synchronous failure as `Ready(Err(error))`.
  void fail(E error) => _state.value = Ready(Err(error));

  /// Releases the state notifier.
  void dispose() => _state.dispose();
}
