import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:reef/features/undo/_implementations/undo_controller.dart';
import 'package:reef/features/windowing/_implementations/windowing_ids.dart';
import 'package:reef/features/windowing/_implementations/windowing_root.dart';

/// Closes the active window.
class CloseWindowIntent extends Intent {
  const CloseWindowIntent();
}

/// Splits the active window along [axis].
class SplitWindowIntent extends Intent {
  const SplitWindowIntent(this.axis);

  final Axis axis;
}

/// Steps the active window back in its history.
class WindowBackIntent extends Intent {
  const WindowBackIntent();
}

/// Steps the active window forward in its history.
class WindowForwardIntent extends Intent {
  const WindowForwardIntent();
}

/// Opt-in keyboard commands for the windowing units, built on Flutter's
/// [Shortcuts] and [Actions]. Place it below a [WindowingRoot]. Window
/// commands act on the focused shell's active tab's active window and do
/// nothing without one. Undo and redo use Flutter's [UndoTextIntent] and
/// [RedoTextIntent], so a focused text field handles them first; otherwise
/// they go to [undo] while it can undo or redo.
class WindowingShortcuts extends StatelessWidget {
  const WindowingShortcuts({
    super.key,
    required this.undo,
    this.bindings,
    required this.child,
  });

  final UndoController undo;

  /// Replaces [defaultBindings]; spread them in to extend instead.
  final Map<ShortcutActivator, Intent>? bindings;
  final Widget child;

  /// Command on Apple platforms, Control elsewhere.
  static LogicalKeyboardKey get primaryModifier => _apple
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;

  static bool get _apple => switch (defaultTargetPlatform) {
        TargetPlatform.macOS || TargetPlatform.iOS => true,
        _ => false,
      };

  static SingleActivator _primary(LogicalKeyboardKey key,
          {bool shift = false}) =>
      SingleActivator(key, control: !_apple, meta: _apple, shift: shift);

  /// Primary+W close, Primary+\ split side by side, Primary+Shift+\ split
  /// stacked, Alt+Left back, Alt+Right forward, Primary+Z undo,
  /// Primary+Shift+Z and Primary+Y redo.
  static Map<ShortcutActivator, Intent> get defaultBindings => {
        _primary(LogicalKeyboardKey.keyW): const CloseWindowIntent(),
        _primary(LogicalKeyboardKey.backslash):
            const SplitWindowIntent(Axis.horizontal),
        _primary(LogicalKeyboardKey.backslash, shift: true):
            const SplitWindowIntent(Axis.vertical),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true):
            const WindowBackIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true):
            const WindowForwardIntent(),
        _primary(LogicalKeyboardKey.keyZ):
            const UndoTextIntent(SelectionChangedCause.keyboard),
        _primary(LogicalKeyboardKey.keyZ, shift: true):
            const RedoTextIntent(SelectionChangedCause.keyboard),
        _primary(LogicalKeyboardKey.keyY):
            const RedoTextIntent(SelectionChangedCause.keyboard),
      };

  @override
  Widget build(BuildContext context) {
    final c = WindowingScope.of(context).controller;
    WindowId? active() {
      final doc = c.doc.value;
      final tabId = doc.shells[doc.focusedShellId]?.activeTabId;
      return doc.tabs[tabId]?.activeWindowId;
    }

    return Shortcuts(
      shortcuts: bindings ?? defaultBindings,
      child: Actions(
        actions: {
          CloseWindowIntent: _WindowAction<CloseWindowIntent>(
              active, (w, _) => c.closeWindow(w)),
          SplitWindowIntent: _WindowAction<SplitWindowIntent>(
              active, (w, i) => c.splitWindow(w, axis: i.axis)),
          WindowBackIntent:
              _WindowAction<WindowBackIntent>(active, (w, _) => c.popBuffer(w)),
          WindowForwardIntent: _WindowAction<WindowForwardIntent>(
              active, (w, _) => c.navigateForward(w)),
          UndoTextIntent: _UndoAction<UndoTextIntent>(undo.$canUndo, undo.undo),
          RedoTextIntent: _UndoAction<RedoTextIntent>(undo.$canRedo, undo.redo),
        },
        child: Focus(autofocus: true, child: child),
      ),
    );
  }
}

class _WindowAction<T extends Intent> extends Action<T> {
  _WindowAction(this.active, this.run);

  final WindowId? Function() active;
  final void Function(WindowId window, T intent) run;

  @override
  bool isEnabled(T intent) => active() != null;

  @override
  void invoke(T intent) => run(active()!, intent);
}

class _UndoAction<T extends Intent> extends Action<T> {
  _UndoAction(this.can, this.run);

  final ValueListenable<bool> can;
  final VoidCallback run;

  // A focused text field's own undo is overridable; [callingAction] is that
  // default, so defer to it to leave the field its keys.
  @override
  bool isEnabled(T intent) => callingAction?.isEnabled(intent) ?? can.value;

  @override
  void invoke(T intent) =>
      callingAction == null ? run() : callingAction!.invoke(intent);
}

/// Opt-in: binds system back (such as Android's back gesture) to
/// [WindowingController.back] of the [WindowingScope] above it, so platform
/// back equals window back. Back left unhandled goes on to the platform.
class WindowingSystemBack extends StatefulWidget {
  const WindowingSystemBack({super.key, required this.child});

  final Widget child;

  @override
  State<WindowingSystemBack> createState() => _WindowingSystemBackState();
}

class _WindowingSystemBackState extends State<WindowingSystemBack>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<bool> didPopRoute() async =>
      WindowingScope.of(context).controller.back();

  @override
  Widget build(BuildContext context) => widget.child;
}
