import 'package:flutter_test/flutter_test.dart';
import 'package:reef/reef.dart';
import 'package:reef_router/reef_router.dart';

/// Routes compare by their URL, which is what nesting must preserve.
abstract base class AppRoute with LinkVerbs<AppRoute> {
  const AppRoute();

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType && '$other' == '$this';

  @override
  int get hashCode => '$this'.hashCode;
}

final class ProjectRoute extends AppRoute {
  const ProjectRoute(this.id, {this.page = 1});
  final String id;
  final int page;

  static final link = Link<ProjectRoute>('projects')
      .field((r) => r.id)
      .query('page', (r) => r.page, fallback: 1)
      .build((id, page) => ProjectRoute(id, page: page));

  @override
  String toString() => 'Project($id, $page)';
}

final class TaskRoute extends AppRoute {
  const TaskRoute(this.project, this.id, {this.sort = 'old'});
  final ProjectRoute project;
  final String id;
  final String sort;

  static final link = Link<TaskRoute>('tasks')
      .parent((r) => r.project)
      .field((r) => r.id)
      .query('sort', (r) => r.sort, fallback: 'old')
      .build((project, id, sort) => TaskRoute(project, id, sort: sort));

  @override
  String toString() => 'Task($project, $id, $sort)';
}

final class ProjectMissingRoute extends AppRoute {
  const ProjectMissingRoute(this.project, this.path);
  final ProjectRoute project;
  final List<String> path;

  static final link = Link<ProjectMissingRoute>('')
      .parent((r) => r.project)
      .rest((r) => r.path)
      .build(ProjectMissingRoute.new);

  @override
  String toString() => 'ProjectMissing($project, $path)';
}

final class FilesRoute extends AppRoute {
  const FilesRoute(this.path);
  final List<String> path;

  static final link = Link<FilesRoute>('files')
      .rest((r) => r.path)
      .build(FilesRoute.new);

  @override
  String toString() => 'Files($path)';
}

final class FileEditRoute extends AppRoute {
  const FileEditRoute(this.file);
  final FilesRoute file;

  static final link = Link<FileEditRoute>('edit')
      .parent((r) => r.file)
      .build(FileEditRoute.new);

  @override
  String toString() => 'FileEdit($file)';
}

final class NotFoundRoute extends AppRoute {
  const NotFoundRoute(this.path);
  final List<String> path;

  static final link = Link<NotFoundRoute>('')
      .rest((r) => r.path)
      .build(NotFoundRoute.new);

  @override
  String toString() => 'NotFound($path)';
}

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
        ProjectRoute.link,
        FilesRoute.link.children([ProjectRoute.link]),
      ]),
      throwsStateError,
    );
  });

  test('a link needing a parent fails at the root', () {
    expect(
      () => LinkTree<AppRoute>([NotFoundRoute.link, TaskRoute.link]),
      throwsStateError,
    );
  });

  test('a link needing a parent fails under another route type', () {
    expect(
      () => LinkTree<AppRoute>([
        NotFoundRoute.link,
        FilesRoute.link.children([TaskRoute.link]),
      ]),
      throwsStateError,
    );
  });

  test('a link without a parent value fails under a parent with values', () {
    expect(
      () => LinkTree<AppRoute>([
        NotFoundRoute.link,
        ProjectRoute.link.children([FilesRoute.link]),
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
