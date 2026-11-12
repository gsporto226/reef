import 'package:reef/reef.dart';
import 'package:reef_router/reef_router.dart';

/// The task list, the home page: `/`.
final class TaskListRoute {
  const TaskListRoute();

  static final link = Link<TaskListRoute>('').build(TaskListRoute.new);
}

/// The editor of the task titled [title]: `/tasks/Buy milk/edit`.
final class TaskEditRoute {
  const TaskEditRoute(this.title);
  final String title;

  static final link = Link<TaskEditRoute>('tasks')
      .field((r) => r.title)
      .literal('edit')
      .build(TaskEditRoute.new);
}

/// Any other path; the example shows nothing for it.
final class NotFoundRoute {
  const NotFoundRoute(this.path);
  final List<String> path;

  static final link = Link<NotFoundRoute>('')
      .rest((r) => r.path)
      .build(NotFoundRoute.new);
}

/// The paths of the buffers a link can reach.
final exampleLinks = LinkTree<Object>([
  TaskListRoute.link,
  TaskEditRoute.link,
  NotFoundRoute.link,
]);

/// The task list buffer.
final taskListBuffer = exampleLinks.linkOf(const TaskListRoute()).buffer;

/// The editor buffer for [title].
BufferId taskEditBuffer(String title) =>
    exampleLinks.linkOf(TaskEditRoute(title)).buffer;
