import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:formularium/features/forms/_data_types/form_field_status.dart';
import 'package:formularium/features/forms/_implementations/raw_formularium_form_field.dart';
import 'package:reef/features/operation/_implementations/operation.dart';
import 'package:reef_fp/result.dart';
import 'package:reef_fp/unit.dart';

/// Base class for the ViewModel layer of the reef quartet.
///
/// Owns the page [model] and exposes it as a [ValueListenable] (`$model` — the
/// out-binding root). Subclasses declare out-bindings (`$`-prefixed derived
/// listenables), in-bindings (intents), ephemeral UI objects and bind them with
/// [bind] / [bindText] / [bindField].
///
/// The viewmodel is the **sole publisher** of the model: UI objects are
/// Listenable sources the viewmodel subscribes to; every transition between
/// model state and UI state is mediated here, with echo loops broken by
/// transient unsubscription only (see `docs/blueprint.md` §5).
abstract class ViewModel<M> {
  /// Creates a viewmodel owning [initialModel].
  ViewModel(M initialModel)
    : _model = initialModel,
      _$model = ValueNotifier<M>(initialModel);

  M _model;
  final ValueNotifier<M> _$model;

  final List<void Function()> _detachments = [];
  final List<void Function()> _disposals = [];
  bool _disposed = false;

  /// The current model instance. Transform it through the model's named
  /// methods and [publish] the result — never mutate state outside it.
  M get model => _model;

  /// Reactive view of the model — the out-binding root.
  ValueListenable<M> get $model => _$model;

  /// Creates and registers an [Operation] owned by this viewmodel.
  Operation<T, E> operation<T, E>() {
    final op = Operation<T, E>();
    _disposals.add(op.dispose);
    return op;
  }

  /// Replaces the model and notifies listeners. Sole mutation point.
  /// [coalesceKey] is for undo-aware mixins (`UndoableModel`); ignored here.
  @protected
  void publish(M newModel, {Object? coalesceKey}) {
    _model = newModel;
    _$model.value = newModel;
  }

  /// THE method for fallible model changes — every `Result<E, M>` returned by
  /// a model method funnels through here:
  ///
  /// - `Ok(model)` → resets [via] and publishes the new model;
  /// - `Err(error)` → surfaces the failure on [via] and runs [onFail]
  ///   reconciliations (e.g. re-sync the UI object to model state).
  void edit<E>(
    Result<E, M> result, {
    required Operation<Unit, E> via,
    List<VoidCallback> onFail = const [],
    Object? coalesceKey,
  }) {
    result.fold(
      (e) {
        via.fail(e);
        for (final r in onFail) {
          r();
        }
      },
      (m) {
        via.reset();
        publish(m, coalesceKey: coalesceKey);
      },
    );
  }

  /// Two-way binding between a model-derived field listenable and a UI object.
  ///
  /// - **In-channel:** subscribes to [uiValue]; on change, applies
  ///   `apply(fromUi(...))` through [edit] — publishing only on success,
  ///   reconciling the UI object on failure.
  /// - **Out-channel:** subscribes to [modelValue]; on change, writes
  ///   `toUi(...)` into the UI object via [writeUi].
  /// - **Loop-breaking:** while processing an in-event the out-listener is
  ///   removed; while performing an out-write the in-listener is removed.
  ///   Events arriving during suppression are dropped, never buffered.
  ///
  /// The UI object is expected to be **seeded from the model at construction**
  /// — [bind] does not perform an initial out-write.
  void bind<Ui, Field, E>({
    required ValueListenable<Field> modelValue,
    required ValueListenable<Ui> uiValue,
    required Ui Function(Field value) toUi,
    required Field Function(Ui value) fromUi,
    required void Function(Ui value) writeUi,
    required Result<E, M> Function(Field value) apply,
    required Operation<Unit, E> via,
    Object? coalesceKey,
  }) {
    late final void Function() onUi;
    late final void Function() onModel;

    // Out-channel: suppress the in-listener while writing the model value into
    // the UI object. Doubles as the failure reconciliation (rejected in-binds
    // end with the UI object re-synced to model state).
    onModel = () {
      uiValue.removeListener(onUi);
      try {
        writeUi(toUi(modelValue.value));
      } finally {
        uiValue.addListener(onUi);
      }
    };

    // In-channel: suppress the out-listener while applying the UI value.
    onUi = () {
      modelValue.removeListener(onModel);
      try {
        edit(apply(fromUi(uiValue.value)),
            via: via, onFail: [onModel], coalesceKey: coalesceKey);
      } finally {
        modelValue.addListener(onModel);
      }
    };
    uiValue.addListener(onUi);
    modelValue.addListener(onModel);
    _detachments.add(() {
      uiValue.removeListener(onUi);
      modelValue.removeListener(onModel);
    });
  }

  /// [bind] specialization for [TextEditingController] ↔ `String` model field.
  ///
  /// The out-write replaces the controller value with the model text and
  /// collapses the selection to the end of the text.
  void bindText<E>(
    TextEditingController controller,
    ValueListenable<String> modelValue, {
    required Result<E, M> Function(String value) apply,
    required Operation<Unit, E> via,
    Object? coalesceKey,
  }) {
    bind(
      modelValue: modelValue,
      uiValue: controller,
      fromUi: (value) => value.text,
      toUi: (text) => TextEditingValue(text: text),
      writeUi: (value) => controller.value = value,
      apply: apply,
      via: via,
      coalesceKey: coalesceKey,
    );
  }

  /// Two-way binding between a formularium field and a model-derived field
  /// listenable (the input tier of `docs/blueprint.md` §6).
  ///
  /// - **In-channel:** subscribes to the field `$status`; on `Valid`, applies
  ///   the model method through [edit]. On failure (stale apply — possible in
  ///   submit-style flows) the field is re-validated against the current model
  ///   state, self-healing the discrepancy.
  /// - **Out-channel:** on model change, pushes the value into the field with
  ///   `valueRaw` + `validate()` (no dirty marking), with the status listener
  ///   transiently removed.
  ///
  /// The field is expected to be created with its `initialValue` taken from
  /// the model — [bindField] does not perform an initial out-write.
  void bindField<F, E>({
    required RawFormulariumFormField<F, F> field,
    required ValueListenable<F> modelValue,
    required Result<E, M> Function(F value) apply,
    required Operation<Unit, E> via,
  }) {
    void onStatus() {
      final status = field.status;
      if (status is Valid<F>) {
        edit(apply(status.transformed), via: via, onFail: [field.validate]);
      }
    }

    void onModel() {
      field.$status.removeListener(onStatus);
      try {
        field.valueRaw(modelValue.value);
        field.validate();
      } finally {
        field.$status.addListener(onStatus);
      }
    }

    field.$status.addListener(onStatus);
    modelValue.addListener(onModel);
    _detachments.add(() {
      field.$status.removeListener(onStatus);
      modelValue.removeListener(onModel);
    });
  }

  /// Registers a disposal callback executed by [dispose].
  @protected
  void registerDisposal(void Function() disposal) => _disposals.add(disposal);

  /// Detaches all bindings and runs registered disposals (operations, fields,
  /// controllers — reverse registration order). Idempotent. Subclasses
  /// overriding this must call `super.dispose()`.
  @mustCallSuper
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    for (final detach in _detachments) {
      detach();
    }
    _detachments.clear();
    for (final disposal in _disposals.reversed) {
      disposal();
    }
    _disposals.clear();
    _$model.dispose();
  }
}
