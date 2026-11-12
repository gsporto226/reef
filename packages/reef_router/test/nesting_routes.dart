import 'package:reef_router/reef_router.dart';

// Routes shared by link_nesting_test and the compile-error fixtures.

/// Routes compare by their URL, which is what nesting must preserve.
abstract base class AppRoute with LinkVerbs<AppRoute> {
  const AppRoute();

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType && '$other' == '$this';

  @override
  int get hashCode => '$this'.hashCode;
}

base class ProjectRoute extends AppRoute {
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
