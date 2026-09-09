import 'package:reef_fp/identity.dart';
import 'package:test/test.dart';

void main() {
  group('identity', () {
    test('identity', () {
      expect(identity(1), 1);
      expect(identity('string'), 'string');
      expect(identity(true), true);
    });
    test('identityAsync', () async {
      expect(await identityAsync(1), 1);
      expect(await identityAsync(Future.value(true)), true);
    });
  });
}
