import 'package:flutter/foundation.dart';

/// Disposable callback registry for non-provider resources that must die with
/// a buffer (§4.4): subscriptions to global listenables, timers, etc.
///
/// Providers and viewmodel-owned objects do not need this — riverpod
/// (`ref.onDispose`) and the viewmodel's `registerDisposal` already cover
/// them. The scope covers everything else whose lifetime should be the
/// buffer's.
class ReefScope {
  final Set<VoidCallback> _onDisposeCallbacks = {};

  /// Registers [callback] to run when the scope is disposed.
  void registerOnDispose(VoidCallback callback) => _onDisposeCallbacks.add(callback);

  /// Removes a previously registered [callback].
  void unregisterOnDispose(VoidCallback callback) => _onDisposeCallbacks.remove(callback);

  /// Runs every registered callback once and clears the registry.
  ///
  /// Iterates over a copy so callbacks may unregister (even themselves) while
  /// disposal is running.
  void dispose() {
    for (final callback in List<VoidCallback>.of(_onDisposeCallbacks)) {
      callback();
    }
    _onDisposeCallbacks.clear();
  }
}
