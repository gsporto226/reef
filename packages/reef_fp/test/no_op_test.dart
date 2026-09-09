import 'package:reef_fp/no_op.dart';
import 'package:test/test.dart';

void main() {
  group('noop', () {
    test('noop', () {
      expect(() => noop(1), returnsNormally);
    });
  });
}
