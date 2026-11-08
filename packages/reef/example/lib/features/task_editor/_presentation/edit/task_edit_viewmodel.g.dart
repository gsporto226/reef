// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'task_edit_viewmodel.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The page's viewmodel: owns the model, exposes out-bindings (`$`-prefixed)
/// and in-bindings (intents), owns ephemeral UI objects and mediates every
/// UI ↔ model transition with transient-unsubscription loop-breaking.
///
/// Family-keyed by [bufferId] — the buffer materializer (§4.4): one provider
/// member per buffer; windows sharing a buffer id share the viewmodel.
/// Hibernation lifecycle (§10.2): registers in the buffer registry,
/// auto-hibernates the model JSON on dispose and rematerializes from it when
/// the same buffer id is reopened.

@ProviderFor(taskEditViewModel)
final taskEditViewModelProvider = TaskEditViewModelFamily._();

/// The page's viewmodel: owns the model, exposes out-bindings (`$`-prefixed)
/// and in-bindings (intents), owns ephemeral UI objects and mediates every
/// UI ↔ model transition with transient-unsubscription loop-breaking.
///
/// Family-keyed by [bufferId] — the buffer materializer (§4.4): one provider
/// member per buffer; windows sharing a buffer id share the viewmodel.
/// Hibernation lifecycle (§10.2): registers in the buffer registry,
/// auto-hibernates the model JSON on dispose and rematerializes from it when
/// the same buffer id is reopened.

final class TaskEditViewModelProvider
    extends
        $FunctionalProvider<
          TaskEditViewModel,
          TaskEditViewModel,
          TaskEditViewModel
        >
    with $Provider<TaskEditViewModel> {
  /// The page's viewmodel: owns the model, exposes out-bindings (`$`-prefixed)
  /// and in-bindings (intents), owns ephemeral UI objects and mediates every
  /// UI ↔ model transition with transient-unsubscription loop-breaking.
  ///
  /// Family-keyed by [bufferId] — the buffer materializer (§4.4): one provider
  /// member per buffer; windows sharing a buffer id share the viewmodel.
  /// Hibernation lifecycle (§10.2): registers in the buffer registry,
  /// auto-hibernates the model JSON on dispose and rematerializes from it when
  /// the same buffer id is reopened.
  TaskEditViewModelProvider._({
    required TaskEditViewModelFamily super.from,
    required BufferId super.argument,
  }) : super(
         retry: null,
         name: r'taskEditViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$taskEditViewModelHash();

  @override
  String toString() {
    return r'taskEditViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<TaskEditViewModel> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  TaskEditViewModel create(Ref ref) {
    final argument = this.argument as BufferId;
    return taskEditViewModel(ref, bufferId: argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TaskEditViewModel value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TaskEditViewModel>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TaskEditViewModelProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$taskEditViewModelHash() => r'd8184592a2be7b943f6c87dea7abfc79dc7da925';

/// The page's viewmodel: owns the model, exposes out-bindings (`$`-prefixed)
/// and in-bindings (intents), owns ephemeral UI objects and mediates every
/// UI ↔ model transition with transient-unsubscription loop-breaking.
///
/// Family-keyed by [bufferId] — the buffer materializer (§4.4): one provider
/// member per buffer; windows sharing a buffer id share the viewmodel.
/// Hibernation lifecycle (§10.2): registers in the buffer registry,
/// auto-hibernates the model JSON on dispose and rematerializes from it when
/// the same buffer id is reopened.

final class TaskEditViewModelFamily extends $Family
    with $FunctionalFamilyOverride<TaskEditViewModel, BufferId> {
  TaskEditViewModelFamily._()
    : super(
        retry: null,
        name: r'taskEditViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The page's viewmodel: owns the model, exposes out-bindings (`$`-prefixed)
  /// and in-bindings (intents), owns ephemeral UI objects and mediates every
  /// UI ↔ model transition with transient-unsubscription loop-breaking.
  ///
  /// Family-keyed by [bufferId] — the buffer materializer (§4.4): one provider
  /// member per buffer; windows sharing a buffer id share the viewmodel.
  /// Hibernation lifecycle (§10.2): registers in the buffer registry,
  /// auto-hibernates the model JSON on dispose and rematerializes from it when
  /// the same buffer id is reopened.

  TaskEditViewModelProvider call({required BufferId bufferId}) =>
      TaskEditViewModelProvider._(argument: bufferId, from: this);

  @override
  String toString() => r'taskEditViewModelProvider';
}
