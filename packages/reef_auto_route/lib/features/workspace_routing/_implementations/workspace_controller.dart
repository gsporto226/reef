import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reef/features/hibernation/_interfaces/hibernation_store.dart';
import 'package:reef/features/page_identity/_implementations/buffer_id.dart';
import 'package:reef/features/workspace/_implementations/split_tree_controller.dart';

/// The workspace controller of one tab — app state, not widget state. The
/// router is a projection: route replaces reattach to the same controller
/// and pane state survives (blueprint §10.3).
///
/// The tree hibernates through the app's [HibernationStore] under the
/// reserved `workspace:` key when the tab closes; an empty workspace deletes
/// the record. Reopening `/w/<tabId>` restores the layout.
final workspaceControllerProvider =
    Provider.autoDispose.family<SplitTreeController, String>((ref, tabId) {
  final key = BufferId.manual('workspace:$tabId');
  final store = ref.watch(hibernationStoreProvider);
  final controller = SplitTreeController.fromJson(store.load(key));
  ref.onDispose(() {
    final json = controller.toJson();
    if (json == null) {
      store.delete(key);
    } else {
      store.save(key, json);
    }
    controller.dispose();
  });
  return controller;
});
