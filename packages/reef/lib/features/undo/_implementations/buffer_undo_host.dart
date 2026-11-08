import 'package:reef/features/page_identity/_implementations/buffer_id.dart';
import 'package:reef/features/undo/_implementations/undo_controller.dart';
import 'package:reef/features/view_model/_implementations/view_model.dart';

/// A buffer's model at one point in time (spec §4).
class BufferSnapshot {
  const BufferSnapshot(this.bufferId, this.model);

  final BufferId bufferId;
  final Object? model;

  @override
  bool operator ==(Object other) =>
      other is BufferSnapshot &&
      other.bufferId == bufferId &&
      other.model == model;

  @override
  int get hashCode => Object.hash(bufferId, model);
}

/// Publishes [BufferSnapshot]s back through the buffer's live view model
/// without recording them. A snapshot for a buffer with no live view model
/// (hibernated) waits until one attaches. Registers itself on [UndoController].
class BufferUndoHost implements UndoHost<BufferSnapshot> {
  BufferUndoHost(this._undo) {
    _undo.registerHost<BufferSnapshot>(this);
  }

  final UndoController _undo;
  final _restorers = <BufferId, void Function(Object?)>{};
  final _pending = <BufferId, Object?>{};

  /// Routes [bufferId]'s snapshots to [restore], first adopting one that
  /// arrived while no view model was attached. Returns the detach callback.
  void Function() attach(BufferId bufferId, void Function(Object?) restore) {
    _restorers[bufferId] = restore;
    if (_pending.containsKey(bufferId)) restore(_pending.remove(bufferId));
    return () {
      if (_restorers[bufferId] == restore) _restorers.remove(bufferId);
    };
  }

  /// Records one content edit of [bufferId]. Edits sharing a [coalesceKey]
  /// coalesce only within the same buffer.
  void record(BufferId bufferId, Object? before, Object? after,
          {Object? coalesceKey}) =>
      _undo.record(UndoEntry<BufferSnapshot>(
        label: const UndoLabel('Edit'),
        snapshotBefore: BufferSnapshot(bufferId, before),
        snapshotAfter: BufferSnapshot(bufferId, after),
        coalesceKey: coalesceKey == null ? null : (bufferId, coalesceKey),
      ));

  @override
  void undo(BufferSnapshot snapshotBefore) => _publish(snapshotBefore);

  @override
  void redo(BufferSnapshot snapshotAfter) => _publish(snapshotAfter);

  void _publish(BufferSnapshot s) => switch (_restorers[s.bufferId]) {
        final restore? => restore(s.model),
        null => _pending[s.bufferId] = s.model,
      };
}

/// Makes a view model's content edits undoable: after [attachUndo], every
/// [publish] that changes the model records one entry; publishes passing an
/// equal `coalesceKey` in a row merge (typing into one field). Entries carry
/// whole models, so undo works on a view model rematerialized from
/// hibernation.
///
/// Focused text fields consume Ctrl+Z first; field-level undo stays
/// Flutter's. Reef binds no shell shortcut to [UndoController.undo] (W2).
mixin UndoableModel<M> on ViewModel<M> {
  (BufferUndoHost, BufferId)? _undoTarget;

  /// Records later publishes under [bufferId]. The latest view model attached
  /// for a buffer receives its undo and redo, including any that happened
  /// while the buffer had none. Call from the constructor or provider.
  void attachUndo(BufferUndoHost host, BufferId bufferId) {
    _undoTarget = (host, bufferId);
    registerDisposal(host.attach(bufferId, _restore));
  }

  @override
  void publish(M newModel, {Object? coalesceKey}) {
    final before = model;
    if (_undoTarget case (final host, final bufferId)?
        when newModel != before) {
      host.record(bufferId, before, newModel, coalesceKey: coalesceKey);
    }
    super.publish(newModel);
  }

  void _restore(Object? model) => super.publish(model as M);
}
