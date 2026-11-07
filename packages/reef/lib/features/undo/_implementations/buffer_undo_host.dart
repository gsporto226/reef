import 'package:formularium/features/localization/localizable_interface.dart';
import 'package:reef/features/page_identity/_implementations/buffer_id.dart';
import 'package:reef/features/undo/_implementations/undo_controller.dart';
import 'package:reef/features/view_model/_implementations/view_model.dart';

/// A buffer's model at one point in time (spec §4).
class BufferSnapshot {
  const BufferSnapshot(this.bufferId, this.model);

  final BufferId bufferId;
  final Object? model;
}

/// The label on every buffer content undo entry.
class BufferEdit implements ILocalizable {
  const BufferEdit();

  @override
  String localize() => 'Edit';
}

/// Publishes [BufferSnapshot]s back through the buffer's live view model
/// without recording them. Registers itself on [UndoController].
class BufferUndoHost implements UndoHost<BufferSnapshot> {
  BufferUndoHost(this._undo) {
    _undo.registerHost<BufferSnapshot>(this);
  }

  final UndoController _undo;
  final _models = <BufferId, UndoableModel<Object?>>{};

  // ponytail: no live view model (buffer hibernated) means a no-op; writing
  // into the hibernation store would need the model's JSON codec here.
  @override
  void undo(BufferSnapshot snapshotBefore) =>
      _models[snapshotBefore.bufferId]?._restore(snapshotBefore.model);

  @override
  void redo(BufferSnapshot snapshotAfter) =>
      _models[snapshotAfter.bufferId]?._restore(snapshotAfter.model);
}

/// Makes a view model's content edits undoable: after [attachUndo], every
/// [publish] that changes the model records one entry. Entries carry whole
/// models, so undo works on a view model rematerialized from hibernation.
///
/// Focused text fields consume Ctrl+Z first; field-level undo stays
/// Flutter's. Reef binds no shell shortcut to [UndoController.undo] (W2).
mixin UndoableModel<M> on ViewModel<M> {
  BufferUndoHost? _host;
  late BufferId _bufferId;

  /// Records later publishes under [bufferId]. The latest view model attached
  /// for a buffer receives its undo and redo. Call from the constructor.
  void attachUndo(BufferUndoHost host, BufferId bufferId) {
    _host = host;
    _bufferId = bufferId;
    host._models[bufferId] = this;
    registerDisposal(() {
      if (host._models[bufferId] == this) host._models.remove(bufferId);
    });
  }

  @override
  void publish(M newModel) {
    final before = model;
    if (_host case final host? when newModel != before) {
      host._undo.record(UndoEntry<BufferSnapshot>(
        label: const BufferEdit(),
        snapshotBefore: BufferSnapshot(_bufferId, before),
        snapshotAfter: BufferSnapshot(_bufferId, newModel),
      ));
    }
    super.publish(newModel);
  }

  void _restore(Object? model) => super.publish(model as M);
}
