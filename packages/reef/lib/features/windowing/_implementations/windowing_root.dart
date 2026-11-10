import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:listenable_plus/listenable_plus.dart';
import 'package:reef/features/page_identity/_implementations/buffer_id.dart';
import 'package:reef/features/windowing/_implementations/window_resize_handle.dart';
import 'package:reef/features/windowing/_implementations/windowing_controller.dart';
import 'package:reef/features/windowing/_implementations/windowing_delegate.dart';
import 'package:reef/features/windowing/_implementations/windowing_doc.dart';
import 'package:reef/features/windowing/_implementations/windowing_ids.dart';

/// Turns a buffer id into the page that shows it: the app's kind-to-page
/// mapping. Returns null while the buffer is not ready yet; the window then
/// shows the delegate's [WindowingDelegate.hibernatingBuilder].
typedef BufferBuilder = Widget? Function(BuildContext context, BufferId buffer);

/// Wraps a shell's active tab canvas in the app's chrome (title bar, tab
/// strip).
typedef ShellSurfaceBuilder = Widget Function(
  BuildContext context,
  ShellId shellId,
  Widget canvas,
);

/// The top of a windowing UI: installs [WindowingScope] and [delegate] over
/// [child]. Without
/// a [child] it draws the focused shell through a [ShellHost].
class WindowingRoot extends StatelessWidget {
  const WindowingRoot({
    super.key,
    required this.controller,
    required this.bufferBuilder,
    this.delegate = const WindowingDelegate(),
    this.child,
  });

  final WindowingController controller;
  final BufferBuilder bufferBuilder;
  final WindowingDelegate delegate;
  final Widget? child;

  @override
  Widget build(BuildContext context) => WindowingScope(
    controller: controller,
    bufferBuilder: bufferBuilder,
    child: WindowingDelegateScope(
      delegate: delegate,
      child:
          child ??
          _Select<ShellId>(
            id: #focusedShell,
            selector: (doc) => doc.focusedShellId,
            builder: (_, shellId) => ShellHost(shellId),
          ),
    ),
  );
}

/// Inherited lookup of the [controller] and [bufferBuilder] for every
/// windowing unit below a [WindowingRoot].
class WindowingScope extends InheritedWidget {
  const WindowingScope({
    super.key,
    required this.controller,
    required this.bufferBuilder,
    required super.child,
  });

  final WindowingController controller;
  final BufferBuilder bufferBuilder;

  /// The nearest scope; throws when no [WindowingRoot] is above [context].
  static WindowingScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<WindowingScope>();
    if (scope != null) return scope;
    throw FlutterError(
      'No WindowingRoot found above ${context.widget}.\n'
      'Windowing units read the controller and buffer builder from a '
      'WindowingRoot: place one above this widget.',
    );
  }

  @override
  bool updateShouldNotify(WindowingScope oldWidget) =>
      controller != oldWidget.controller ||
      bufferBuilder != oldWidget.bufferBuilder;
}

/// Renders the active tab of shell [shellId] under [surfaceBuilder].
class ShellHost extends StatelessWidget {
  const ShellHost(this.shellId, {super.key, this.surfaceBuilder});

  final ShellId shellId;
  final ShellSurfaceBuilder? surfaceBuilder;

  @override
  Widget build(BuildContext context) => _Select<TabId?>(
    id: shellId.value,
    selector: (doc) => doc.shells[shellId]?.activeTabId,
    builder: (context, tabId) {
      final canvas = tabId == null ? const SizedBox.shrink() : TabCanvas(tabId);
      return surfaceBuilder?.call(context, shellId, canvas) ?? canvas;
    },
  );
}

/// Renders tab [tabId]'s windows through the delegate's
/// [WindowingDelegate.windowArrangement]; the default flex tree sizes branch
/// children by their ratios along the branch axis with a
/// [WindowResizeHandle] between them, a [WindowHost] per tree window. An empty tab shows the delegate's [WindowingDelegate.emptyBuilder].
class TabCanvas extends StatelessWidget {
  const TabCanvas(this.tabId, {super.key});

  final TabId tabId;

  @override
  Widget build(BuildContext context) => _Select<WindowNode?>(
    id: tabId.value,
    selector: (doc) => doc.tabs[tabId]?.root,
    builder: (context, root) {
      final delegate = WindowingDelegateScope.of(context);
      if (root == null) return delegate.emptyBuilder(context, tabId);
      return delegate.windowArrangement.builder?.call(context, tabId) ??
          _node(context, root);
    },
  );

  Widget _node(BuildContext context, WindowNode node) => switch (node) {
    WindowLeaf(:final id) => WindowHost(id),
    WindowBranch(:final axis, :final children, :final ratios) => Flex(
      direction: axis,
      children: [
        for (final (i, child) in children.indexed) ...[
          if (i > 0) WindowResizeHandle(branch: node, index: i),
          Expanded(
            flex: (ratios[i] * 1000).round(),
            child: _node(context, child),
          ),
        ],
      ],
    ),
  };
}

/// Shows window [windowId]'s current buffer through the scope's buffer
/// builder inside the delegate's [WindowingDelegate.windowChrome]. A pointer
/// down on it activates it.
class WindowHost extends StatelessWidget {
  const WindowHost(this.windowId, {super.key});

  final WindowId windowId;

  /// The window whose page encloses [context].
  static WindowId of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_WindowIdScope>()!.windowId;

  @override
  Widget build(BuildContext context) {
    final scope = WindowingScope.of(context);
    final delegate = WindowingDelegateScope.of(context);
    return _Select<(BufferId?, bool)>(
      id: windowId.value,
      selector: (doc) => (
        doc.windows[windowId]?.history.current,
        doc.tabs.values.any((t) => t.activeWindowId == windowId),
      ),
      builder: (context, selected) {
        final (buffer, active) = selected;
        if (buffer == null) return const SizedBox.shrink();
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => scope.controller.activateWindow(windowId),
          child: _WindowIdScope(
            windowId: windowId,
            child: delegate.windowChrome(
              context,
              windowId,
              active,
              // Global so a layout change around the window reparents its
              // page instead of remounting it.
              KeyedSubtree(
                key: _PageKey(windowId, buffer),
                child: Builder(
                  builder: (context) =>
                      scope.bufferBuilder(context, buffer) ??
                      delegate.hibernatingBuilder(context, windowId, buffer),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// What a [TabStripSlot] hands its builder: a shell's tabs and the intents
/// over them.
class TabStripState {
  const TabStripState({
    required this.tabIds,
    required this.activeTabId,
    required this.activate,
    required this.close,
    required this.reorder,
  });

  final List<TabId> tabIds;
  final TabId activeTabId;
  final void Function(TabId tabId) activate;
  final void Function(TabId tabId) close;

  /// Moves a tab to `index` within the shell.
  final void Function(TabId tabId, int index) reorder;
}

/// Headless tab strip of shell [shellId]: [builder] draws it from a
/// [TabStripState].
class TabStripSlot extends StatelessWidget {
  const TabStripSlot(this.shellId, {super.key, required this.builder});

  final ShellId shellId;
  final Widget Function(BuildContext context, TabStripState strip) builder;

  @override
  Widget build(BuildContext context) {
    final c = WindowingScope.of(context).controller;
    return _Select<ShellState?>(
      id: shellId.value,
      selector: (doc) => doc.shells[shellId],
      builder: (context, shell) => shell == null
          ? const SizedBox.shrink()
          : builder(
              context,
              TabStripState(
                tabIds: shell.tabIds,
                activeTabId: shell.activeTabId,
                activate: c.activateTab,
                close: c.closeTab,
                reorder: (tabId, index) =>
                    c.moveTab(tabId, shellId: shellId, index: index),
              ),
            ),
    );
  }
}

class _WindowIdScope extends InheritedWidget {
  const _WindowIdScope({required this.windowId, required super.child});

  final WindowId windowId;

  @override
  bool updateShouldNotify(_WindowIdScope oldWidget) =>
      windowId != oldWidget.windowId;
}

class _PageKey extends GlobalKey {
  const _PageKey(this.windowId, this.buffer) : super.constructor();

  final WindowId windowId;
  final BufferId buffer;

  @override
  bool operator ==(Object other) =>
      other is _PageKey && other.windowId == windowId && other.buffer == buffer;

  @override
  int get hashCode => Object.hash(windowId, buffer);
}

/// Rebuilds [builder] only when [selector]'s value over the doc changes by
/// value equality. [id] names the selection: a new id selects afresh.
class _Select<T> extends StatefulWidget {
  const _Select({
    required this.id,
    required this.selector,
    required this.builder,
  });

  final Object id;
  final T Function(WindowingDoc doc) selector;
  final Widget Function(BuildContext context, T value) builder;

  @override
  State<_Select<T>> createState() => _SelectState<T>();
}

class _SelectState<T> extends State<_Select<T>> {
  ValueListenable<WindowingDoc>? _doc;
  late MappedValueListenable<T, WindowingDoc> _selection;

  void _listen(ValueListenable<WindowingDoc> doc) {
    if (_doc != null) _selection.dispose();
    _doc = doc;
    _selection = MappedValueListenable(
      widget.selector(doc.value),
      mapper: widget.selector,
      source: doc,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final doc = WindowingScope.of(context).controller.doc;
    if (doc != _doc) _listen(doc);
  }

  @override
  void didUpdateWidget(_Select<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) _listen(_doc!);
  }

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<T>(
    valueListenable: _selection,
    builder: (context, value, _) => widget.builder(context, value),
  );
}
