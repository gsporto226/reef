import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reef/features/page_identity/_implementations/buffer_id.dart';
import 'package:reef/features/page_identity/_implementations/reef_scope.dart';
import 'package:reef/features/page_identity/_providers/reef_scope_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReefScope', () {
    test('dispose runs every registered callback once', () {
      final scope = ReefScope();
      var calls = 0;
      scope.registerOnDispose(() => calls++);
      scope.registerOnDispose(() => calls += 10);

      scope.dispose();
      expect(calls, 11);

      scope.dispose(); // idempotent — registry cleared
      expect(calls, 11);
    });

    test('unregistered callbacks do not run', () {
      final scope = ReefScope();
      var ran = false;
      void callback() => ran = true;

      scope.registerOnDispose(callback);
      scope.unregisterOnDispose(callback);
      scope.dispose();

      expect(ran, isFalse);
    });

    test('callbacks may unregister during disposal (list-copy iteration)', () {
      final scope = ReefScope();
      var otherRan = false;

      late final void Function() selfRemoving;
      selfRemoving = () => scope.unregisterOnDispose(selfRemoving);

      scope.registerOnDispose(selfRemoving);
      scope.registerOnDispose(() => otherRan = true);

      expect(scope.dispose, returnsNormally);
      expect(otherRan, isTrue);
    });
  });

  group('reefScopeProvider', () {
    test('one scope per buffer id, isolated between ids', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final a = container.read(reefScopeProvider(BufferId.manual('a')));
      final b = container.read(reefScopeProvider(BufferId.manual('b')));

      expect(identical(a, b), isFalse);
      expect(container.read(reefScopeProvider(BufferId.manual('a'))), same(a));
    });

    test('scope is shared while any listener watches, disposed with the last',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final id = BufferId.manual('shared');
      final sub1 = container.listen(reefScopeProvider(id), (_, _) {});
      final scope = container.read(reefScopeProvider(id));

      var disposed = false;
      scope.registerOnDispose(() => disposed = true);

      final sub2 = container.listen(reefScopeProvider(id), (_, _) {});
      sub2.close(); // one window gone — buffer still alive
      await Future<void>.delayed(Duration.zero);
      expect(disposed, isFalse);

      sub1.close(); // last window gone — buffer dies
      // autoDispose runs on a scheduled microtask, not synchronously.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(disposed, isTrue, reason: 'autoDispose runs scope.dispose');
    });
  });
}
