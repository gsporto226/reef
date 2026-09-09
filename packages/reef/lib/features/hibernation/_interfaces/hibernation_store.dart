import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reef/features/page_identity/_implementations/buffer_id.dart';

/// Where hibernated buffer JSON lives (§10.2). The default implementation is
/// in-memory; apps override [hibernationStoreProvider] with a disk-backed
/// one. The interface is synchronous — async stores must preload before the
/// buffer's provider runs (the seed is read synchronously in provider bodies).
abstract interface class HibernationStore {
  /// The hibernated JSON for [bufferId], or null.
  Map<String, dynamic>? load(BufferId bufferId);

  /// Persists [json] under [bufferId].
  void save(BufferId bufferId, Map<String, dynamic> json);

  /// Drops the hibernated state for [bufferId] (the `:bd` equivalent).
  void delete(BufferId bufferId);
}

/// In-memory [HibernationStore] — the default and the test double.
class InMemoryHibernationStore implements HibernationStore {
  final Map<BufferId, Map<String, dynamic>> _json = {};

  @override
  Map<String, dynamic>? load(BufferId bufferId) => _json[bufferId];

  @override
  void save(BufferId bufferId, Map<String, dynamic> json) =>
      _json[bufferId] = json;

  @override
  void delete(BufferId bufferId) => _json.remove(bufferId);
}

/// The app's hibernation store — keepAlive, overridable at the
/// [ProviderScope].
final hibernationStoreProvider = Provider<HibernationStore>(
  (ref) => InMemoryHibernationStore(),
);
