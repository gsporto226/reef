import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reef/features/hibernation/_implementations/buffer_registry.dart';
import 'package:reef/features/hibernation/_interfaces/hibernation_store.dart';
import 'package:reef/features/page_identity/_implementations/buffer_id.dart';
import 'package:reef/features/windowing/_implementations/windowing_controller.dart';

/// Wires a materialized buffer into the [bufferRegistryProvider] (`:ls`).
/// Call inside the buffer's provider body.
void trackBuffer(Ref ref, BufferId bufferId) {
  final registry = ref.watch(bufferRegistryProvider);
  registry.register(bufferId);
  ref.onDispose(() => registry.unregister(bufferId));
}

/// Auto-hibernates the buffer (§10.2): when the provider disposes (last
/// window closed), [snapshot] is evaluated against the then-current state
/// and persisted into the [hibernationStoreProvider]. Call inside the
/// buffer's provider body.
void hibernateOnDispose(
  Ref ref,
  BufferId bufferId,
  Map<String, dynamic> Function() snapshot,
) {
  assert(
    bufferId != WindowingController.hibernationKey,
    '$bufferId is reserved for the layout record',
  );
  final store = ref.watch(hibernationStoreProvider);
  ref.onDispose(() => store.save(bufferId, snapshot()));
}

/// Restores the hibernated seed for [bufferId], or null when none — feeds
/// the provider's `initial` parameter. Call inside the buffer's provider
/// body.
M? hibernatedSeed<M>(
  Ref ref,
  BufferId bufferId,
  M Function(Map<String, dynamic> json) fromJson,
) {
  assert(
    bufferId != WindowingController.hibernationKey,
    '$bufferId is reserved for the layout record',
  );
  final json = ref.watch(hibernationStoreProvider).load(bufferId);
  return json == null ? null : fromJson(json);
}
