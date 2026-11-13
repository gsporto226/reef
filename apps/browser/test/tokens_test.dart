import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/tokens.dart';

void main() {
  test('lib/src/tokens.g.dart is up to date with design/tokens.json', () {
    // Compared without CRs: a CRLF checkout must not fail it.
    String read(String path) =>
        File(path).readAsStringSync().replaceAll('\r', '');
    expect(read(output), tokensSource(read(input)));
  });
}
