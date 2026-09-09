import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reef/features/hibernation/_interfaces/hibernation_store.dart';
import 'package:reef/features/page_identity/_implementations/buffer_id.dart';
import 'package:reef/features/workspace/_implementations/split_tree.dart';
import 'package:reef/features/workspace/_implementations/split_tree_controller.dart';
import 'package:reef_auto_route/reef_auto_route.dart';

void main() {
  group('workspaceControllerProvider', () {
    test('keyed by tabId — two tabs get independent controllers', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final a = container.read(workspaceControllerProvider('a'));
      final b = container.read(workspaceControllerProvider('b'));
      a.open(BufferId.manual('task-edit:1'));

      expect(b.$root.value, isNull);
      expect(a.$root.value, isA<LeafSplitNode>());
    });

    test('restores the hibernated tree for the tab', () {
      final store = InMemoryHibernationStore();
      final seeded = SplitTreeController();
      seeded.open(BufferId.manual('task-edit:1'));
      store.save(
        BufferId.manual('workspace:main'),
        seeded.toJson()!,
      );
      seeded.dispose();

      final container =
          ProviderContainer(overrides: [hibernationStoreProvider.overrideWithValue(store)]);
      addTearDown(container.dispose);

      final controller = container.read(workspaceControllerProvider('main'));
      final root = controller.$root.value;
      expect(root, isA<LeafSplitNode>());
      expect((root as LeafSplitNode).bufferId.id, 'task-edit:1');
      expect(controller.$focused.value?.id, 'task-edit:1');
    });

    test('hibernates the tree on dispose', () async {
      final store = InMemoryHibernationStore();
      final container =
          ProviderContainer(overrides: [hibernationStoreProvider.overrideWithValue(store)]);
      addTearDown(container.dispose);

      container
          .read(workspaceControllerProvider('main'))
          .open(BufferId.manual('task-edit:1'));

      await Future<void>.delayed(Duration.zero); // autoDispose is scheduled
      final json = store.load(BufferId.manual('workspace:main'));
      expect(json, isNotNull);
      expect(SplitTreeController.fromJson(json).$root.value,
          isA<LeafSplitNode>());
    });

    test('disposing an empty workspace deletes the hibernation record',
        () async {
      final store = InMemoryHibernationStore();
      store.save(BufferId.manual('workspace:main'), {
        'root': {'kind': 'leaf', 'bufferId': 'task-edit:1'},
        'focused': 'task-edit:1',
      });
      final container =
          ProviderContainer(overrides: [hibernationStoreProvider.overrideWithValue(store)]);
      addTearDown(container.dispose);

      container.read(workspaceControllerProvider('main'));
      // Empty tree → closeFocused until root is null.
      final controller = container.read(workspaceControllerProvider('main'));
      controller.closeFocused();

      await Future<void>.delayed(Duration.zero);
      expect(store.load(BufferId.manual('workspace:main')), isNull);
    });
  });
}
