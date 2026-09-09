import 'package:freezed_annotation/freezed_annotation.dart';

part 'task_list_model.freezed.dart';

/// The list page's domain model (§4.1): the filter is model state — typed
/// into the search field, it flows through the sync contract into the
/// infinite-scroll controller.
@freezed
abstract class TaskListModel with _$TaskListModel {
  const factory TaskListModel({@Default('') String query}) = _TaskListModel;

  const TaskListModel._();

  /// Infallible change: returns the modified model.
  TaskListModel withQuery(String value) => TaskListModel(query: value);
}
