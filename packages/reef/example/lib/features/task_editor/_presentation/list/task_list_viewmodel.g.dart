// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'task_list_viewmodel.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The list page's viewmodel: binds the search field to the model's query and
/// feeds it to the infinite-scroll controller as the filter.

@ProviderFor(taskListViewModel)
final taskListViewModelProvider = TaskListViewModelFamily._();

/// The list page's viewmodel: binds the search field to the model's query and
/// feeds it to the infinite-scroll controller as the filter.

final class TaskListViewModelProvider
    extends
        $FunctionalProvider<
          TaskListViewModel,
          TaskListViewModel,
          TaskListViewModel
        >
    with $Provider<TaskListViewModel> {
  /// The list page's viewmodel: binds the search field to the model's query and
  /// feeds it to the infinite-scroll controller as the filter.
  TaskListViewModelProvider._({
    required TaskListViewModelFamily super.from,
    required BufferId super.argument,
  }) : super(
         retry: null,
         name: r'taskListViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$taskListViewModelHash();

  @override
  String toString() {
    return r'taskListViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<TaskListViewModel> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  TaskListViewModel create(Ref ref) {
    final argument = this.argument as BufferId;
    return taskListViewModel(ref, bufferId: argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TaskListViewModel value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TaskListViewModel>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TaskListViewModelProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$taskListViewModelHash() => r'4fd803b92a7cdd0c8889c236476f73699ca25a2a';

/// The list page's viewmodel: binds the search field to the model's query and
/// feeds it to the infinite-scroll controller as the filter.

final class TaskListViewModelFamily extends $Family
    with $FunctionalFamilyOverride<TaskListViewModel, BufferId> {
  TaskListViewModelFamily._()
    : super(
        retry: null,
        name: r'taskListViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The list page's viewmodel: binds the search field to the model's query and
  /// feeds it to the infinite-scroll controller as the filter.

  TaskListViewModelProvider call({required BufferId bufferId}) =>
      TaskListViewModelProvider._(argument: bufferId, from: this);

  @override
  String toString() => r'taskListViewModelProvider';
}
