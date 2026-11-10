import 'package:flutter/widgets.dart';
import 'package:formularium/features/localization/localizable_interface.dart';
import 'package:reef/features/page_identity/_implementations/buffer_id.dart';
import 'package:reef/features/windowing/_implementations/window_resize_handle.dart';
import 'package:reef/features/windowing/_implementations/windowing_controller.dart';
import 'package:reef/features/windowing/_implementations/windowing_ids.dart';
import 'package:reef/features/windowing/_implementations/windowing_root.dart';

/// Wraps window [windowId]'s [page]; [focused] while it is its tab's active
/// window.
typedef WindowChromeBuilder = Widget Function(
  BuildContext context,
  WindowId windowId,
  bool focused,
  Widget page,
);

/// Draws tab [tabId] while it holds no windows.
typedef EmptyTabBuilder = Widget Function(BuildContext context, TabId tabId);

/// Draws window [windowId] while the page for [buffer] is not ready yet (the
/// buffer builder returned null).
typedef HibernatingBuilder = Widget Function(
  BuildContext context,
  WindowId windowId,
  BufferId buffer,
);

/// Draws shell [shellId]'s tab strip.
typedef TabStripBuilder = Widget Function(
  BuildContext context,
  ShellId shellId,
);

/// Draws the divider of a [WindowResizeHandle] between children laid out
/// along [axis].
typedef SplitterBuilder = Widget Function(BuildContext context, Axis axis);

/// Places floating window [windowId] (the [window] widget) in its scope's
/// [FloatingLayer], which fills the scope's container. [geometry] is the
/// doc's advisory hint, null until moved; [index] is the window's place in
/// the scope, bottom first.
typedef FloatingBuilder = Widget Function(
  BuildContext context,
  WindowId windowId,
  Rect? geometry,
  int index,
  Widget window,
);

/// How a tab's windows show: the window tree as nested flexes ([flexTree]),
/// or a [custom] builder given the tab id.
@immutable
final class WindowArrangement {
  const WindowArrangement._(this.builder);

  /// A custom arrangement, e.g. a window carousel. The windows' pages are
  /// drawn by placing a [WindowHost] per window.
  const WindowArrangement.custom(
    Widget Function(BuildContext context, TabId tabId) this.builder,
  );

  /// The window tree as nested flexes sized by their ratios, a
  /// [WindowResizeHandle] between the children of every branch.
  static const flexTree = WindowArrangement._(null);

  /// Null for [flexTree].
  final Widget Function(BuildContext context, TabId tabId)? builder;
}

/// Maps windowing entities to localizable labels for strips and headers.
/// Every mapping returns null (no label) unless given.
@immutable
class WindowingLabels {
  const WindowingLabels({
    this.shell = _none,
    this.tab = _none,
    this.window = _none,
    this.buffer = _none,
  });

  final ILocalizable? Function(ShellId shellId) shell;
  final ILocalizable? Function(TabId tabId) tab;
  final ILocalizable? Function(WindowId windowId) window;
  final ILocalizable? Function(BufferId buffer) buffer;

  static ILocalizable? _none(Object? _) => null;
}

/// The app's visual hooks for the windowing units, each with a default.
/// Handed to [WindowingRoot]; [WindowingDelegateScope] overrides it for a
/// subtree.
@immutable
class WindowingDelegate {
  const WindowingDelegate({
    this.windowChrome = _focusBorder,
    this.emptyBuilder = _blankTab,
    this.hibernatingBuilder = _blankWindow,
    this.labels = const WindowingLabels(),
    this.windowArrangement = WindowArrangement.flexTree,
    this.tabStrip = _defaultTabStrip,
    this.splitter = _thinDivider,
    this.floating = _floatingFrame,
    this.interceptor,
  });

  /// Default: a border on the focused window only.
  final WindowChromeBuilder windowChrome;

  /// Default: blank.
  final EmptyTabBuilder emptyBuilder;

  /// Default: blank.
  final HibernatingBuilder hibernatingBuilder;

  /// Default: no labels.
  final WindowingLabels labels;

  /// Default: [WindowArrangement.flexTree].
  final WindowArrangement windowArrangement;

  /// Default: a plain row of tab names over [TabStripSlot]; a tap activates,
  /// the `×` closes.
  final TabStripBuilder tabStrip;

  /// Default: a 1px grey line centred in an 8px strip.
  final SplitterBuilder splitter;

  /// Default: at the hint, else cascading from the top left at 280x160,
  /// clamped to the container; a drag dispatches [MoveFloating], one undo
  /// step per drag.
  final FloatingBuilder floating;

  /// Handed to the controller by [WindowingRoot]. Default: none, every
  /// command applies.
  final WindowingInterceptor? interceptor;

  WindowingDelegate copyWith({
    WindowChromeBuilder? windowChrome,
    EmptyTabBuilder? emptyBuilder,
    HibernatingBuilder? hibernatingBuilder,
    WindowingLabels? labels,
    WindowArrangement? windowArrangement,
    TabStripBuilder? tabStrip,
    SplitterBuilder? splitter,
    FloatingBuilder? floating,
    WindowingInterceptor? interceptor,
  }) => WindowingDelegate(
    windowChrome: windowChrome ?? this.windowChrome,
    emptyBuilder: emptyBuilder ?? this.emptyBuilder,
    hibernatingBuilder: hibernatingBuilder ?? this.hibernatingBuilder,
    labels: labels ?? this.labels,
    windowArrangement: windowArrangement ?? this.windowArrangement,
    tabStrip: tabStrip ?? this.tabStrip,
    splitter: splitter ?? this.splitter,
    floating: floating ?? this.floating,
    interceptor: interceptor ?? this.interceptor,
  );

  static Widget _floatingFrame(
    BuildContext _,
    WindowId windowId,
    Rect? geometry,
    int index,
    Widget window,
  ) => _FloatingFrame(windowId, geometry, index, window);

  static Widget _thinDivider(BuildContext _, Axis axis) => SizedBox(
    width: axis == Axis.horizontal ? 8 : null,
    height: axis == Axis.horizontal ? null : 8,
    child: Center(
      child: Container(
        width: axis == Axis.horizontal ? 1 : null,
        height: axis == Axis.horizontal ? null : 1,
        color: const Color(0xFFBDBDBD),
      ),
    ),
  );

  static Widget _focusBorder(
    BuildContext _,
    WindowId _,
    bool focused,
    Widget page,
  ) => DecoratedBox(
    position: DecorationPosition.foreground,
    decoration: BoxDecoration(
      border: focused
          ? Border.all(color: const Color(0xFF2196F3), width: 2)
          : null,
    ),
    child: page,
  );

  static Widget _blankTab(BuildContext _, TabId _) => const SizedBox.expand();

  static Widget _blankWindow(BuildContext _, WindowId _, BufferId _) =>
      const SizedBox.expand();

  static Widget _defaultTabStrip(BuildContext context, ShellId shellId) =>
      TabStripSlot(
        shellId,
        builder: (context, strip) {
          final labels = WindowingDelegateScope.of(context).labels;
          return Row(
            children: [
              for (final (i, id) in strip.tabIds.indexed) ...[
                GestureDetector(
                  onTap: () => strip.activate(id),
                  child: Text(
                    labels.tab(id)?.localize() ?? 'Tab ${i + 1}',
                    style: TextStyle(
                      fontWeight: id == strip.activeTabId
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
                GestureDetector(
                  key: ValueKey('close ${id.value}'),
                  onTap: () => strip.close(id),
                  child: const Text(' × '),
                ),
              ],
            ],
          );
        },
      );
}

/// Overrides the [WindowingDelegate] for the units in [child].
class WindowingDelegateScope extends InheritedWidget {
  const WindowingDelegateScope({
    super.key,
    required this.delegate,
    required super.child,
  });

  final WindowingDelegate delegate;

  /// The nearest delegate, or the default one when no scope is above
  /// [context].
  static WindowingDelegate of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<WindowingDelegateScope>()
          ?.delegate ??
      const WindowingDelegate();

  @override
  bool updateShouldNotify(WindowingDelegateScope oldWidget) =>
      delegate != oldWidget.delegate;
}

class _FloatingFrame extends StatefulWidget {
  const _FloatingFrame(this.windowId, this.geometry, this.index, this.window);

  final WindowId windowId;
  final Rect? geometry;
  final int index;
  final Widget window;

  @override
  State<_FloatingFrame> createState() => _FloatingFrameState();
}

class _FloatingFrameState extends State<_FloatingFrame> {
  // The rect at drag start plus the offset since then, so updates landing
  // in one frame never stack on a stale rect.
  Rect _rect = Rect.zero;
  Rect _start = Rect.zero;
  Offset _offset = Offset.zero;
  Size _area = Size.zero;

  Rect _clamp(Rect r) => Rect.fromLTWH(
    r.left.clamp(0, (_area.width - r.width).clamp(0, double.infinity)),
    r.top.clamp(0, (_area.height - r.height).clamp(0, double.infinity)),
    r.width,
    r.height,
  );

  void _move(DragUpdateDetails d) {
    _offset += d.delta;
    WindowingScope.of(context).controller.moveFloating(
      widget.windowId,
      _clamp(_start.shift(_offset)),
      coalesceKey: 'move:${widget.windowId.value}',
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      _area = box.biggest;
      final cascade = 40 + 32.0 * widget.index;
      _rect = _clamp(
        widget.geometry ?? Rect.fromLTWH(cascade, cascade, 280, 160),
      );
      return Stack(
        children: [
          Positioned.fromRect(
            rect: _rect,
            child: GestureDetector(
              onPanStart: (_) {
                _start = _rect;
                _offset = Offset.zero;
              },
              onPanUpdate: _move,
              onPanEnd: (_) =>
                  WindowingScope.of(context).controller.sealCoalescing(),
              child: widget.window,
            ),
          ),
        ],
      );
    },
  );
}
