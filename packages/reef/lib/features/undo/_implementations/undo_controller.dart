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

  void _undo(Object host) => (host as UndoHost<S>).undo(this);
  void _redo(Object host) => (host as UndoHost<S>).redo(this);
}

/// A fixed, untranslated [UndoEntry.label].
class UndoLabel implements ILocalizable {
  const UndoLabel(this._text);

  final String _text;

  @override
  String localize() => _text;
}

/// Publishes an entry back into the state its subsystem owns: [undo]
/// reverses it, [redo] replays it.
abstract interface class UndoHost<S> {
  void undo(UndoEntry<S> entry);
  void redo(UndoEntry<S> entry);
}

/// The app's one undo timeline. Routes entries to hosts by snapshot type.
class UndoController {
  static const maxEntries = 64;

  final _hosts = <Type, Object>{};
  final _entries = <(Type, UndoEntry<dynamic>)>[];
  int _cursor = 0; // entries before the cursor are undoable
  bool _sealed = false;
  final _canUndo = ValueNotifier(false);
  final _canRedo = ValueNotifier(false);

  ValueListenable<bool> get $canUndo => _canUndo;
  ValueListenable<bool> get $canRedo => _canRedo;

  /// Every entry's label, oldest first, redo tail included (audit log).
  List<ILocalizable> get labels => [for (final (_, e) in _entries) e.label];

  void registerHost<S>(UndoHost<S> host) => _hosts[S] = host;

  void record<S>(UndoEntry<S> entry) {
    assert(_hosts.containsKey(S), 'No UndoHost registered for $S');
    // Coalesce only onto the newest entry: after an undo, the entry before
    // the cursor is a finished step; so is a sealed one.
    final last =
        !_sealed && _cursor == _entries.length ? _entries.lastOrNull : null;
    _sealed = false;
    _entries.removeRange(_cursor, _entries.length);
    if (last != null &&
        entry.coalesceKey != null &&
        last.$1 == S &&
        last.$2.coalesceKey == entry.coalesceKey) {
      final before = last.$2.snapshotBefore as S;
      if (before == entry.snapshotAfter) {
        _entries.removeLast(); // the merged step changes nothing
      } else {
        _entries.last = (
          S,
          UndoEntry<S>(
            label: entry.label,
            snapshotBefore: before,
            snapshotAfter: entry.snapshotAfter,
            coalesceKey: entry.coalesceKey,
          ),
        );
      }
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

  /// Ends the current coalescing run: the next entry starts a new step.
  void sealCoalescing() => _sealed = true;

  /// Drops every entry of snapshot type [S], keeping the rest in order.
  void clearHost<S>() {
    _cursor = _entries.take(_cursor).where((e) => e.$1 != S).length;
    _entries.removeWhere((e) => e.$1 == S);
    _publish();
  }

  void _publish() {
    _canUndo.value = _cursor > 0;
    _canRedo.value = _cursor < _entries.length;
  }
}
