import 'package:reef/features/page_identity/_implementations/buffer_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BufferId', () {
    test('generate() produces unique ids', () {
      final ids = {for (var i = 0; i < 1000; i++) BufferId.generate().id};
      expect(ids.length, 1000);
    });

    test('generate() is time-sortable across milliseconds', () async {
      // v7 sorts by timestamp; within one millisecond ordering falls to
      // random bits, so generations are spaced out to test the guarantee.
      final ids = <String>[];
      for (var i = 0; i < 10; i++) {
        ids.add(BufferId.generate().id);
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      final sorted = List<String>.of(ids)..sort();
      expect(ids, sorted);
    });

    test('manual() keeps the given string', () {
      expect(BufferId.manual('test-buffer').id, 'test-buffer');
    });

    test('equality is string equality (extension type)', () {
      expect(BufferId.manual('a'), BufferId.manual('a'));
      expect(BufferId.manual('a'), isNot(BufferId.manual('b')));
      // v7 generation of the same string never collides in practice; manual
      // ids with equal strings are the same buffer by definition.
      expect(BufferId.manual('a').hashCode, BufferId.manual('a').hashCode);
    });

    test('sub() nests under the parent and siblings are distinct', () {
      final parent = BufferId.manual('p');
      final childA = parent.sub('a');
      final childB = parent.sub('b');

      expect(childA.id, 'p.a');
      expect(childB.id, 'p.b');
      expect(childA, isNot(childB));
      expect(childA.id, startsWith(parent.id));
    });
  });
}
