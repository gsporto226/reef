import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Axis, AxisDirection, Rect;
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

  /// A fresh doc: one focused shell holding one tab, empty or with one
  /// active window showing [buffer].
  factory WindowingDoc.initial({BufferId? buffer}) {
    final shell = ShellId.generate();
    final tab = TabId.generate();
    final window = WindowId.generate();
    return WindowingDoc(
      shells: {shell: ShellState(tabIds: [tab], activeTabId: tab)},
      tabs: {
        tab: buffer == null
            ? const TabState()
            : TabState(root: WindowLeaf(window), activeWindowId: window),
      },
      windows: {
        if (buffer != null)
          window: WindowState(history: BufferHistory(current: buffer)),
      },
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

  /// The record version [toRecord] writes and [fromRecord] reads.
  static const recordVersion = 1;

  /// This doc as a versioned JSON record (spec §11).
  Map<String, dynamic> toRecord() => {
    'version': recordVersion,
    'doc': {
      'focusedShell': focusedShellId.id,
      'shells': {
        for (final MapEntry(:key, :value) in shells.entries)
          key.id: {
            'tabs': [for (final t in value.tabIds) t.id],
            'activeTab': value.activeTabId.id,
          },
      },
      'tabs': {
        for (final MapEntry(:key, :value) in tabs.entries)
          key.id: {
            'root': value.root.let(_nodeToJson),
            'activeWindow': value.activeWindowId?.id,
          },
      },
      'windows': {
        for (final MapEntry(:key, :value) in windows.entries)
          key.id: {
            'back': [for (final b in value.history.back) b.id],
            'current': value.history.current.id,
            'forward': [for (final b in value.history.forward) b.id],
          },
      },
      'floating': {
        for (final MapEntry(:key, :value) in floating.entries)
          key.id: {
            'scope': switch (value.scope) {
              ShellScope(:final id) => {'shell': id.id},
              TabScope(:final id) => {'tab': id.id},
              WindowScope(:final id) => {'window': id.id},
            },
            'z': value.zIndex,
            'geometry': value.geometry.let(
              (g) => [g.left, g.top, g.width, g.height],
            ),
          },
      },
    },
  };

  /// The doc in [record], or null when the record is missing, has another
  /// version, is malformed or breaks an invariant ([isValid]). Never throws.
  static WindowingDoc? fromRecord(Map<String, dynamic>? record) {
    if (record == null || record['version'] != recordVersion) return null;
    try {
      final json = record['doc'] as Map<String, dynamic>;
      List<BufferId> buffers(Object? l) => [
        for (final b in l! as List) BufferId.manual(b as String),
      ];
      final doc = WindowingDoc(
        focusedShellId: ShellId.manual(json['focusedShell'] as String),
        shells: {
          for (final MapEntry(:key, :value)
              in (json['shells'] as Map<String, dynamic>).entries)
            ShellId.manual(key): ShellState(
              tabIds: [
                for (final t in value['tabs'] as List)
                  TabId.manual(t as String),
              ],
              activeTabId: TabId.manual(value['activeTab'] as String),
            ),
        },
        tabs: {
          for (final MapEntry(:key, :value)
              in (json['tabs'] as Map<String, dynamic>).entries)
            TabId.manual(key): TabState(
              root: (value['root'] as Object?).let(_nodeFromJson),
              activeWindowId: (value['activeWindow'] as String?).let(
                WindowId.manual,
              ),
            ),
        },
        windows: {
          for (final MapEntry(:key, :value)
              in (json['windows'] as Map<String, dynamic>).entries)
            WindowId.manual(key): WindowState(
              history: BufferHistory(
                back: buffers(value['back']),
                current: BufferId.manual(value['current'] as String),
                forward: buffers(value['forward']),
              ),
            ),
        },
        floating: {
          for (final MapEntry(:key, :value)
              in (json['floating'] as Map<String, dynamic>).entries)
            WindowId.manual(key): FloatingState(
              scope: switch (value['scope']) {
                {'shell': final String id} => ShellScope(ShellId.manual(id)),
                {'tab': final String id} => TabScope(TabId.manual(id)),
                {'window': final String id} => WindowScope(WindowId.manual(id)),
                _ => throw const FormatException('scope'),
              },
              zIndex: value['z'] as int,
              geometry: (value['geometry'] as List?).let(
                (g) => Rect.fromLTWH(
                  (g[0] as num).toDouble(),
                  (g[1] as num).toDouble(),
                  (g[2] as num).toDouble(),
                  (g[3] as num).toDouble(),
                ),
              ),
            ),
        },
      );
      return doc.isValid ? doc : null;
    } on Object {
      return null; // malformed: any cast or shape failure
    }
  }

  /// Whether this doc holds the invariants the reducer keeps: every
  /// reference resolves, each tab sits in one shell, each window in one tree
  /// or floating, branches have two or more children with positive ratios
  /// summing to one, and floating scopes form no cycle.
  bool get isValid {
    if (!shells.containsKey(focusedShellId)) return false;
    final ownedTabs = [for (final s in shells.values) ...s.tabIds];
    for (final s in shells.values) {
      if (!s.tabIds.contains(s.activeTabId)) return false;
    }
    if (ownedTabs.length != tabs.length ||
        !setEquals(ownedTabs.toSet(), tabs.keys.toSet())) {
      return false;
    }
    final placed = [...floating.keys];
    for (final t in tabs.values) {
      final ids = t.root?.windowIds.toList() ?? const [];
      if (t.activeWindowId case final a? when !ids.contains(a)) return false;
      if (t.root case final root? when !_validNode(root)) return false;
      placed.addAll(ids);
    }
    if (placed.length != windows.length ||
        !setEquals(placed.toSet(), windows.keys.toSet())) {
      return false;
    }
    for (final id in floating.keys) {
      final seen = {id};
      for (var scope = floating[id]!.scope; ;) {
        final exists = switch (scope) {
          ShellScope(:final id) => shells.containsKey(id),
          TabScope(:final id) => tabs.containsKey(id),
          WindowScope(:final id) => windows.containsKey(id),
        };
        if (!exists) return false;
        if (scope is! WindowScope || !floating.containsKey(scope.id)) break;
        if (!seen.add(scope.id)) return false;
        scope = floating[scope.id]!.scope;
      }
    }
    return true;
  }
}

bool _validNode(WindowNode node) => switch (node) {
  WindowLeaf() => true,
  WindowBranch(:final children, :final ratios) =>
    children.length >= 2 &&
        ratios.length == children.length &&
        ratios.every((r) => r > 0) &&
        (ratios.fold(0.0, (a, b) => a + b) - 1).abs() < 1e-6 &&
        children.every(_validNode),
};

Object _nodeToJson(WindowNode node) => switch (node) {
  WindowLeaf(:final id) => {'window': id.id},
  WindowBranch(:final axis, :final children, :final ratios) => {
    'axis': axis.name,
    'children': [for (final c in children) _nodeToJson(c)],
    'ratios': ratios,
  },
};

WindowNode _nodeFromJson(Object json) => switch (json) {
  {'window': final String id} => WindowLeaf(WindowId.manual(id)),
  {
    'axis': final String axis,
    'children': final List children,
    'ratios': final List ratios,
  } =>
    WindowBranch(
      axis: Axis.values.byName(axis),
      children: [for (final c in children) _nodeFromJson(c as Object)],
      ratios: [for (final r in ratios) (r as num).toDouble()],
    ),
  _ => throw const FormatException('window node'),
};

extension<T extends Object> on T? {
  R? let<R>(R Function(T) f) => switch (this) {
    final v? => f(v),
    _ => null,
  };
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

/// Read-side queries over a [WindowingDoc].
extension WindowingDocQueries on WindowingDoc {
  /// The focused shell's active tab.
  TabState get activeTab => tabs[shells[focusedShellId]!.activeTabId]!;

  /// The focused shell's active tab's active window.
  WindowId? get activeWindowId => activeTab.activeWindowId;

  /// The windows whose history currently shows [buffer], in [windows] order.
  Iterable<WindowId> windowsShowing(BufferId buffer) => [
    for (final MapEntry(:key, :value) in windows.entries)
      if (value.history.current == buffer) key,
  ];

  /// The tab whose tree holds [window]; null for a floating or unknown one.
  TabId? tabOf(WindowId window) => [
    for (final MapEntry(:key, :value) in tabs.entries)
      if (value.root?.windowIds.contains(window) ?? false) key,
  ].firstOrNull;

  /// The tree window that shares [window]'s edge on side [direction], laid
  /// out by the tree's ratios; null at the tab's edge or for a floating
  /// window.
  WindowId? neighbour(WindowId window, AxisDirection direction) {
    final root = tabOf(window)?.let((t) => tabs[t]!.root);
    if (root == null) return null;
    final rects = <WindowId, Rect>{};
    void layout(WindowNode node, Rect r) {
      switch (node) {
        case WindowLeaf(:final id):
          rects[id] = r;
        case WindowBranch(:final axis, :final children, :final ratios):
          var start = 0.0;
          for (final (i, child) in children.indexed) {
            final end = start + ratios[i];
            layout(
                child,
                axis == Axis.horizontal
                    ? Rect.fromLTRB(r.left + r.width * start, r.top,
                        r.left + r.width * end, r.bottom)
                    : Rect.fromLTRB(r.left, r.top + r.height * start,
                        r.right, r.top + r.height * end));
            start = end;
          }
      }
    }

    layout(root, const Rect.fromLTWH(0, 0, 1, 1));
    final a = rects[window]!;
    const e = 1e-9;
    bool overlapsV(Rect b) => b.top < a.bottom - e && b.bottom > a.top + e;
    bool overlapsH(Rect b) => b.left < a.right - e && b.right > a.left + e;
    return rects.entries
        .where((x) => switch (direction) {
              AxisDirection.left =>
                (x.value.right - a.left).abs() < e && overlapsV(x.value),
              AxisDirection.right =>
                (x.value.left - a.right).abs() < e && overlapsV(x.value),
              AxisDirection.up =>
                (x.value.bottom - a.top).abs() < e && overlapsH(x.value),
              AxisDirection.down =>
                (x.value.top - a.bottom).abs() < e && overlapsH(x.value),
            })
        .firstOrNull
        ?.key;
  }

}
