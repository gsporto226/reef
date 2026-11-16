import 'dart:ui' show FlutterView;

import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:reef/features/windowing/_implementations/windowing_controller.dart';
import 'package:reef/features/windowing/_implementations/windowing_doc.dart';
import 'package:reef/features/windowing/_implementations/windowing_ids.dart';
import 'package:reef/features/windowing/_implementations/windowing_root.dart';

/// What a [DockSource] drags (ADR 0012).
@immutable
sealed class Dockable {
  const Dockable();
}

class TabDockable extends Dockable {
  const TabDockable(this.tabId);

  final TabId tabId;
}

class WindowDockable extends Dockable {
  const WindowDockable(this.windowId);

  final WindowId windowId;
}

/// Where a [DockArea] lands a drop.
@immutable
sealed class DockTarget {
  const DockTarget();
}

/// Slot [index] of [shellId]'s tab strip: before the tab now at [index], or
/// after the last tab when it equals the tab count.
class TabStripTarget extends DockTarget {
  const TabStripTarget(this.shellId, this.index);

  final ShellId shellId;
  final int index;
}

/// Side [edge] of tree window [windowId]: the drop splits it there.
class WindowEdgeTarget extends DockTarget {
  const WindowEdgeTarget(this.windowId, this.edge);

  final WindowId windowId;
  final AxisDirection edge;
}

/// The centre of window [windowId]: a dropped window's page is pushed onto
/// it, like a link dropped on a page.
class WindowCentreTarget extends DockTarget {
  const WindowCentreTarget(this.windowId);

  final WindowId windowId;
}

/// Empty tab [tabId]: a dropped window becomes its root.
class EmptyTabTarget extends DockTarget {
  const EmptyTabTarget(this.tabId);

  final TabId tabId;
}

/// The floating layer of [scope]: a dropped tree window floats there.
class FloatTarget extends DockTarget {
  const FloatTarget(this.scope);

  final FloatScope scope;
}

/// The batch dropping [dockable] on [target] dispatches against [doc]: only
/// existing commands, so the interceptor sees it and it is one undo step.
/// Empty for a self-drop, a no-op or a pair that does not dock (a tab off
/// a tab strip, a floating window onto a float layer).
List<WindowingCommand> dockCommands(
  WindowingDoc doc,
  Dockable dockable,
  DockTarget target,
) => switch ((dockable, target)) {
  (TabDockable(:final tabId), TabStripTarget(:final shellId, :final index)) =>
    _tabToStrip(doc, tabId, shellId, index),
  (TabDockable(), _) => const [],
  (WindowDockable(:final windowId), _)
      when !doc.windows.containsKey(windowId) =>
    const [],
  (
    WindowDockable(:final windowId),
    TabStripTarget(:final shellId, :final index),
  )
      when doc.shells.containsKey(shellId) =>
    () {
      final tab = TabId.generate();
      return [
        NewTab(shellId: shellId, tabId: tab),
        _place(doc, windowId, tab),
        MoveTab(tab, shellId: shellId, index: index),
      ];
    }(),
  (
    WindowDockable(:final windowId),
    WindowEdgeTarget(windowId: final at, :final edge),
  )
      when at != windowId =>
    switch (doc.tabOf(at)) {
      null => const [],
      final tab => [
        _place(
          doc,
          windowId,
          tab,
          target: at,
          axis: axisDirectionToAxis(edge),
          side: edge == AxisDirection.left || edge == AxisDirection.up
              ? DockSide.before
              : DockSide.after,
        ),
      ],
    },
  (WindowDockable(:final windowId), WindowCentreTarget(windowId: final at))
      when at != windowId &&
          doc.windows.containsKey(at) &&
          !_floatsOver(doc, at, windowId) =>
    switch (doc.windows[windowId]!.history.current) {
      final entry when doc.windows[at]!.history.current == entry => [
        CloseWindow(windowId),
        ActivateWindow(at),
      ],
      final entry => [
        PushBuffer(at, entry.buffer, arguments: entry.arguments),
        CloseWindow(windowId),
        ActivateWindow(at),
      ],
    },
  (WindowDockable(:final windowId), EmptyTabTarget(:final tabId))
      when doc.tabs.containsKey(tabId) && doc.tabs[tabId]!.root == null =>
    [_place(doc, windowId, tabId)],
  (WindowDockable(:final windowId), FloatTarget(:final scope))
      when !doc.floating.containsKey(windowId) =>
    [FloatWindow(windowId, scope: scope)],
  (WindowDockable(), _) => const [],
};

List<WindowingCommand> _tabToStrip(
  WindowingDoc doc,
  TabId tabId,
  ShellId shellId,
  int index,
) {
  final from = doc.shells.entries
      .where((e) => e.value.tabIds.contains(tabId))
      .firstOrNull;
  if (from == null || !doc.shells.containsKey(shellId)) return const [];
  if (from.key != shellId) {
    return [MoveTab(tabId, shellId: shellId, index: index)];
  }
  // A slot after the tab's own place shifts down once the tab leaves it.
  final i = from.value.tabIds.indexOf(tabId);
  final to = index > i ? index - 1 : index;
  return to == i ? const [] : [MoveTab(tabId, shellId: shellId, index: to)];
}

/// Moves [windowId], tree or floating, into tab [tabId].
WindowingCommand _place(
  WindowingDoc doc,
  WindowId windowId,
  TabId tabId, {
  WindowId? target,
  Axis axis = Axis.horizontal,
  DockSide side = DockSide.after,
}) => doc.floating.containsKey(windowId)
    ? DockWindow(windowId, tabId: tabId, target: target, axis: axis, side: side)
    : MoveWindow(
        windowId,
        tabId: tabId,
        target: target,
        axis: axis,
        side: side,
      );

/// Whether [window] floats, through any chain of scopes, over [over]:
/// closing [over] would close it too.
bool _floatsOver(WindowingDoc doc, WindowId window, WindowId over) {
  for (
    var s = doc.floating[window]?.scope;
    s is WindowScope;
    s = doc.floating[s.id]?.scope
  ) {
    if (s.id == over) return true;
  }
  return false;
}

/// A drag hovering a [DockArea]: the [target] it would drop on, and
/// whether the interceptor [allowed] the batch it would dispatch.
@immutable
class DockHover {
  const DockHover(this.target, {required this.allowed});

  final DockTarget target;
  final bool allowed;
}

/// Picks the target under [position] in an area of [size]; null for none.
typedef DockTargetPicker = DockTarget? Function(Offset position, Size size);

/// A drop zone of a reef dock drag (ADR 0012). While a drag hovers it,
/// [builder] gets a [DockHover]; null otherwise. Without a [builder] it
/// draws [child] under a tint, blue when the drop is allowed and red when
/// the interceptor vetoes it, over the half of an edge target or the
/// whole area. Where areas overlap the smallest one under the pointer wins.
class DockArea extends StatefulWidget {
  const DockArea({super.key, required this.target, this.builder, this.child})
    : assert(builder != null || child != null);

  final DockTargetPicker target;
  final Widget Function(BuildContext context, DockHover? hover)? builder;
  final Widget? child;

  /// A window's targets: the nearest edge within a quarter of the area,
  /// else the centre.
  static DockTargetPicker window(WindowId windowId) => (p, s) {
    final x = p.dx / s.width, y = p.dy / s.height;
    final (d, edge) = [
      (x, AxisDirection.left),
      (1 - x, AxisDirection.right),
      (y, AxisDirection.up),
      (1 - y, AxisDirection.down),
    ].reduce((a, b) => b.$1 < a.$1 ? b : a);
    return d < 0.25
        ? WindowEdgeTarget(windowId, edge)
        : WindowCentreTarget(windowId);
  };

  /// Tab [index]'s targets in [shellId]'s strip: the slot before it on its
  /// leading half, after it on its trailing half.
  static DockTargetPicker tab(ShellId shellId, int index) =>
      (p, s) => TabStripTarget(shellId, p.dx < s.width / 2 ? index : index + 1);

  @override
  State<DockArea> createState() => _DockAreaState();
}

final _areas = <_DockAreaState>{};

class _DockAreaState extends State<DockArea> {
  final _hover = ValueNotifier<DockHover?>(null);
  late WindowingController _controller;
  late FlutterView _view;

  @override
  void initState() {
    super.initState();
    _areas.add(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller = WindowingScope.of(context).controller;
    _view = View.of(context);
  }

  @override
  void dispose() {
    _areas.remove(this);
    _hover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: _hover,
    child: widget.child,
    builder: (context, hover, child) =>
        widget.builder?.call(context, hover) ??
        Stack(
          fit: StackFit.passthrough,
          children: [
            child!,
            Positioned.fill(
              child: IgnorePointer(child: hover == null ? null : _tint(hover)),
            ),
          ],
        ),
  );
}

Widget _tint(DockHover hover) {
  final tint = ColoredBox(
    color: hover.allowed ? const Color(0x442196F3) : const Color(0x44F44336),
  );
  return switch (hover.target) {
    WindowEdgeTarget(:final edge) => Align(
      alignment: switch (edge) {
        AxisDirection.left => Alignment.centerLeft,
        AxisDirection.right => Alignment.centerRight,
        AxisDirection.up => Alignment.topCenter,
        AxisDirection.down => Alignment.bottomCenter,
      },
      child: FractionallySizedBox(
        widthFactor: axisDirectionToAxis(edge) == Axis.horizontal ? 0.5 : 1,
        heightFactor: axisDirectionToAxis(edge) == Axis.vertical ? 0.5 : 1,
        child: tint,
      ),
    ),
    _ => SizedBox.expand(child: tint),
  };
}

/// The area under [position] (logical, in [view]) and the point in it.
/// Areas of another view count only when the pointer has left [view] and
/// the platform knows both views' screen origins.
(_DockAreaState, Offset)? _hitTest(
  WindowingController controller,
  FlutterView view,
  Offset position,
) {
  final platform = controller.platform;
  final inside = (Offset.zero & view.physicalSize / view.devicePixelRatio)
      .contains(position);
  final origin = platform?.viewOrigin(view);
  final screen = origin == null
      ? null
      : origin + position * view.devicePixelRatio;
  (_DockAreaState, Offset)? best;
  var bestSize = double.infinity;
  for (final area in _areas) {
    if (area._controller != controller || !area.mounted) continue;
    final box = area.context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) continue;
    if (_offstage(box)) continue;
    final Offset point;
    if (area._view == view) {
      point = position;
    } else {
      // ponytail: views can overlap on screen and reef knows no z-order, so
      // the pointer's own view wins while it is inside it.
      final o = platform?.viewOrigin(area._view);
      if (inside || screen == null || o == null) continue;
      point = (screen - o) / area._view.devicePixelRatio;
    }
    final local = box.globalToLocal(point);
    if (!(Offset.zero & box.size).contains(local)) continue;
    final size = box.size.width * box.size.height;
    if (size < bestSize) {
      best = (area, local);
      bestSize = size;
    }
  }
  return best;
}

bool _offstage(RenderObject box) {
  for (RenderObject? o = box; o != null; o = o.parent) {
    if (o is RenderOffstage && o.offstage) return true;
  }
  return false;
}

/// Makes [child] the drag handle of [dockable]. A drag starts past the
/// touch slop and is a reef drag session, not a Flutter `Draggable`: reef
/// follows the pointer across the views of every shell and hit-tests their
/// [DockArea]s. A drop on an area dispatches [dockCommands]' batch; a drop
/// outside the handle's view, on no area, pops the tab or window out where
/// the platform can ([ShellCapabilities.canPopOut]), and is cancelled
/// otherwise.
class DockSource extends StatefulWidget {
  const DockSource({super.key, required this.dockable, required this.child});

  final Dockable dockable;
  final Widget child;

  @override
  State<DockSource> createState() => _DockSourceState();
}

class _DockSourceState extends State<DockSource> {
  Offset? _down;
  bool _dragging = false;
  _DockAreaState? _hovered;

  WindowingController get _controller => WindowingScope.of(context).controller;

  void _hover(_DockAreaState? area, DockHover? hover) {
    if (_hovered != area && (_hovered?.mounted ?? false)) {
      _hovered!._hover.value = null;
    }
    _hovered = area;
    if (area != null) area._hover.value = hover;
  }

  void _move(PointerMoveEvent e) {
    final down = _down;
    if (down == null) return;
    if (!_dragging && (e.position - down).distance <= kTouchSlop) return;
    _dragging = true;
    final hit = _hitTest(_controller, View.of(context), e.position);
    if (hit == null) return _hover(null, null);
    final (area, local) = hit;
    final target = area.widget.target(local, area.context.size!);
    final batch = target == null
        ? const <WindowingCommand>[]
        : dockCommands(_controller.doc.value, widget.dockable, target);
    _hover(
      area,
      batch.isEmpty
          ? null
          : DockHover(target!, allowed: _controller.wouldApply(batch)),
    );
  }

  void _up(PointerUpEvent e) {
    final dragging = _dragging;
    _reset();
    if (!dragging) return;
    final controller = _controller;
    final view = View.of(context);
    final hit = _hitTest(controller, view, e.position);
    if (hit != null) {
      final (area, local) = hit;
      if (area.widget.target(local, area.context.size!) case final target?) {
        controller.dispatchAll(
          dockCommands(controller.doc.value, widget.dockable, target),
        );
      }
      return;
    }
    final outside = !(Offset.zero & view.physicalSize / view.devicePixelRatio)
        .contains(e.position);
    if (!outside || !controller.capabilities.canPopOut) return;
    switch (widget.dockable) {
      case TabDockable(:final tabId):
        controller.popOutTab(tabId);
      case WindowDockable(:final windowId):
        controller.popOutWindow(windowId);
    }
  }

  void _reset() {
    _hover(null, null);
    _down = null;
    _dragging = false;
  }

  @override
  void dispose() {
    _hover(null, null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (e) => _down = e.position,
    onPointerMove: _move,
    onPointerUp: _up,
    onPointerCancel: (_) => _reset(),
    child: widget.child,
  );
}
