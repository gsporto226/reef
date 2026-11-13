import 'package:flutter/foundation.dart';
import 'package:reef/features/windowing/_implementations/windowing_doc.dart';
import 'package:reef/features/windowing/_implementations/windowing_ids.dart';

/// The units one change touched (ADR 0009): each shell, tab, window (with
/// its history) and floating entry that differs between two docs, as its
/// value before and after (null: absent), plus the focused shell.
@immutable
class WindowingPatch {
  const WindowingPatch._(
    this._shells,
    this._tabs,
    this._windows,
    this._floating,
    this._focus,
  );

  /// The units that differ between [before] and [after].
  factory WindowingPatch.diff(WindowingDoc before, WindowingDoc after) =>
      WindowingPatch._(
        _delta(before.shells, after.shells),
        _delta(before.tabs, after.tabs),
        _delta(before.windows, after.windows),
        _delta(before.floating, after.floating),
        before.focusedShellId == after.focusedShellId
            ? null
            : (before.focusedShellId, after.focusedShellId),
      );

  final Map<ShellId, (ShellState?, ShellState?)> _shells;
  final Map<TabId, (TabState?, TabState?)> _tabs;
  final Map<WindowId, (WindowState?, WindowState?)> _windows;
  final Map<WindowId, (FloatingState?, FloatingState?)> _floating;
  final (ShellId, ShellId)? _focus;

  /// The patch that undoes this one.
  WindowingPatch get reversed => WindowingPatch._(
    _swap(_shells),
    _swap(_tabs),
    _swap(_windows),
    _swap(_floating),
    _focus.let((f) => (f.$2, f.$1)),
  );

  /// [doc] with every touched unit set to its "after" value and every other
  /// unit kept. Null on conflict: a touched unit's presence in [doc] differs
  /// from its "before" (a later change removed or added it), or the result
  /// breaks a doc invariant (a later change moved a parent a unit needs).
  WindowingDoc? apply(WindowingDoc doc) {
    if (!_present(doc.shells, _shells) ||
        !_present(doc.tabs, _tabs) ||
        !_present(doc.windows, _windows) ||
        !_present(doc.floating, _floating)) {
      return null;
    }
    final next = WindowingDoc(
      shells: _set(doc.shells, _shells),
      tabs: _set(doc.tabs, _tabs),
      windows: _set(doc.windows, _windows),
      floating: _set(doc.floating, _floating),
      focusedShellId: _focus?.$2 ?? doc.focusedShellId,
    );
    return next.isValid ? next : null;
  }
}

Map<K, (V?, V?)> _delta<K, V>(Map<K, V> before, Map<K, V> after) => {
  for (final k in {...before.keys, ...after.keys})
    if (before[k] != after[k]) k: (before[k], after[k]),
};

bool _present<K, V>(Map<K, V> doc, Map<K, (V?, V?)> d) =>
    d.entries.every((e) => doc.containsKey(e.key) == (e.value.$1 != null));

Map<K, (V?, V?)> _swap<K, V>(Map<K, (V?, V?)> d) =>
    d.map((k, v) => MapEntry(k, (v.$2, v.$1)));

/// [doc] with [d]'s "after" values, keeping [doc]'s key order.
Map<K, V> _set<K, V extends Object>(Map<K, V> doc, Map<K, (V?, V?)> d) => {
  for (final MapEntry(:key, :value) in doc.entries)
    if (!d.containsKey(key)) key: value else key: ?d[key]!.$2,
  for (final MapEntry(:key, :value) in d.entries)
    if (!doc.containsKey(key)) key: ?value.$2,
};

extension<T extends Object> on T? {
  R? let<R>(R Function(T) f) => switch (this) {
    final v? => f(v),
    _ => null,
  };
}
