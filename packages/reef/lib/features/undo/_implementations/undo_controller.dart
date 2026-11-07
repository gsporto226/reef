import 'package:flutter/foundation.dart';
import 'package:formularium/features/localization/localizable_interface.dart';

/// One step on the undo timeline (spec §4). Data only.
class UndoEntry<S> {
  const UndoEntry({
    required this.label,
    required this.snapshotBefore,
    required this.snapshotAfter,
    this.coalesceKey,
  });

  /// For the audit log; menus render generic Undo/Redo.
  final ILocalizable label;
  final S snapshotBefore;
  final S snapshotAfter;

  /// Consecutive entries with an equal non-null key merge into one.
  final Object? coalesceKey;

  void _undo(Object host) => (host as UndoHost<S>).undo(snapshotBefore);
  void _redo(Object host) => (host as UndoHost<S>).redo(snapshotAfter);
}

/// Publishes a snapshot back into the state its subsystem owns.
abstract interface class UndoHost<S> {
  void undo(S snapshotBefore);
  void redo(S snapshotAfter);
}

/// The app's one undo timeline. Routes entries to hosts by snapshot type.
class UndoController {
  static const maxEntries = 64;

  final _hosts = <Type, Object>{};
  final _entries = <(Type, UndoEntry<dynamic>)>[];
  int _cursor = 0; // entries before the cursor are undoable
  final _canUndo = ValueNotifier(false);
  final _canRedo = ValueNotifier(false);

  ValueListenable<bool> get $canUndo => _canUndo;
  ValueListenable<bool> get $canRedo => _canRedo;

  void registerHost<S>(UndoHost<S> host) => _hosts[S] = host;

  void record<S>(UndoEntry<S> entry) {
    assert(_hosts.containsKey(S), 'No UndoHost registered for $S');
    _entries.removeRange(_cursor, _entries.length);
    final last = _entries.lastOrNull;
    if (last != null &&
        entry.coalesceKey != null &&
        last.$1 == S &&
        last.$2.coalesceKey == entry.coalesceKey) {
      _entries.last = (S, UndoEntry<S>(
        label: entry.label,
        snapshotBefore: last.$2.snapshotBefore as S,
        snapshotAfter: entry.snapshotAfter,
        coalesceKey: entry.coalesceKey,
      ));
    } else {
      _entries.add((S, entry));
      if (_entries.length > maxEntries) _entries.removeAt(0);
    }
    _cursor = _entries.length;
    _publish();
  }

  void undo() {
    if (_cursor == 0) return;
    final (type, entry) = _entries[--_cursor];
    entry._undo(_hosts[type]!);
    _publish();
  }

  void redo() {
    if (_cursor == _entries.length) return;
    final (type, entry) = _entries[_cursor++];
    entry._redo(_hosts[type]!);
    _publish();
  }

  void clear() {
    _entries.clear();
    _cursor = 0;
    _publish();
  }

  void _publish() {
    _canUndo.value = _cursor > 0;
    _canRedo.value = _cursor < _entries.length;
  }
}
