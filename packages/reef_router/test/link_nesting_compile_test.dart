// Wrong nesting is a compile error (spec stories 17, 18, 19; #69): each
// fixture is analyzed and must report an error; the valid one none.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _header = '''
import 'package:reef_router/reef_router.dart';
import '../nesting_routes.dart';
''';

const _fixtures = {
  'valid': '''
final tree = LinkTree<AppRoute>([
  NotFoundRoute.link,
  ProjectRoute.link.children([TaskRoute.link, ProjectMissingRoute.link]),
  FilesRoute.link.children([FileEditRoute.link]),
  Link<HomeRoute>('home').build(HomeRoute.new).children([FilesRoute.link]),
]);

final class HomeRoute extends AppRoute {
  const HomeRoute();
}
''',
  'parent_at_root': '''
final tree = LinkTree<AppRoute>([NotFoundRoute.link, TaskRoute.link]);
''',
  'parent_of_other_type': '''
final node = FilesRoute.link.children([TaskRoute.link]);
''',
  'parent_of_subtype': '''
final class PinnedProjectRoute extends ProjectRoute {
  const PinnedProjectRoute(super.id);
}

final class PinRoute extends AppRoute {
  const PinRoute(this.project);
  final PinnedProjectRoute project;

  static final link = Link<PinRoute>('pin')
      .parent((r) => r.project)
      .build(PinRoute.new);
}

final node = ProjectRoute.link.children([PinRoute.link]);
''',
  'parent_of_supertype': '''
final class AnyRoute extends AppRoute {
  const AnyRoute(this.parent);
  final AppRoute parent;

  static final link = Link<AnyRoute>('any')
      .parent((r) => r.parent)
      .build(AnyRoute.new);
}

final node = ProjectRoute.link.children([AnyRoute.link]);
''',
  'no_parent_under_values': '''
final node = ProjectRoute.link.children([FilesRoute.link]);
''',
  'parent_under_valueless': '''
final class HomeRoute extends AppRoute {
  const HomeRoute();
  static final link = Link<HomeRoute>('home').build(HomeRoute.new);
}

final class UnderHomeRoute extends AppRoute {
  const UnderHomeRoute(this.home);
  final HomeRoute home;

  static final link = Link<UnderHomeRoute>('x')
      .parent((r) => r.home)
      .build(UnderHomeRoute.new);
}

final node = HomeRoute.link.children([UnderHomeRoute.link]);
''',
};

void main() {
  test('wrong nesting fails to compile; right nesting compiles', () async {
    final dir = Directory('test/_nesting_fixtures')..createSync();
    addTearDown(() => dir.deleteSync(recursive: true));
    for (final MapEntry(:key, :value) in _fixtures.entries) {
      File('${dir.path}/$key.dart').writeAsStringSync('$_header\n$value');
    }
    final dart =
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/dart-sdk'
        '/bin/dart${Platform.isWindows ? '.exe' : ''}';
    final result = await Process.run(dart, [
      'analyze',
      '--format=machine',
      dir.path,
    ]);
    final errors = <String>{
      for (final line in '${result.stdout}${result.stderr}'.split('\n'))
        if (line.startsWith('ERROR|') &&
            line.contains('|LIST_ELEMENT_TYPE_NOT_ASSIGNABLE|'))
          line.split('|')[3].split(RegExp(r'[\\/]')).last,
    };
    expect(errors, {
      for (final name in _fixtures.keys)
        if (name != 'valid') '$name.dart',
    }, reason: '${result.stdout}${result.stderr}');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
