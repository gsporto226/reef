import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Axis;
import 'package:reef/features/page_identity/_implementations/buffer_id.dart';
import 'package:reef/features/windowing/_implementations/windowing_doc.dart';
import 'package:reef/features/windowing/_implementations/windowing_ids.dart';

/// A windowing mutation (spec §3). Commands carry pre-generated ids for what
/// they create, so the reducer stays pure. A command invalid in the current
/// doc returns that same doc instance.
sealed class WindowingCommand {
  const WindowingCommand();

  WindowingDoc apply(WindowingDoc doc);
}

/// Appends a tab to [shellId], activates it and focuses the shell. With a
/// [buffer], the tab's first window ([WindowId]) shows that buffer.
class NewTab extends WindowingCommand {
  const NewTab({required this.shellId, required this.tabId, this.buffer});

  final ShellId shellId;
  final TabId tabId;
  final (WindowId, BufferId)? buffer;

  @override
  WindowingDoc apply(WindowingDoc doc) {
    final shell = doc.shells[shellId];
    if (shell == null || doc.tabs.containsKey(tabId)) return doc;
    final window = buffer?.$1;
    if (doc.windows.containsKey(window)) return doc;
    return doc.copyWith(
      shells: {
        ...doc.shells,
        shellId: ShellState(tabIds: [...shell.tabIds, tabId], activeTabId: tabId),
      },
      tabs: {
        ...doc.tabs,
        tabId: TabState(
            root: window == null ? null : WindowLeaf(window),
            activeWindowId: window),
      },
      windows: {
        ...doc.windows,
        if (buffer case (final w, final b))
          w: WindowState(history: BufferHistory(current: b)),
      },
      focusedShellId: shellId,
    );
  }
}

/// Activates [tabId] in its shell and focuses that shell.
class ActivateTab extends WindowingCommand {
  const ActivateTab(this.tabId);

  final TabId tabId;

  @override
  WindowingDoc apply(WindowingDoc doc) {
    final (id, shell) = _owner(doc, tabId) ?? (null, null);
    if (id == null || shell == null) return doc;
    if (shell.activeTabId == tabId && doc.focusedShellId == id) return doc;
    return doc.copyWith(
      shells: {
        ...doc.shells,
        id: ShellState(tabIds: shell.tabIds, activeTabId: tabId),
      },
      focusedShellId: id,
    );
  }
}

/// Closes [tabId] and its windows. A shell's last tab never closes. Closing
/// the active tab activates its left neighbour, or the next one.
class CloseTab extends WindowingCommand {
  const CloseTab(this.tabId);

  final TabId tabId;

  @override
  WindowingDoc apply(WindowingDoc doc) {
    final (id, shell) = _owner(doc, tabId) ?? (null, null);
    if (id == null || shell == null || shell.tabIds.length == 1) return doc;
    final index = shell.tabIds.indexOf(tabId);
    final tabIds = [...shell.tabIds]..removeAt(index);
    final active = shell.activeTabId == tabId
        ? tabIds[index == 0 ? 0 : index - 1]
        : shell.activeTabId;
    final root = doc.tabs[tabId]!.root;
    return doc.copyWith(
      shells: {...doc.shells, id: ShellState(tabIds: tabIds, activeTabId: active)},
      tabs: {...doc.tabs}..remove(tabId),
      windows: {...doc.windows}
        ..removeWhere((w, _) => root?.windowIds.contains(w) ?? false),
    );
  }
}

/// Splits [windowId] along [axis], putting [newWindowId] after it. The new
/// window copies the window history, with [buffer] pushed on top when given,
/// and takes focus.
class SplitWindow extends WindowingCommand {
  const SplitWindow(
    this.windowId, {
    required this.newWindowId,
    required this.axis,
    this.buffer,
  });

  final WindowId windowId;
  final WindowId newWindowId;
  final Axis axis;
  final BufferId? buffer;

  @override
  WindowingDoc apply(WindowingDoc doc) {
    final tabId = _tabOf(doc, windowId);
    if (tabId == null || doc.windows.containsKey(newWindowId)) return doc;
    final history = doc.windows[windowId]!.history;
    final copy = switch (buffer) {
      null => history,
      final b => BufferHistory(back: [...history.back, history.current], current: b),
    };
    // ponytail: always nests a new branch; flatten into a same-axis parent
    // if deep trees from repeated splits become a problem.
    final split = WindowBranch(
      axis: axis,
      children: [WindowLeaf(windowId), WindowLeaf(newWindowId)],
      ratios: const [0.5, 0.5],
    );
    final next = doc.copyWith(
      shells: doc.shells,
      tabs: {
        ...doc.tabs,
        tabId: TabState(
          root: _replaceLeaf(doc.tabs[tabId]!.root!, windowId, split),
          activeWindowId: newWindowId,
        ),
      },
      windows: {...doc.windows, newWindowId: WindowState(history: copy)},
    );
    return ActivateTab(tabId).apply(next);
  }
}

/// Closes tree window [windowId]. A branch left with one child collapses
/// into it and the remaining ratios are renormalized. When the window was
/// active, focus moves to its left neighbour, or the next one. Closing the
/// last window leaves the tab empty.
class CloseWindow extends WindowingCommand {
  const CloseWindow(this.windowId);

  final WindowId windowId;

  @override
  WindowingDoc apply(WindowingDoc doc) {
    final tabId = _tabOf(doc, windowId);
    if (tabId == null) return doc;
    final tab = doc.tabs[tabId]!;
    WindowId? neighbour;
    final root = _atParent(tab.root!, windowId, (branch, i) {
      final children = [...branch.children]..removeAt(i);
      final ratios = [...branch.ratios]..removeAt(i);
      neighbour = children[i == 0 ? 0 : i - 1].windowIds.first;
      if (children.length == 1) return children.single;
      final sum = ratios.fold(0.0, (a, r) => a + r);
      return WindowBranch(
        axis: branch.axis,
        children: children,
        ratios: [for (final r in ratios) r / sum],
      );
    });
    return doc.copyWith(
      shells: doc.shells,
      tabs: {
        ...doc.tabs,
        tabId: TabState(
          root: root,
          activeWindowId:
              tab.activeWindowId == windowId ? neighbour : tab.activeWindowId,
        ),
      },
      windows: {...doc.windows}..remove(windowId),
    );
  }
}

/// Sets the [ratios] of the branch directly holding [windowId]. Ratios must
/// be positive, one per child, and sum to one.
class ResizeWindow extends WindowingCommand {
  const ResizeWindow(this.windowId, this.ratios);

  final WindowId windowId;
  final List<double> ratios;

  @override
  WindowingDoc apply(WindowingDoc doc) {
    final tabId = _tabOf(doc, windowId);
    if (tabId == null ||
        ratios.any((r) => r <= 0) ||
        (ratios.fold(0.0, (a, r) => a + r) - 1).abs() > 1e-9) {
      return doc;
    }
    final tab = doc.tabs[tabId]!;
    final root = _atParent(
      tab.root!,
      windowId,
      (branch, _) => branch.ratios.length != ratios.length
          ? branch
          : WindowBranch(
              axis: branch.axis, children: branch.children, ratios: ratios),
    );
    if (root == null || root == tab.root) return doc;
    return doc.copyWith(
      shells: doc.shells,
      tabs: {
        ...doc.tabs,
        tabId: TabState(root: root, activeWindowId: tab.activeWindowId),
      },
    );
  }
}

/// A command that rewrites one window's history. Unknown windows, and edits
/// returning null or the same history, leave the doc unchanged.
sealed class _HistoryCommand extends WindowingCommand {
  const _HistoryCommand(this.windowId);

  final WindowId windowId;

  BufferHistory? edit(BufferHistory history);

  @override
  WindowingDoc apply(WindowingDoc doc) {
    final history = doc.windows[windowId]?.history;
    final next = history == null ? null : edit(history);
    if (next == null || next == history) return doc;
    return doc.copyWith(
      shells: doc.shells,
      windows: {...doc.windows, windowId: WindowState(history: next)},
    );
  }
}

/// Points [windowId] at [buffer] with a fresh window history.
class AttachBuffer extends _HistoryCommand {
  const AttachBuffer(super.windowId, this.buffer);

  final BufferId buffer;

  @override
  BufferHistory edit(BufferHistory history) => BufferHistory(current: buffer);
}

/// Moves the current buffer onto back, clears forward and shows [buffer].
class PushBuffer extends _HistoryCommand {
  const PushBuffer(super.windowId, this.buffer);

  final BufferId buffer;

  @override
  BufferHistory edit(BufferHistory history) => BufferHistory(
      back: [...history.back, history.current], current: buffer);
}

/// Back: moves the current buffer onto forward and shows the top of back.
class PopBuffer extends _HistoryCommand {
  const PopBuffer(super.windowId);

  @override
  BufferHistory? edit(BufferHistory history) => history.back.isEmpty
      ? null
      : BufferHistory(
          back: history.back.sublist(0, history.back.length - 1),
          current: history.back.last,
          forward: [...history.forward, history.current],
        );
}

/// Mirror of [PopBuffer]: moves the current buffer onto back and shows the
/// top of forward.
class NavigateForward extends _HistoryCommand {
  const NavigateForward(super.windowId);

  @override
  BufferHistory? edit(BufferHistory history) => history.forward.isEmpty
      ? null
      : BufferHistory(
          back: [...history.back, history.current],
          current: history.forward.last,
          forward: history.forward.sublist(0, history.forward.length - 1),
        );
}

/// Shows [buffer] in place of the current one; both stacks stay untouched.
class ReplaceBuffer extends _HistoryCommand {
  const ReplaceBuffer(super.windowId, this.buffer);

  final BufferId buffer;

  @override
  BufferHistory edit(BufferHistory history) => BufferHistory(
      back: history.back, current: buffer, forward: history.forward);
}

/// Activates [windowId] in its tab, then that tab and its shell.
class ActivateWindow extends WindowingCommand {
  const ActivateWindow(this.windowId);

  final WindowId windowId;

  @override
  WindowingDoc apply(WindowingDoc doc) {
    final tabId = _tabOf(doc, windowId);
    if (tabId == null) return doc;
    final tab = doc.tabs[tabId]!;
    final next = tab.activeWindowId == windowId
        ? doc
        : doc.copyWith(shells: doc.shells, tabs: {
            ...doc.tabs,
            tabId: TabState(root: tab.root, activeWindowId: windowId),
          });
    return ActivateTab(tabId).apply(next);
  }
}

/// Adds shell [shellId] holding one empty tab [tabId], and focuses it.
class AttachShell extends WindowingCommand {
  const AttachShell(this.shellId, {required this.tabId});

  final ShellId shellId;
  final TabId tabId;

  @override
  WindowingDoc apply(WindowingDoc doc) {
    if (doc.shells.containsKey(shellId) || doc.tabs.containsKey(tabId)) {
      return doc;
    }
    return doc.copyWith(
      shells: {
        ...doc.shells,
        shellId: ShellState(tabIds: [tabId], activeTabId: tabId),
      },
      tabs: {...doc.tabs, tabId: const TabState()},
      focusedShellId: shellId,
    );
  }
}

/// Focuses [shellId].
class ActivateShell extends WindowingCommand {
  const ActivateShell(this.shellId);

  final ShellId shellId;

  @override
  WindowingDoc apply(WindowingDoc doc) =>
      !doc.shells.containsKey(shellId) || doc.focusedShellId == shellId
          ? doc
          : doc.copyWith(shells: doc.shells, focusedShellId: shellId);
}

/// Closes [shellId] with its tabs and their windows. The last shell never
/// closes. Closing the focused shell focuses the first remaining one.
class CloseShell extends WindowingCommand {
  const CloseShell(this.shellId);

  final ShellId shellId;

  @override
  WindowingDoc apply(WindowingDoc doc) {
    final shell = doc.shells[shellId];
    if (shell == null || doc.shells.length == 1) return doc;
    final shells = {...doc.shells}..remove(shellId);
    final gone = {
      for (final t in shell.tabIds) ...?doc.tabs[t]!.root?.windowIds,
    };
    return doc.copyWith(
      shells: shells,
      tabs: {...doc.tabs}..removeWhere((t, _) => shell.tabIds.contains(t)),
      windows: {...doc.windows}..removeWhere((w, _) => gone.contains(w)),
      focusedShellId:
          doc.focusedShellId == shellId ? shells.keys.first : null,
    );
  }
}

/// Moves [tabId] to [index] (clamped) in [shellId], then activates it and
/// focuses that shell. A shell's last tab never moves out. When the moved
/// tab was active in its old shell, its left neighbour (or the next one)
/// becomes active there.
class MoveTab extends WindowingCommand {
  const MoveTab(this.tabId, {required this.shellId, required this.index});

  final TabId tabId;
  final ShellId shellId;
  final int index;

  @override
  WindowingDoc apply(WindowingDoc doc) {
    final (from, source) = _owner(doc, tabId) ?? (null, null);
    final target = doc.shells[shellId];
    if (from == null || source == null || target == null) return doc;
    if (from != shellId && source.tabIds.length == 1) return doc;
    final i = source.tabIds.indexOf(tabId);
    final rest = [...source.tabIds]..removeAt(i);
    final shells = {...doc.shells};
    if (from != shellId) {
      shells[from] = ShellState(
        tabIds: rest,
        activeTabId: source.activeTabId == tabId
            ? rest[i == 0 ? 0 : i - 1]
            : source.activeTabId,
      );
    }
    final into = from == shellId ? rest : [...target.tabIds];
    into.insert(index.clamp(0, into.length), tabId);
    shells[shellId] = ShellState(tabIds: into, activeTabId: tabId);
    final next = doc.copyWith(shells: shells, focusedShellId: shellId);
    return next == doc ? doc : next;
  }
}

/// Moves tree window [windowId] into tab [tabId] of any shell, in one step.
/// An empty tab takes it as its root; otherwise it splits [target] (the
/// tab's active window by default) along [axis], placed after it. The
/// source tree collapses as in [CloseWindow] and may be left empty. The
/// moved window keeps its history and takes focus.
class MoveWindow extends WindowingCommand {
  const MoveWindow(this.windowId,
      {required this.tabId, this.target, this.axis = Axis.horizontal});

  final WindowId windowId;
  final TabId tabId;
  final WindowId? target;
  final Axis axis;

  @override
  WindowingDoc apply(WindowingDoc doc) {
    final tab = doc.tabs[tabId];
    if (tab == null || _tabOf(doc, windowId) == null) return doc;
    final at = target ?? tab.activeWindowId;
    if (at == windowId) return doc;
    if (at != null && !tab.root!.windowIds.contains(at)) return doc;
    final removed = CloseWindow(windowId).apply(doc);
    final placed = at == null
        ? WindowLeaf(windowId)
        : _replaceLeaf(
            removed.tabs[tabId]!.root!,
            at,
            WindowBranch(
              axis: axis,
              children: [WindowLeaf(at), WindowLeaf(windowId)],
              ratios: const [0.5, 0.5],
            ));
    return ActivateWindow(windowId).apply(removed.copyWith(
      shells: removed.shells,
      tabs: {
        ...removed.tabs,
        tabId: TabState(root: placed, activeWindowId: windowId),
      },
      windows: {...removed.windows, windowId: doc.windows[windowId]!},
    ));
  }
}

TabId? _tabOf(WindowingDoc doc, WindowId window) {
  for (final MapEntry(:key, :value) in doc.tabs.entries) {
    if (value.root?.windowIds.contains(window) ?? false) return key;
  }
  return null;
}

WindowNode _replaceLeaf(WindowNode node, WindowId id, WindowNode with_) =>
    switch (node) {
      WindowLeaf(id: final leaf) => leaf == id ? with_ : node,
      WindowBranch() => WindowBranch(
          axis: node.axis,
          children: [for (final c in node.children) _replaceLeaf(c, id, with_)],
          ratios: node.ratios,
        ),
    };

/// Replaces the branch directly holding leaf [id] with `edit(branch, index)`
/// and returns the new tree, or null when no branch holds the leaf.
WindowNode? _atParent(WindowNode node, WindowId id,
    WindowNode Function(WindowBranch branch, int index) edit) {
  if (node is! WindowBranch) return null;
  final i = node.children.indexWhere((c) => c == WindowLeaf(id));
  if (i >= 0) return edit(node, i);
  for (final (j, child) in node.children.indexed) {
    if (_atParent(child, id, edit) case final edited?) {
      return WindowBranch(
        axis: node.axis,
        children: [...node.children]..[j] = edited,
        ratios: node.ratios,
      );
    }
  }
  return null;
}

(ShellId, ShellState)? _owner(WindowingDoc doc, TabId tab) {
  for (final MapEntry(:key, :value) in doc.shells.entries) {
    if (value.tabIds.contains(tab)) return (key, value);
  }
  return null;
}

/// Owns the [WindowingDoc] and publishes it through [doc]. Pages call the
/// intent methods; [dispatch] and [dispatchAll] take commands directly.
class WindowingController {
  WindowingController({WindowingDoc? initial})
      : _doc = ValueNotifier(initial ?? WindowingDoc.initial());

  final ValueNotifier<WindowingDoc> _doc;

  ValueListenable<WindowingDoc> get doc => _doc;

  void dispatch(WindowingCommand command) => dispatchAll([command]);

  /// Applies [commands] in order and publishes once, only when the resulting
  /// doc differs from the current one.
  void dispatchAll(Iterable<WindowingCommand> commands) {
    final next = commands.fold(_doc.value, (doc, c) => c.apply(doc));
    if (next != _doc.value) _doc.value = next;
  }

  /// Opens a tab in [shellId] (the focused shell by default), showing
  /// [buffer] in a first window when given. Returns the new tab's id.
  TabId newTab({ShellId? shellId, BufferId? buffer}) {
    final tab = TabId.generate();
    dispatch(NewTab(
      shellId: shellId ?? _doc.value.focusedShellId,
      tabId: tab,
      buffer: buffer == null ? null : (WindowId.generate(), buffer),
    ));
    return tab;
  }

  void activateTab(TabId tabId) => dispatch(ActivateTab(tabId));

  void closeTab(TabId tabId) => dispatch(CloseTab(tabId));

  void moveTab(TabId tabId, {required ShellId shellId, required int index}) =>
      dispatch(MoveTab(tabId, shellId: shellId, index: index));

  /// Adds a shell holding one empty tab and focuses it. Returns its id.
  /// The platform shell is not opened here (that is `popOutTab`, later).
  ShellId attachShell() {
    final shell = ShellId.generate();
    dispatch(AttachShell(shell, tabId: TabId.generate()));
    return shell;
  }

  void activateShell(ShellId shellId) => dispatch(ActivateShell(shellId));

  void closeShell(ShellId shellId) => dispatch(CloseShell(shellId));

  void activateWindow(WindowId windowId) => dispatch(ActivateWindow(windowId));

  void moveWindow(WindowId windowId,
          {required TabId tabId, WindowId? target, Axis axis = Axis.horizontal}) =>
      dispatch(MoveWindow(windowId, tabId: tabId, target: target, axis: axis));

  /// Splits [windowId] along [axis]. Returns the new window's id.
  WindowId splitWindow(WindowId windowId,
      {required Axis axis, BufferId? buffer}) {
    final window = WindowId.generate();
    dispatch(SplitWindow(windowId,
        newWindowId: window, axis: axis, buffer: buffer));
    return window;
  }

  void closeWindow(WindowId windowId) => dispatch(CloseWindow(windowId));

  void resizeWindow(WindowId windowId, List<double> ratios) =>
      dispatch(ResizeWindow(windowId, ratios));

  void attachBuffer(WindowId windowId, BufferId buffer) =>
      dispatch(AttachBuffer(windowId, buffer));

  void pushBuffer(WindowId windowId, BufferId buffer) =>
      dispatch(PushBuffer(windowId, buffer));

  void popBuffer(WindowId windowId) => dispatch(PopBuffer(windowId));

  void navigateForward(WindowId windowId) =>
      dispatch(NavigateForward(windowId));

  void replaceBuffer(WindowId windowId, BufferId buffer) =>
      dispatch(ReplaceBuffer(windowId, buffer));

  void dispose() => _doc.dispose();
}
