import 'package:flutter_test/flutter_test.dart';
import 'package:reef/reef.dart';
import 'package:reef_router/reef_router.dart';

import 'nesting_routes.dart';

final tree = LinkTree<AppRoute>([
  NotFoundRoute.link,
  ProjectRoute.link.children([TaskRoute.link, ProjectMissingRoute.link]),
  FilesRoute.link.children([FileEditRoute.link]),
]);

AppRoute at(String uri) => tree.routeOf(Uri.parse(uri));

void main() {
  test('a child URL carries its parent path and query, and decodes back', () {
    const route = TaskRoute(ProjectRoute('p1', page: 3), 't9', sort: 'new');
    final uri = tree.uriOf(route);
    expect(uri.toString(), '/projects/p1/tasks/t9?page=3&sort=new');
    expect(tree.routeOf(uri), route);
    expect(
      at('/projects/p1/tasks/t9'),
      const TaskRoute(ProjectRoute('p1'), 't9'),
    );
    expect(at('/projects/p1?page=2'), const ProjectRoute('p1', page: 2));
  });

  test('a child buffer kind is its mounted path', () {
    const route = TaskRoute(ProjectRoute('p1', page: 3), 't9');
    final (:buffer, :arguments) = tree.linkOf(route);
    expect(buffer, BufferId.of('/projects/*/tasks/*', 'p1/t9'));
    expect(arguments, {'page': '3'});
    expect(tree.routeOfBuffer(buffer, arguments), route);
  });

  test('a child redeclaring an inherited query key fails at startup', () {
    final child = Link<TaskRoute>('tasks')
        .parent((r) => r.project)
        .query('page', (r) => r.id, fallback: '')
        .build((p, id) => TaskRoute(p, id));
    expect(
      () => LinkTree<AppRoute>([
        NotFoundRoute.link,
        ProjectRoute.link.children([child]),
      ]),
      throwsA(
        isStateError.having((e) => e.message, 'message', contains('parent')),
      ),
    );
  });

  test('a link mounted twice fails at startup', () {
    expect(
      () => LinkTree<AppRoute>([
        NotFoundRoute.link,
        FilesRoute.link,
        ProjectRoute.link.children([TaskRoute.link, TaskRoute.link]),
      ]),
      throwsStateError,
    );
  });

  test('a rest parent has children matched from the end; the child wins', () {
    expect(at('/files/a/b'), const FilesRoute(['a', 'b']));
    expect(at('/files/a/b/edit'), const FileEditRoute(FilesRoute(['a', 'b'])));
    const route = FileEditRoute(FilesRoute(['a', 'b']));
    expect(tree.uriOf(route).toString(), '/files/a/b/edit');
    final buffer = tree.linkOf(route).buffer;
    expect(buffer, BufferId.of('/files/**/edit', 'a/b'));
    expect(tree.routeOfBuffer(buffer), route);
  });

  test('a catch-all under a parent gives a scoped not-found', () {
    expect(
      at('/projects/p1/nope/x?page=2'),
      const ProjectMissingRoute(ProjectRoute('p1', page: 2), ['nope', 'x']),
    );
    expect(at('/elsewhere'), const NotFoundRoute(['elsewhere']));
  });
}
