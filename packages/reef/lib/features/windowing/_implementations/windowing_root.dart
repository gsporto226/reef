import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:listenable_plus/listenable_plus.dart';
import 'package:reef/features/page_identity/_implementations/buffer_id.dart';
import 'package:reef/features/responsive/_implementations/screen_type_layout.dart';
import 'package:reef/features/windowing/_implementations/window_resize_handle.dart';
import 'package:reef/features/windowing/_implementations/windowing_controller.dart';
import 'package:reef/features/windowing/_implementations/windowing_delegate.dart';
import 'package:reef/features/windowing/_implementations/windowing_doc.dart';
import 'package:reef/features/windowing/_implementations/windowing_ids.dart';
import 'package:reef/features/windowing/_implementations/windowing_projection.dart';

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
/// [child]. Without a [child] it draws the focused shell as a
/// [ShellProjection]. While mounted, a [WindowingDelegate.interceptor],
/// [WindowingDelegate.openPolicy], [WindowingDelegate.focusPolicy] and
/// [WindowingDelegate.linkPolicy] replace the controller's; the previous ones come back on unmount.
class WindowingRoot extends StatefulWidget {
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
  State<WindowingRoot> createState() => _WindowingRootState();
}

class _WindowingRootState extends State<WindowingRoot> {
  WindowingInterceptor? _previous;
  late WindowingOpenPolicy _previousOpenPolicy;
  late WindowingFocusPolicy _previousFocusPolicy;
  late WindowingLinkPolicy _previousLinkPolicy;

  @override
  void initState() {
    super.initState();
    _install();
  }

  @override
  void didUpdateWidget(WindowingRoot old) {
    super.didUpdateWidget(old);
    if (old.controller == widget.controller &&
        old.delegate.interceptor == widget.delegate.interceptor &&
        old.delegate.openPolicy == widget.delegate.openPolicy &&
        old.delegate.focusPolicy == widget.delegate.focusPolicy &&
        old.delegate.linkPolicy == widget.delegate.linkPolicy) {
      return;
    }
    _uninstall(old.controller);
    _install();
  }

  @override
  void dispose() {
    _uninstall(widget.controller);
    super.dispose();
  }

  void _install() {
    _previous = widget.controller.interceptor;
    _previousOpenPolicy = widget.controller.openPolicy;
    _previousFocusPolicy = widget.controller.focusPolicy;
    _previousLinkPolicy = widget.controller.linkPolicy;
    if (widget.delegate.interceptor case final interceptor?) {
      widget.controller.interceptor = interceptor;
    }
    if (widget.delegate.openPolicy case final openPolicy?) {
      widget.controller.openPolicy = openPolicy;
    }
    if (widget.delegate.focusPolicy case final focusPolicy?) {
      widget.controller.focusPolicy = focusPolicy;
    }
    if (widget.delegate.linkPolicy case final linkPolicy?) {
      widget.controller.linkPolicy = linkPolicy;
    }
  }

  void _uninstall(WindowingController controller) => controller
    ..interceptor = _previous
    ..openPolicy = _previousOpenPolicy
    ..focusPolicy = _previousFocusPolicy
    ..linkPolicy = _previousLinkPolicy;

  @override
  Widget build(BuildContext context) {
    final WindowingRoot(:controller, :delegate, :child) = widget;
    return WindowingScope(
      controller: controller,
      bufferBuilder: widget.bufferBuilder,
      child: WindowingDelegateScope(
        delegate: delegate,
        child:
            child ??
            _Select<ShellId>(
              id: #focusedShell,
              selector: (doc) => doc.focusedShellId,
              builder: (context, shellId) => ShellProjection(shellId),
            ),
      ),
    );
  }
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

/// Renders the active tab of shell [shellId] under [surfaceBuilder], with
/// the shell's [FloatingLayer] over the whole surface.
class ShellHost extends StatelessWidget {
  const ShellHost(this.shellId, {super.key, this.surfaceBuilder});

  final ShellId shellId;
  final ShellSurfaceBuilder? surfaceBuilder;

  @override
  Widget build(BuildContext context) => _Select<TabId?>(
    id: shellId.value,
    selector: (doc) => doc.shells[shellId]?.activeTabId,
    builder: (context, tabId) {
      final canvas = tabId == null ? const SizedBox.expand() : TabCanvas(tabId);
      // The shell's floats cover the whole surface, chrome included.
      return Stack(
        fit: StackFit.expand,
        children: [
          surfaceBuilder?.call(context, shellId, canvas) ?? canvas,
          FloatingLayer(ShellScope(shellId)),
        ],
      );
    },
  );
}

/// Renders tab [tabId]'s windows through the delegate's
/// [WindowingDelegate.windowArrangement]; the default flex tree sizes branch
/// children by their ratios along the branch axis with a
/// [WindowResizeHandle] between them, a [WindowHost] per tree window. An
/// empty tab shows the delegate's [WindowingDelegate.emptyBuilder]. The
/// tab's [FloatingLayer] draws on top.
class TabCanvas extends StatelessWidget {
  const TabCanvas(this.tabId, {super.key});

  final TabId tabId;

  @override
  Widget build(BuildContext context) => _Select<WindowNode?>(
    id: tabId.value,
    selector: (doc) => doc.tabs[tabId]?.root,
    builder: (context, root) {
      final delegate = WindowingDelegateScope.of(context);
      return Stack(
        fit: StackFit.expand,
        children: [
          if (root == null)
            delegate.emptyBuilder(context, tabId)
          else
            _arranged(context, root),
          FloatingLayer(TabScope(tabId)),
        ],
      );
    },
  );

  Widget _arranged(BuildContext context, WindowNode root) {
    final arrangement =
        WindowingDelegateScope.of(context).windowArrangement ??
        (screenTypeOf(context) == ScreenType.desktop
            ? WindowArrangement.flexTree
            : WindowArrangement.focusedOnly);
    if (arrangement.builder case final builder?) return builder(context, tabId);
    if (!arrangement.focused) return _node(context, root);
    return _Select<WindowId?>(
      id: tabId.value,
      selector: (doc) => doc.tabs[tabId]?.activeWindowId,
      builder: (_, windowId) =>
          windowId == null ? const SizedBox.shrink() : WindowHost(windowId),
    );
  }

  Widget _node(BuildContext context, WindowNode node) => switch (node) {
    WindowLeaf(:final id) => WindowHost(id),
    WindowBranch(:final axis, :final children, :final ratios) => LayoutBuilder(
      builder: (context, constraints) => Flex(
        direction: axis,
        children: [
          for (final (i, child) in children.indexed) ...[
            if (i > 0)
              WindowResizeHandle(
                branch: node,
                index: i,
                extent: axis == Axis.horizontal
                    ? constraints.maxWidth
                    : constraints.maxHeight,
              ),
            Expanded(
              flex: (ratios[i] * 1000).round(),
              child: _node(context, child),
            ),
          ],
        ],
      ),
    ),
  };
}

/// Shows window [windowId]'s current buffer through the scope's buffer
/// builder inside the delegate's [WindowingDelegate.windowChrome], with the
/// window's [FloatingLayer] over it. A pointer down on it activates it (and
/// raises it, when floating) unless [activateOnPointer] is false. A window
/// always fills its slot, so its slot needs bounded constraints. A window is
/// drawn in one place at a time: its page sits under a global key, so two
/// hosts of one window would clash.
class WindowHost extends StatelessWidget {
  const WindowHost(this.windowId, {super.key, this.activateOnPointer = true});

  final WindowId windowId;

  /// Whether a pointer down activates the window; false for a window that
  /// never takes focus, like a navigation sidebar.
  final bool activateOnPointer;

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
        doc.windows[windowId]?.history.current.buffer,
        doc.tabs.values.any((t) => t.activeWindowId == windowId),
      ),
      builder: (context, selected) {
        final (buffer, active) = selected;
        if (buffer == null) return const SizedBox.shrink();
        final window = Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: activateOnPointer
              ? (_) => scope.controller.activateWindow(windowId)
              : null,
          child: _WindowIdScope(
            windowId: windowId,
            child: delegate.windowChrome(
              context,
              windowId,
              active,
              _transitioned(
                delegate.pageTransition(buffer),
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
          ),
        );
        return Stack(
          fit: StackFit.expand,
          children: [window, FloatingLayer(WindowScope(windowId))],
        );
      },
    );
  }
}

/// Runs [transition] into [page]; with none, the page swaps at once.
// ponytail: going back to a page still animating out puts its global key in
// the tree twice; key the outgoing pages apart if that bites.
Widget _transitioned(PageTransition? transition, Widget page) =>
    AnimatedSwitcher(
      duration: transition?.duration ?? Duration.zero,
      transitionBuilder: transition?.builder ?? _noTransition,
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [...previous, ?current],
      ),
      child: page,
    );

Widget _noTransition(Widget child, Animation<double> _) => child;

/// The floating windows of [scope], bottom to top by z-index, each a
/// [WindowHost] wrapped by the delegate's [WindowingDelegate.floating].
/// Hosted by [ShellHost], [TabCanvas] and [WindowHost] for their own scope.
class FloatingLayer extends StatelessWidget {
  const FloatingLayer(this.scope, {super.key});

  final FloatScope scope;

  @override
  Widget build(BuildContext context) => _Select<List<(WindowId, Rect?)>>(
    id: scope,
    equals: listEquals,
    selector: (doc) => [
      for (final MapEntry(:key, :value)
          in doc.floating.entries.where((e) => e.value.scope == scope).toList()
            ..sort((a, b) => a.value.zIndex.compareTo(b.value.zIndex)))
        (key, value.geometry),
    ],
    builder: (context, floats) {
      final delegate = WindowingDelegateScope.of(context);
      return Stack(
        children: [
          for (final (i, (id, geometry)) in floats.indexed)
            Positioned.fill(
              key: ValueKey(id.value),
              child: delegate.floating(
                context,
                id,
                geometry,
                i,
                WindowHost(id),
              ),
            ),
        ],
      );
    },
  );
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
/// value equality, or by [equals] when given. [id] names the selection: a
/// new id selects afresh.
class _Select<T> extends StatefulWidget {
  const _Select({
    required this.id,
    required this.selector,
    required this.builder,
    this.equals,
  });

  final Object id;
  final bool Function(T previous, T next)? equals;
  final T Function(WindowingDoc doc) selector;
  final Widget Function(BuildContext context, T value) builder;

  @override
  State<_Select<T>> createState() => _SelectState<T>();
}

class _SelectState<T> extends State<_Select<T>> {
  ValueListenable<WindowingDoc>? _doc;
  late MappedValueListenable<T, WindowingDoc> _mapped;
  late DistinctValueNotifier<T> _selection;

  void _listen(ValueListenable<WindowingDoc> doc) {
    if (_doc != null) _dispose();
    _doc = doc;
    _mapped = MappedValueListenable(
      widget.selector(doc.value),
      mapper: widget.selector,
      source: doc,
    );
    _selection = DistinctValueNotifier(
      _mapped.value,
      source: _mapped,
      equals: widget.equals,
    );
  }

  void _dispose() {
    _selection.dispose();
    _mapped.dispose();
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
    _dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<T>(
    valueListenable: _selection,
    builder: (context, value, _) => widget.builder(context, value),
  );
}
