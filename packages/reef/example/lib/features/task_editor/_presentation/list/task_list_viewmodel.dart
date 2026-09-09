import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:listenable_plus/listenable_plus.dart';
import 'package:reef/features/page_identity/_implementations/buffer_id.dart';
import 'package:reef/features/view_model/_implementations/view_model.dart';
import 'package:reef_example/features/task_editor/_presentation/edit/task_edit_model.dart'
    show TaskError;
import 'package:reef_example/features/task_editor/_presentation/list/task_list_model.dart';
import 'package:reef_fp/async.dart';
import 'package:reef_fp/result.dart';
import 'package:reef_fp/unit.dart';
import 'package:reef_widgets/features/infinite_scroll/_implementations/infinite_scroll_controller.dart';
import 'package:reef_widgets/features/infinite_scroll/_implementations/infinite_scroll_state.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'task_list_viewmodel.g.dart';

/// The list page's viewmodel: binds the search field to the model's query and
/// feeds it to the infinite-scroll controller as the filter.
@riverpod
TaskListViewModel taskListViewModel(
  Ref ref, {
  required BufferId bufferId,
}) {
  final vm = TaskListViewModel();
  ref.onDispose(vm.dispose);
  return vm;
}

class TaskListViewModel extends ViewModel<TaskListModel> {
  TaskListViewModel() : super(const TaskListModel()) {
    queryController = TextEditingController(text: model.query);
    registerDisposal(queryController.dispose);

    bindText(
      queryController,
      $query,
      apply: (value) => Ok<TaskError, TaskListModel>(model.withQuery(value)),
      via: queryOp,
    );

    scroll = InfiniteScrollController<String, String, TaskError>(
      $filter: $filter,
      loadPage: _source.load,
    );
    registerDisposal(scroll.dispose);
  }

  late final TextEditingController queryController;
  late final InfiniteScrollController<String, String, TaskError> scroll;
  late final queryOp = operation<Unit, TaskError>();
  final _source = const FakeTaskSource();

  ValueListenable<String> get $query => $model.select((m) => m.query);

  /// The scroll filter: the model's query, always ready (input tier owns the
  /// empty case).
  late final ValueListenable<Async<String>> $filter =
      $query.map(Async<String>.ready);
}

/// In-memory paged source: filters the pool by the query and slices pages.
/// An empty page signals the end (§10-adjacent loader contract).
class FakeTaskSource {
  const FakeTaskSource();

  static const pool = [
    'Buy milk', 'Walk dog', 'Write report', 'Clean kitchen', 'Call Alice',
    'Fix bike', 'Read book', 'Plan trip', 'Water plants', 'Pay bills',
    'Buy bread', 'Ship parcel', 'Book dentist', 'Refactor reef', 'Ship reef',
  ];

  Future<Result<TaskError, InfiniteScrollPage<String>>> load({
    required String filter,
    required int page,
    required int pageSize,
  }) async {
    final needle = filter.trim().toLowerCase();
    final matches = pool
        .where((task) => task.toLowerCase().contains(needle))
        .toList(growable: false);
    final start = (page - 1) * pageSize;
    if (start >= matches.length) {
      return Ok(const InfiniteScrollPage<String>(items: []));
    }
    final end = math.min(start + pageSize, matches.length);
    return Ok(InfiniteScrollPage<String>(items: matches.sublist(start, end)));
  }
}
