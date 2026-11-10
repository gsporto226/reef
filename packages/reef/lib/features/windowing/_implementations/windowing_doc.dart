import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Axis, Rect;
import 'package:reef/features/page_identity/_implementations/buffer_id.dart';
import 'package:reef/features/windowing/_implementations/windowing_ids.dart';

/// The canonical windowing state (spec §2): immutable, id-normalized, with
/// hand-written value equality. Collections are unmodifiable.
@immutable
class WindowingDoc {
  WindowingDoc({
    required Map<ShellId, ShellState> shells,
    required Map<TabId, TabState> tabs,
    required Map<WindowId, WindowState> windows,
    required this.focusedShellId,
    Map<WindowId, FloatingState> floating = const {},
  })  : shells = Map.unmodifiable(shells),
        tabs = Map.unmodifiable(tabs),
        windows = Map.unmodifiable(windows),
        floating = Map.unmodifiable(floating);

  /// A fresh doc: one focused shell holding one empty tab.
  factory WindowingDoc.initial() {
    final shell = ShellId.generate();
    final tab = TabId.generate();
    return WindowingDoc(
      shells: {shell: ShellState(tabIds: [tab], activeTabId: tab)},
      tabs: {tab: const TabState()},
      windows: const {},
      focusedShellId: shell,
    );
  }

  final Map<ShellId, ShellState> shells;
  final Map<TabId, TabState> tabs;
  final Map<WindowId, WindowState> windows;
  final ShellId focusedShellId;

  /// Floating windows: in [windows] but in no tab's tree.
  final Map<WindowId, FloatingState> floating;

  WindowingDoc copyWith({
    Map<ShellId, ShellState>? shells,
    Map<TabId, TabState>? tabs,
    Map<WindowId, WindowState>? windows,
    ShellId? focusedShellId,
    Map<WindowId, FloatingState>? floating,
  }) =>
      WindowingDoc(
        shells: shells ?? this.shells,
        tabs: tabs ?? this.tabs,
        windows: windows ?? this.windows,
        focusedShellId: focusedShellId ?? this.focusedShellId,
        floating: floating ?? this.floating,
      );

  @override
  bool operator ==(Object other) =>
      other is WindowingDoc &&
      other.focusedShellId == focusedShellId &&
      mapEquals(other.shells, shells) &&
      mapEquals(other.tabs, tabs) &&
      mapEquals(other.windows, windows) &&
      mapEquals(other.floating, floating);

  @override
  int get hashCode => Object.hash(focusedShellId, shells.length, tabs.length,
      windows.length);
}

/// A shell's ordered tab strip and its active tab.
@immutable
class ShellState {
  ShellState({required List<TabId> tabIds, required this.activeTabId})
      : tabIds = List.unmodifiable(tabIds);

  final List<TabId> tabIds;
  final TabId activeTabId;

  @override
  bool operator ==(Object other) =>
      other is ShellState &&
      other.activeTabId == activeTabId &&
      listEquals(other.tabIds, tabIds);

  @override
  int get hashCode => Object.hash(activeTabId, Object.hashAll(tabIds));
}

/// A tab's window tree and its active window. Empty when [root] is null.
@immutable
class TabState {
  const TabState({this.root, this.activeWindowId});

  final WindowNode? root;
  final WindowId? activeWindowId;

  @override
  bool operator ==(Object other) =>
      other is TabState &&
      other.root == root &&
      other.activeWindowId == activeWindowId;

  @override
  int get hashCode => Object.hash(root, activeWindowId);
}

/// A node of a tab's window tree: a [WindowLeaf] or a [WindowBranch].
@immutable
sealed class WindowNode {
  const WindowNode();

  /// The tree windows under this node, in layout order.
  Iterable<WindowId> get windowIds;
}

/// A tree window's slot.
class WindowLeaf extends WindowNode {
  const WindowLeaf(this.id);

  final WindowId id;

  @override
  Iterable<WindowId> get windowIds => [id];

  @override
  bool operator ==(Object other) => other is WindowLeaf && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Children laid out along [axis], each taking its share of [ratios]
/// (positive, one per child, summing to one). Always two or more children.
class WindowBranch extends WindowNode {
  WindowBranch({
    required this.axis,
    required List<WindowNode> children,
    required List<double> ratios,
  })  : children = List.unmodifiable(children),
        ratios = List.unmodifiable(ratios);

  final Axis axis;
  final List<WindowNode> children;
  final List<double> ratios;

  WindowBranch copyWith({List<WindowNode>? children, List<double>? ratios}) =>
      WindowBranch(
        axis: axis,
        children: children ?? this.children,
        ratios: ratios ?? this.ratios,
      );

  @override
  Iterable<WindowId> get windowIds => children.expand((c) => c.windowIds);

  @override
  bool operator ==(Object other) =>
      other is WindowBranch &&
      other.axis == axis &&
      listEquals(other.children, children) &&
      listEquals(other.ratios, ratios);

  @override
  int get hashCode =>
      Object.hash(axis, Object.hashAll(children), Object.hashAll(ratios));
}

/// A window: a viewport showing one buffer, with its own history.
@immutable
class WindowState {
  const WindowState({required this.history});

  final BufferHistory history;

  @override
  bool operator ==(Object other) =>
      other is WindowState && other.history == history;

  @override
  int get hashCode => history.hashCode;
}

/// A window's back and forward stacks around the buffer it shows.
@immutable
class BufferHistory {
  BufferHistory({
    required this.current,
    List<BufferId> back = const [],
    List<BufferId> forward = const [],
  })  : back = List.unmodifiable(back),
        forward = List.unmodifiable(forward);

  final List<BufferId> back;
  final BufferId current;
  final List<BufferId> forward;

  @override
  bool operator ==(Object other) =>
      other is BufferHistory &&
      other.current == current &&
      listEquals(other.back, back) &&
      listEquals(other.forward, forward);

  @override
  int get hashCode =>
      Object.hash(current, Object.hashAll(back), Object.hashAll(forward));
}

/// The container whose overlay hosts a floating window.
@immutable
sealed class FloatScope {
  const FloatScope();
}

class ShellScope extends FloatScope {
  const ShellScope(this.id);

  final ShellId id;

  @override
  bool operator ==(Object other) => other is ShellScope && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class TabScope extends FloatScope {
  const TabScope(this.id);

  final TabId id;

  @override
  bool operator ==(Object other) => other is TabScope && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class WindowScope extends FloatScope {
  const WindowScope(this.id);

  final WindowId id;

  @override
  bool operator ==(Object other) => other is WindowScope && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// A floating window's [scope], its [zIndex] among that scope's floating
/// windows (higher draws on top), and an advisory [geometry] hint: where it
/// sits in its scope's space, null until moved.
@immutable
class FloatingState {
  const FloatingState({required this.scope, required this.zIndex, this.geometry});

  final FloatScope scope;
  final int zIndex;
  final Rect? geometry;

  FloatingState copyWith({int? zIndex, Rect? geometry}) => FloatingState(
      scope: scope,
      zIndex: zIndex ?? this.zIndex,
      geometry: geometry ?? this.geometry);

  @override
  bool operator ==(Object other) =>
      other is FloatingState &&
      other.scope == scope &&
      other.zIndex == zIndex &&
      other.geometry == geometry;

  @override
  int get hashCode => Object.hash(scope, zIndex, geometry);
}
