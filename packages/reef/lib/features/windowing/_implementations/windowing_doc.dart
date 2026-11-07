import 'package:flutter/foundation.dart';
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
  })  : shells = Map.unmodifiable(shells),
        tabs = Map.unmodifiable(tabs),
        windows = Map.unmodifiable(windows);

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

  WindowingDoc copyWith({
    required Map<ShellId, ShellState> shells,
    Map<TabId, TabState>? tabs,
    Map<WindowId, WindowState>? windows,
    ShellId? focusedShellId,
  }) =>
      WindowingDoc(
        shells: shells,
        tabs: tabs ?? this.tabs,
        windows: windows ?? this.windows,
        focusedShellId: focusedShellId ?? this.focusedShellId,
      );

  @override
  bool operator ==(Object other) =>
      other is WindowingDoc &&
      other.focusedShellId == focusedShellId &&
      mapEquals(other.shells, shells) &&
      mapEquals(other.tabs, tabs) &&
      mapEquals(other.windows, windows);

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
// ponytail: the tree is a single window for now; splits (#4+) turn [root]
// into a tree node.
@immutable
class TabState {
  const TabState({this.root, this.activeWindowId});

  final WindowId? root;
  final WindowId? activeWindowId;

  @override
  bool operator ==(Object other) =>
      other is TabState &&
      other.root == root &&
      other.activeWindowId == activeWindowId;

  @override
  int get hashCode => Object.hash(root, activeWindowId);
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
