// The design builder over the real design files: its output must match the
// checked-in generated sources, so a design sync without a rebuild fails.
import 'dart:io';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:mail_client/design_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the generated tokens and glyphs are up to date', () async {
    String read(String path) => File(path).readAsStringSync();
    await testBuilder(
      designBuilder(const BuilderOptions({})),
      {
        'mail_client|design/tokens.json': read('design/tokens.json'),
        'mail_client|design/SPEC.snapshot.json': read(
          'design/SPEC.snapshot.json',
        ),
      },
      outputs: {
        'mail_client|lib/src/tokens.g.dart': read('lib/src/tokens.g.dart'),
        'mail_client|lib/src/icons.g.dart': read('lib/src/icons.g.dart'),
      },
    );
  });

  test('unknown token types and icon nodes are refused', () async {
    final result = await testBuilder(designBuilder(const BuilderOptions({})), {
      'mail_client|design/tokens.json':
          '{"x": {"\$type": "shadow", "\$value": {}}}',
      'mail_client|design/SPEC.snapshot.json':
          '{"component:Icon / x": {"data": {"description": "", "children": '
          '[{"type": "star", "width": 1, "height": 1}]}}}',
    });
    expect(result.succeeded, isFalse);
    expect(
      result.errors.join(),
      allOf(contains('token type shadow'), contains('icon node type star')),
    );
  });
}
