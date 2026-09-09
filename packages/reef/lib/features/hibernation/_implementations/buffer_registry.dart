import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reef/features/page_identity/_implementations/buffer_id.dart';

/// The `:ls` of reef (§10.1): a listenable registry of alive buffers, in
/// creation order, with the pinned set (§10.2 — pinned buffers stay
/// materialized until explicitly closed; the flag is advisory here — keeping
/// a pinned buffer alive is done app-side with a keepAlive anchor provider).
class BufferRegistry {
  final List<BufferId> _alive = [];
  final Set<BufferId> _pinned = {};
  final ValueNotifier<List<BufferId>> _notifier = ValueNotifier(const []);

  /// Alive buffer ids, in creation order.
  ValueListenable<List<BufferId>> get $alive => _notifier;

  /// Marks [bufferId] materialized.
  void register(BufferId bufferId) {
    if (_alive.any((id) => id == bufferId)) return;
    _alive.add(bufferId);
    _emit();
  }

  /// Marks [bufferId] disposed.
  void unregister(BufferId bufferId) {
    _alive.removeWhere((id) => id == bufferId);
    _emit();
  }

  /// Pins [bufferId] (stays out of eviction; shown pinned in the registry).
  void pin(BufferId bufferId) {
    _pinned.add(bufferId);
    _emit();
  }

  /// Unpins [bufferId].
  void unpin(BufferId bufferId) => _pinned.remove(bufferId);

  /// Whether [bufferId] is pinned.
  bool isPinned(BufferId bufferId) => _pinned.contains(bufferId);

  void _emit() => _notifier.value = List.unmodifiable(_alive);

  /// Releases the notifier (registry is app-lifetime).
  void dispose() => _notifier.dispose();
}

/// The app's buffer registry — keepAlive.
final bufferRegistryProvider = Provider<BufferRegistry>((ref) {
  final registry = BufferRegistry();
  ref.onDispose(registry.dispose);
  return registry;
});
