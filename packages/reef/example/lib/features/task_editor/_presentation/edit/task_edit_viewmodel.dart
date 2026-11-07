import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:formularium/features/forms/_data_types/form_field_status.dart';
import 'package:formularium/features/forms/_implementations/formularium_form_field.dart';
import 'package:listenable_plus/listenable_plus.dart';
import 'package:reef/features/formularium_bridge/_implementations/result_validation.dart';
import 'package:reef/features/hibernation/_implementations/lifecycle.dart';
import 'package:reef/features/page_identity/_implementations/buffer_id.dart';
import 'package:reef/features/undo/_implementations/buffer_undo_host.dart';
import 'package:reef/features/view_model/_implementations/view_model.dart';
import 'package:reef_example/features/task_editor/_presentation/edit/task_edit_model.dart';
import 'package:reef_example/undo_providers.dart';
import 'package:reef_fp/async.dart';
import 'package:reef_fp/result.dart';
import 'package:reef_fp/unit.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'task_edit_viewmodel.g.dart';

/// The page's viewmodel: owns the model, exposes out-bindings (`$`-prefixed)
/// and in-bindings (intents), owns ephemeral UI objects and mediates every
/// UI ↔ model transition with transient-unsubscription loop-breaking.
///
/// Family-keyed by [bufferId] — the buffer materializer (§4.4): one provider
/// member per buffer; windows sharing a buffer id share the viewmodel.
/// Hibernation lifecycle (§10.2): registers in the buffer registry,
/// auto-hibernates the model JSON on dispose and rematerializes from it when
/// the same buffer id is reopened.
@riverpod
TaskEditViewModel taskEditViewModel(
  Ref ref, {
  required BufferId bufferId,
  TaskEditModel? initial,
}) {
  trackBuffer(ref, bufferId);
  // Hibernation wins over the route seed (§10.2): a rematerialized buffer
  // restores its hibernated model; the seed only matters for fresh buffers.
  final seed = hibernatedSeed<TaskEditModel>(ref, bufferId, TaskEditModel.fromJson) ?? initial;
  final vm = TaskEditViewModel(initialModel: seed)
    ..attachUndo(ref.watch(bufferUndoHostProvider), bufferId);
  hibernateOnDispose(ref, bufferId, () => vm.model.toJson());
  ref.onDispose(vm.dispose);
  return vm;
}

class TaskEditViewModel extends ViewModel<TaskEditModel>
    with UndoableModel<TaskEditModel> {
  TaskEditViewModel({TaskEditModel? initialModel})
    : super(initialModel ?? const TaskEditModel()) {
    final base = initialModel ?? const TaskEditModel();

    // Ephemeral UI objects — seeded from the model at construction (this is
    // the restore path: a restored model seeds a fresh viewmodel).
    titleController = TextEditingController(text: base.title);
    registerDisposal(titleController.dispose);

    dueDateFocus = FocusNode();
    registerDisposal(dueDateFocus.dispose);

    // Input tier: the formularium field OWNS validation and **delegates to the
    // model method** — the invariant is never encoded twice.
    dueDateField = FormulariumFormField<DateTime?, DateTime?>(
      initialValue: base.dueDate,
      validator: modelValidator<TaskEditModel, DateTime?, TaskError>(
        apply: (date) => model.withDueDate(date),
        localize: (error) => error,
      ),
      enabled: true,
      autovalidateMode: AutovalidateMode.always,
      focusNode: dueDateFocus,
    );
    registerDisposal(dueDateField.dispose);

    // Plumbing — bind() assumes UI objects were seeded above.
    bindText(
      titleController,
      $title,
      apply: (value) => Ok<TaskError, TaskEditModel>(model.withTitle(value)),
      via: titleOp,
    );
    bindField<DateTime?, TaskError>(
      field: dueDateField,
      modelValue: $dueDate,
      apply: (date) => model.withDueDate(date),
      via: dueDateOp,
    );
  }

  late final TextEditingController titleController;
  late final FocusNode dueDateFocus;
  late final FormulariumFormField<DateTime?, DateTime?> dueDateField;

  late final titleOp = operation<Unit, TaskError>();
  late final dueDateOp = operation<Unit, TaskError>();
  late final saveOp = operation<Unit, TaskError>();

  // ---- Out-bindings (all derived from `$model` or owned listenables) ----

  ValueListenable<String> get $title => $model.select((m) => m.title);
  ValueListenable<DateTime?> get $dueDate => $model.select((m) => m.dueDate);

  /// Input-tier state: the formularium field status (validation surface).
  ValueListenable<FormFieldStatus<DateTime?>> get $dueDateStatus => dueDateField.$status;

  /// Application-tier state: the save operation (`Async<Result<E, T>>`).
  ValueListenable<Async<Result<TaskError, Unit>>> get $save => saveOp.$state;

  // ---- In-bindings (intents) ----

  /// Live style: picking a date feeds the field; autovalidate runs the model
  /// method; on `Valid` the bindField in-channel applies and publishes.
  /// `null` clears the due date.
  void onDueDatePicked(DateTime? date) => dueDateField.value = date;

  /// Submit style: always validate (full, not dirty-only), then apply + save.
  Future<void> onSubmit() async {
    dueDateField.validate();
    final status = dueDateField.status;
    if (status is! Valid<DateTime?>) {
      return; // field $status already surfaces the error
    }
    edit(model.withDueDate(status.transformed), via: dueDateOp);
    await saveOp.run(_save);
  }

  Future<Result<TaskError, Unit>> _save() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    // Fake service: fails when the title is empty (mapped to a domain error).
    if (model.title.trim().isEmpty) {
      return const Err(TaskError.saveFailed);
    }
    return const Ok(Unit.unit);
  }

  // ---- Hibernation contract: the model is serializable; restoring is just a
  // publish — the out-channel re-seeds every UI object (transient-unsub keeps
  // it echo-free). ----

  String hibernate() => model.toJson().toString();

  void restore(Map<String, dynamic> json) => publish(TaskEditModel.fromJson(json));
}
