// Self-check for tool/coverage.dart:
//   dart run --enable-asserts tool/coverage_test.dart

import 'coverage.dart';

void main() {
  final hits = <String, Map<int, int>>{};

  // Unit run in packages/reef: covers line 1 only.
  mergeLcov(hits, 'C:/r/packages/reef', '''
SF:lib\\a.dart
DA:1,3
DA:2,0
end_of_record
''');
  // Integration run in the example: same file via ..\, covers line 2.
  mergeLcov(hits, 'C:/r/packages/reef/example', '''
SF:..\\lib\\a.dart
DA:1,0
DA:2,1
DA:3,0
end_of_record
''');

  final result = uncovered(hits, [
    'C:\\r\\packages\\reef\\lib\\a.dart',
    'C:/r/packages/reef/lib/never_loaded.dart',
  ]);
  assert(result['C:\\r\\packages\\reef\\lib\\a.dart']!.single == 3,
      'layers merge: lines 1 and 2 are covered across runs, 3 is not');
  assert(result.containsKey('C:/r/packages/reef/lib/never_loaded.dart') &&
      result['C:/r/packages/reef/lib/never_loaded.dart'] == null,
      'a file no layer loaded is reported, not skipped');

  assert(isGated('packages/reef/lib/x.dart'));
  assert(!isGated('packages/reef/lib/x.g.dart'));
  assert(!isGated('packages/reef/test/x_test.dart'));
  assert(!isGated('tool/coverage.dart'));
  assert(!isGated('packages/reef_multi_window/lib/src/shell_views.dart'));
  assert(!isGated('C:/reef/apps/browser/lib/entry.dart'));
  assert(isGated('apps/browser/lib/main.dart'));

  assert(!hasCode("/// Barrel.\nlibrary;\n\nexport 'a.dart';\n"));
  assert(hasCode("export 'a.dart';\nint x = 1;\n"));

  assert(coveragePackages('name: browser\nversion: 1.0.0\n').last ==
      '--coverage-package=^browser');

  print('coverage_test: ok');
}
