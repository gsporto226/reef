import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reef/features/hibernation/_implementations/buffer_registry.dart';
import 'package:reef/features/hibernation/_implementations/lifecycle.dart';
import 'package:reef/features/hibernation/_interfaces/hibernation_store.dart';
import 'package:reef/features/page_identity/_implementations/buffer_id.dart';
import 'package:riverpod/riverpod.dart' as rp;

void main() {
  group('InMemoryHibernationStore', () {
    test('save/load/delete roundtrip', () {
      final store = InMemoryHibernationStore();
      final id = BufferId.manual('b1');

      expect(store.load(id), isNull);
      store.save(id, {'title': 'Buy milk'});
      expect(store.load(id), {'title': 'Buy milk'});
      store.delete(id);
      expect(store.load(id), isNull);
    });
  });

  group('BufferRegistry', () {
    test('registers in creation order, unregisters, notifies listeners',
        () {
      final registry = BufferRegistry();
      final seen = <List<String>>[];
      registry.$alive.addListener(() =>
          seen.add(registry.$alive.value.map((id) => id.id).toList()));

      final a = BufferId.manual('a');
      final b = BufferId.manual('b');
      registry.register(a);
      registry.register(b);
      registry.register(a); // duplicate is a no-op
      registry.unregister(a);

      expect(seen, [
        ['a'],
        ['a', 'b'],
        ['b'],
      ]);
    });

    test('pin/unpin/isPinned', () {
      final registry = BufferRegistry();
      final id = BufferId.manual('p');

      expect(registry.isPinned(id), isFalse);
      registry.pin(id);
      expect(registry.isPinned(id), isTrue);
      registry.unpin(id);
      expect(registry.isPinned(id), isFalse);
    });
  });

  group('lifecycle helpers', () {
    late ProviderContainer container;
    late InMemoryHibernationStore store;
    late BufferRegistry registry;
    late List<String> disposed;

    final bufferProvider = rp.Provider.autoDispose.family<String, BufferId>(
      (ref, id) {
        trackBuffer(ref, id);
        hibernateOnDispose(ref, id, () => {'state': id.id});
        hibernatedSeed<String>(ref, id, (json) => json['state'] as String);
        ref.onDispose(() => disposed.add(id.id));
        return id.id;
      },
    );

    setUp(() {
      disposed = [];
      store = InMemoryHibernationStore();
      registry = BufferRegistry();
      container = ProviderContainer(overrides: [
        hibernationStoreProvider.overrideWithValue(store),
        bufferRegistryProvider.overrideWithValue(registry),
      ]);
      addTearDown(container.dispose);
    });

    test('provider body: registers, hibernates on dispose, seeds on re-run',
        () async {
      final id = BufferId.manual('task');
      final sub = container.listen(bufferProvider(id), (_, _) {});
      expect(registry.$alive.value.map((e) => e.id), ['task']);

      sub.close();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(disposed, ['task']);
      expect(registry.$alive.value, isEmpty);
      expect(store.load(id), {'state': 'task'});

      // Reopening the same id rematerializes from the hibernated seed — the
      // provider body reads it via hibernatedSeed (captured in `value`).
      final reopened = container.read(bufferProvider(id));
      expect(reopened, 'task');
      expect(registry.$alive.value.map((e) => e.id), ['task']);
    });

    test('the windowing: id is reserved for the layout record', () {
      const reserved = BufferId.manual('windowing:');
      final seeded = rp.Provider.autoDispose(
        (ref) => hibernatedSeed<Object>(ref, reserved, (json) => json),
      );
      final hibernated = rp.Provider.autoDispose(
        (ref) => hibernateOnDispose(ref, reserved, () => {}),
      );
      final refused = throwsA(
        predicate((e) => '$e'.contains('reserved for the layout record')),
      );
      expect(() => container.read(seeded), refused);
      expect(() => container.read(hibernated), refused);
    });
  });
}

