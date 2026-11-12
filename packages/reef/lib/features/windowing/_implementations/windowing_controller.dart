import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Axis, Rect;
import 'package:formularium/features/localization/localizable_interface.dart';
import 'package:reef_fp/result.dart';
import 'package:reef/features/hibernation/_interfaces/hibernation_store.dart';
import 'package:reef/features/hibernation/_implementations/lifecycle.dart';
import 'package:reef/features/undo/_implementations/undo_controller.dart';
import 'package:reef/features/page_identity/_implementations/buffer_id.dart';
import 'package:reef/features/windowing/_implementations/shell_platform.dart';
import 'package:reef/features/windowing/_implementations/windowing_doc.dart';
import 'package:reef/features/windowing/_implementations/windowing_ids.dart';

/// A windowing mutation (spec §3). Commands carry pre-generated ids for what
/// they create, so the reducer stays pure. A command invalid in the current
/// doc returns that same doc instance.
sealed class WindowingCommand {
  const WindowingCommand();

  WindowingDoc apply(WindowingDoc doc);
}

/// Folds commands over a doc without a controller.
extension WindowingDocApply on WindowingDoc {
  /// This doc with [commands] applied in order, through no interceptor or
  /// focus policy: builds a starting layout without a controller.
  WindowingDoc applyAll(Iterable<WindowingCommand> commands) =>
      commands.fold(this, (doc, c) => c.apply(doc));
}

/// Appends a tab to [shellId], activates it and focuses the shell. With a
/// [buffer], the tab's first window ([WindowId]) shows that buffer.
class NewTab extends WindowingCommand {
  NewTab({
    required this.shellId,
    required this.tabId,
    this.buffer,
    this.arguments = const {},
    HistoryEntryId? entryId,
  }) : entryId = entryId ?? HistoryEntryId.generate();

  /// The id of the entry [buffer] opens with; made here so [apply] is pure.
  final HistoryEntryId entryId;

  final ShellId shellId;
  final TabId tabId;
  final (WindowId, BufferId)? buffer;
  final Map<String, String> arguments;

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
          w: WindowState(
              history: BufferHistory(
                  current: HistoryEntry(b,
                      arguments: arguments, id: entryId))),
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
    return _prune(doc.copyWith(
      shells: {...doc.shells, id: ShellState(tabIds: tabIds, activeTabId: active)},
      tabs: {...doc.tabs}..remove(tabId),
      windows: {...doc.windows}
        ..removeWhere((w, _) => root?.windowIds.contains(w) ?? false),
    ));
  }
}

/// Splits [windowId] along [axis], putting [newWindowId] after it. The new
/// window copies the window history, with [buffer] pushed on top when given,
/// and takes focus.
class SplitWindow extends WindowingCommand {
  SplitWindow(
    this.windowId, {
    required this.newWindowId,
    required this.axis,
    this.buffer,
    this.arguments = const {},
    HistoryEntryId? entryId,
  }) : entryId = entryId ?? HistoryEntryId.generate();

  /// The id of the entry [buffer] is pushed with; made here so [apply] is
  /// pure.
  final HistoryEntryId entryId;

  final WindowId windowId;
  final WindowId newWindowId;
  final Axis axis;
  final BufferId? buffer;
  final Map<String, String> arguments;

  @override
  WindowingDoc apply(WindowingDoc doc) {
    final tabId = doc.tabOf(windowId);
    if (tabId == null || doc.windows.containsKey(newWindowId)) return doc;
    final history = doc.windows[windowId]!.history;
    final copy = switch (buffer) {
      null => history,
      final b => BufferHistory(
          back: [...history.back, history.current],
          current: HistoryEntry(b, arguments: arguments, id: entryId)),
    };
    // ponytail: always nests a new branch; flatten into a same-axis parent
    // if deep trees from repeated splits become a problem.
    final split = WindowBranch(
      axis: axis,
      children: [WindowLeaf(windowId), WindowLeaf(newWindowId)],
      ratios: const [0.5, 0.5],
    );
    final next = doc.copyWith(
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
    final WindowingDoc out;
    if (doc.floating.containsKey(windowId)) {
      out = doc.copyWith(
          floating: {...doc.floating}..remove(windowId));
    } else {
      final detached = _detach(doc, windowId);
      if (detached == null) return doc;
      out = detached;
    }
    return _prune(
        out.copyWith(windows: {...out.windows}..remove(windowId)));
  }
}

/// Takes tree window [windowId] out of its tab's tree, which collapses as in
/// [CloseWindow]. The window stays in `doc.windows`. Null when it is not a
/// tree window.
WindowingDoc? _detach(WindowingDoc doc, WindowId windowId) {
  final tabId = doc.tabOf(windowId);
  if (tabId == null) return null;
  final tab = doc.tabs[tabId]!;
  WindowId? neighbour;
  final root = _atParent(tab.root!, windowId, (branch, i) {
    final children = [...branch.children]..removeAt(i);
    final ratios = [...branch.ratios]..removeAt(i);
    neighbour = children[i == 0 ? 0 : i - 1].windowIds.first;
    if (children.length == 1) return children.single;
    final sum = ratios.fold(0.0, (a, r) => a + r);
    return branch.copyWith(
        children: children, ratios: [for (final r in ratios) r / sum]);
  });
  return doc.copyWith(
    tabs: {
      ...doc.tabs,
      tabId: TabState(
        root: root,
        activeWindowId:
            tab.activeWindowId == windowId ? neighbour : tab.activeWindowId,
      ),
    },
  );
}

/// Drops floating windows whose scope no longer exists, transitively.
WindowingDoc _prune(WindowingDoc doc) {
  final dead = [
    for (final MapEntry(:key, :value) in doc.floating.entries)
      if (!_scopeExists(doc, value.scope)) key,
  ];
  if (dead.isEmpty) return doc;
  return _prune(doc.copyWith(
    windows: {...doc.windows}..removeWhere((w, _) => dead.contains(w)),
    floating: {...doc.floating}..removeWhere((w, _) => dead.contains(w)),
  ));
}

bool _scopeExists(WindowingDoc doc, FloatScope scope) => switch (scope) {
      ShellScope(:final id) => doc.shells.containsKey(id),
      TabScope(:final id) => doc.tabs.containsKey(id),
      WindowScope(:final id) => doc.windows.containsKey(id),
    };

/// Focuses the tab or shell owning [scope], following floating windows'
/// scopes up to a tree window, tab or shell.
WindowingDoc _focusScope(WindowingDoc doc, FloatScope scope) =>
    switch (scope) {
      ShellScope(:final id) => ActivateShell(id).apply(doc),
      TabScope(:final id) => ActivateTab(id).apply(doc),
      WindowScope(:final id) => switch (doc.floating[id]) {
          final f? => _focusScope(doc, f.scope),
          null => ActivateTab(doc.tabOf(id)!).apply(doc),
        },
    };

/// Which side of the target window a docked window lands on, along the
/// dock axis.
enum DockSide { before, after }

/// Puts [windowId] (in `doc.windows`, in no tree) into tab [tabId]: as the
/// root of an empty tab, else in a new 50/50 branch with [at] along [axis].
/// The window takes focus.
WindowingDoc _place(WindowingDoc doc, WindowId windowId, TabId tabId,
    WindowId? at, Axis axis, DockSide side) {
  final pair = [WindowLeaf(at ?? windowId), WindowLeaf(windowId)];
  final placed = at == null
      ? WindowLeaf(windowId)
      : _replaceLeaf(
          doc.tabs[tabId]!.root!,
          at,
          WindowBranch(
            axis: axis,
            children: side == DockSide.after ? pair : pair.reversed.toList(),
            ratios: const [0.5, 0.5],
          ));
  return ActivateWindow(windowId).apply(doc.copyWith(
    tabs: {
      ...doc.tabs,
      tabId: TabState(root: placed, activeWindowId: windowId),
    },
  ));
}

/// The insertion target in tab [tab] for [windowId]: [target], or the tab's
/// active window. `(false, _)` when that is [windowId] or not in the tab.
(bool, WindowId?) _anchor(TabState tab, WindowId windowId, WindowId? target) {
  final at = target ?? tab.activeWindowId;
  if (at == windowId) return (false, null);
  if (at != null && !tab.root!.windowIds.contains(at)) return (false, null);
  return (true, at);
}

/// Sets the [ratios] of the branch [levels] above the one directly holding
/// [windowId] (0 is that branch). Ratios must be positive, one per child,
/// and sum to one; negative levels or levels past the root are no-ops.
class ResizeWindow extends WindowingCommand {
  const ResizeWindow(this.windowId, this.ratios, {this.levels = 0});

  final WindowId windowId;
  final List<double> ratios;
  final int levels;

  @override
  WindowingDoc apply(WindowingDoc doc) {
    final tabId = doc.tabOf(windowId);
    if (tabId == null ||
        ratios.any((r) => r <= 0) ||
        (ratios.fold(0.0, (a, r) => a + r) - 1).abs() > 1e-9) {
      return doc;
    }
    final tab = doc.tabs[tabId]!;
    final root = _resize(tab.root!)?.$1;
    if (root == null || root == tab.root) return doc;
    return doc.copyWith(
      tabs: {
        ...doc.tabs,
        tabId: TabState(root: root, activeWindowId: tab.activeWindowId),
      },
    );
  }

  /// [node] rebuilt with the target branch resized, and its height above
  /// [windowId]'s leaf; null when the window is not under [node].
  (WindowNode, int)? _resize(WindowNode node) {
    if (node is! WindowBranch) {
      return node == WindowLeaf(windowId) ? (node, 0) : null;
    }
    for (final (j, child) in node.children.indexed) {
      if (_resize(child) case (final edited, final below)?) {
        final height = below + 1;
        final branch =
            height == levels + 1 && ratios.length == node.ratios.length
                ? node.copyWith(ratios: ratios)
                : node;
        return (
          edited == child
              ? branch
              : branch.copyWith(children: [...branch.children]..[j] = edited),
          height,
        );
      }
    }
    return null;
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
      windows: {...doc.windows, windowId: WindowState(history: next)},
    );
  }
}

/// Points [windowId] at [buffer] with a fresh window history.
class AttachBuffer extends _HistoryCommand {
  AttachBuffer(super.windowId, this.buffer,
      {this.arguments = const {}, HistoryEntryId? entryId})
      : entryId = entryId ?? HistoryEntryId.generate();

  /// The new entry's id; made here so [apply] is pure.
  final HistoryEntryId entryId;

  final BufferId buffer;
  final Map<String, String> arguments;

  HistoryEntry get _entry =>
      HistoryEntry(buffer, arguments: arguments, id: entryId);

  @override
  BufferHistory edit(BufferHistory history) => BufferHistory(current: _entry);
}

/// Moves the current buffer onto back, clears forward and shows [buffer].
class PushBuffer extends _HistoryCommand {
  PushBuffer(super.windowId, this.buffer,
      {this.arguments = const {}, HistoryEntryId? entryId})
      : entryId = entryId ?? HistoryEntryId.generate();

  /// The new entry's id; made here so [apply] is pure.
  final HistoryEntryId entryId;

  final BufferId buffer;
  final Map<String, String> arguments;

  HistoryEntry get _entry =>
      HistoryEntry(buffer, arguments: arguments, id: entryId);

  @override
  BufferHistory edit(BufferHistory history) => BufferHistory(
      back: [...history.back, history.current], current: _entry);
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
  ReplaceBuffer(super.windowId, this.buffer,
      {this.arguments = const {}, HistoryEntryId? entryId})
      : entryId = entryId ?? HistoryEntryId.generate();

  /// The new entry's id; made here so [apply] is pure.
  final HistoryEntryId entryId;

  final BufferId buffer;
  final Map<String, String> arguments;

  HistoryEntry get _entry =>
      HistoryEntry(buffer, arguments: arguments, id: entryId);

  @override
  BufferHistory edit(BufferHistory history) => BufferHistory(
      back: history.back, current: _entry, forward: history.forward);
}

/// Activates tree window [windowId] in its tab, then that tab and its shell.
/// A floating window is raised in its scope instead, and focus follows its
/// scope chain to the owning tab or shell.
class ActivateWindow extends WindowingCommand {
  const ActivateWindow(this.windowId);

  final WindowId windowId;

  @override
  WindowingDoc apply(WindowingDoc doc) {
    if (doc.floating[windowId] case final state?) {
      return _focusScope(RaiseWindow(windowId).apply(doc), state.scope);
    }
    final tabId = doc.tabOf(windowId);
    if (tabId == null) return doc;
    final tab = doc.tabs[tabId]!;
    final next = tab.activeWindowId == windowId
        ? doc
        : doc.copyWith(tabs: {
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
          : doc.copyWith(focusedShellId: shellId);
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
    return _prune(doc.copyWith(
      shells: shells,
      tabs: {...doc.tabs}..removeWhere((t, _) => shell.tabIds.contains(t)),
      windows: {...doc.windows}..removeWhere((w, _) => gone.contains(w)),
      focusedShellId:
          doc.focusedShellId == shellId ? shells.keys.first : null,
    ));
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
    if (from == shellId && index.clamp(0, source.tabIds.length - 1) == i) {
      return doc;
    }
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
    return doc.copyWith(shells: shells, focusedShellId: shellId);
  }
}

/// Moves tree window [windowId] into tab [tabId] of any shell, in one step.
/// An empty tab takes it as its root; otherwise it splits [target] (the
/// tab's active window by default) along [axis], on [side]. The source tree
/// collapses as in [CloseWindow] and may be left empty. The moved window
/// keeps its history and takes focus.
class MoveWindow extends WindowingCommand {
  const MoveWindow(this.windowId,
      {required this.tabId,
      this.target,
      this.axis = Axis.horizontal,
      this.side = DockSide.after});

  final WindowId windowId;
  final TabId tabId;
  final WindowId? target;
  final Axis axis;
  final DockSide side;

  @override
  WindowingDoc apply(WindowingDoc doc) {
    final tab = doc.tabs[tabId];
    if (tab == null || doc.tabOf(windowId) == null) return doc;
    final (ok, at) = _anchor(tab, windowId, target);
    if (!ok) return doc;
    return _place(_detach(doc, windowId)!, windowId, tabId, at, axis, side);
  }
}

/// Moves tree window [windowId] into the floating overlay of [scope], on top
/// of that scope's floating windows. Its tab's tree collapses as in
/// [CloseWindow] and may be left empty. Refused when [scope] is missing, is
/// the window itself, or floats over it.
class FloatWindow extends WindowingCommand {
  const FloatWindow(this.windowId, {required this.scope});

  final WindowId windowId;
  final FloatScope scope;

  @override
  WindowingDoc apply(WindowingDoc doc) {
    if (!_scopeExists(doc, scope)) return doc;
    for (var s = scope; s is WindowScope; s = doc.floating[s.id]!.scope) {
      if (s.id == windowId) return doc;
      if (!doc.floating.containsKey(s.id)) break;
    }
    final detached = _detach(doc, windowId);
    if (detached == null) return doc;
    return detached.copyWith(floating: {
      ...doc.floating,
      windowId: FloatingState(scope: scope, zIndex: _top(doc, scope, null) + 1),
    });
  }
}

/// Docks floating window [windowId] into tab [tabId]: as the root of an
/// empty tab, else beside [target] (the tab's active window by default) on
/// [side] along [axis]. The docked window takes focus.
class DockWindow extends WindowingCommand {
  const DockWindow(this.windowId,
      {required this.tabId,
      this.target,
      this.axis = Axis.horizontal,
      this.side = DockSide.after});

  final WindowId windowId;
  final TabId tabId;
  final WindowId? target;
  final Axis axis;
  final DockSide side;

  @override
  WindowingDoc apply(WindowingDoc doc) {
    final tab = doc.tabs[tabId];
    if (tab == null || !doc.floating.containsKey(windowId)) return doc;
    final (ok, at) = _anchor(tab, windowId, target);
    if (!ok) return doc;
    return _place(
        doc.copyWith(
            floating: {...doc.floating}..remove(windowId)),
        windowId,
        tabId,
        at,
        axis,
        side);
  }
}

/// Puts floating window [windowId] above the other floating windows of its
/// scope.
class RaiseWindow extends WindowingCommand {
  const RaiseWindow(this.windowId);

  final WindowId windowId;

  @override
  WindowingDoc apply(WindowingDoc doc) {
    final state = doc.floating[windowId];
    if (state == null) return doc;
    final top = _top(doc, state.scope, windowId);
    if (state.zIndex > top) return doc;
    return doc.copyWith(floating: {
      ...doc.floating,
      windowId: state.copyWith(zIndex: top + 1),
    });
  }
}

/// Sets floating window [windowId]'s advisory geometry hint to [geometry], a
/// rectangle in its scope's space. Refused for windows that are not floating.
class MoveFloating extends WindowingCommand {
  const MoveFloating(this.windowId, this.geometry);

  final WindowId windowId;
  final Rect geometry;

  @override
  WindowingDoc apply(WindowingDoc doc) {
    final state = doc.floating[windowId];
    if (state == null || state.geometry == geometry) return doc;
    return doc.copyWith(floating: {
      ...doc.floating,
      windowId: state.copyWith(geometry: geometry),
    });
  }
}

/// The highest zIndex in [scope], ignoring [except]; -1 when none.
int _top(WindowingDoc doc, FloatScope scope, WindowId? except) =>
    doc.floating.entries
        .where((e) => e.value.scope == scope && e.key != except)
        .fold(-1, (top, e) => e.value.zIndex > top ? e.value.zIndex : top);

WindowNode _replaceLeaf(WindowNode node, WindowId id, WindowNode with_) =>
    switch (node) {
      WindowLeaf(id: final leaf) => leaf == id ? with_ : node,
      WindowBranch() => node.copyWith(
          children: [for (final c in node.children) _replaceLeaf(c, id, with_)]),
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
      return node.copyWith(children: [...node.children]..[j] = edited);
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

/// Sees each command before the reducer, against the doc as folded so far.
typedef WindowingInterceptor = CommandDecision Function(
    WindowingDoc doc, WindowingCommand command);

/// A [WindowingInterceptor]'s verdict on one command (spec §6).
sealed class CommandDecision {
  const CommandDecision();

  const factory CommandDecision.approve() = _Approve;

  /// Skips the command and publishes [reason] through
  /// [WindowingController.vetoes].
  const factory CommandDecision.veto(ILocalizable reason) = _Veto;

  /// Applies [command] instead, without intercepting it again.
  const factory CommandDecision.replace(WindowingCommand command) = _Replace;
}

class _Approve extends CommandDecision {
  const _Approve();
}

class _Veto extends CommandDecision {
  const _Veto(this.reason);
  final ILocalizable reason;
}

class _Replace extends CommandDecision {
  const _Replace(this.command);
  final WindowingCommand command;
}

/// A [command] an interceptor vetoed, with its [reason].
class CommandVeto {
  const CommandVeto(this.command, this.reason);

  final WindowingCommand command;
  final ILocalizable reason;
}

/// Compiles "open [buffer]" against [doc] into the commands
/// [WindowingController.openBuffer] dispatches as one batch.
typedef WindowingOpenPolicy = List<WindowingCommand> Function(
    WindowingDoc doc, BufferId buffer,
    {Map<String, String> arguments});

/// Focuses a window of the focused shell's active tab that shows [buffer]
/// with [arguments];
/// else [pushOpenPolicy].
List<WindowingCommand> defaultOpenPolicy(WindowingDoc doc, BufferId buffer,
    {Map<String, String> arguments = const {}}) {
  final tab = doc.activeTab;
  for (final w in tab.root?.windowIds ?? const <WindowId>[]) {
    if (doc.windows[w]!.history.current ==
        HistoryEntry(buffer, arguments: arguments)) {
      return [ActivateWindow(w)];
    }
  }
  return pushOpenPolicy(doc, buffer, arguments: arguments);
}

/// Pushes [buffer] onto the active window; an empty tab gets its first
/// window.
List<WindowingCommand> pushOpenPolicy(WindowingDoc doc, BufferId buffer,
        {Map<String, String> arguments = const {}}) =>
    switch (doc.activeTab.activeWindowId) {
      final w? => [PushBuffer(w, buffer, arguments: arguments)],
      null => _firstWindow(doc, buffer, arguments),
    };

/// Opens [buffer] in a new window beside the active one; an empty tab gets
/// its first window.
List<WindowingCommand> splitBesideOpenPolicy(
        WindowingDoc doc, BufferId buffer,
        {Map<String, String> arguments = const {}}) =>
    switch (doc.activeTab.activeWindowId) {
      final w? => [
          SplitWindow(w,
              newWindowId: WindowId.generate(),
              axis: Axis.horizontal,
              buffer: buffer,
              arguments: arguments),
        ],
      null => _firstWindow(doc, buffer, arguments),
    };

/// Opens [buffer] in a new tab of the focused shell.
List<WindowingCommand> newTabOpenPolicy(WindowingDoc doc, BufferId buffer,
        {Map<String, String> arguments = const {}}) =>
    [
      NewTab(
          shellId: doc.focusedShellId,
          tabId: TabId.generate(),
          buffer: (WindowId.generate(), buffer),
          arguments: arguments),
    ];

/// Gives the focused shell's empty active tab a first window showing
/// [buffer], built in a scratch tab and moved in.
List<WindowingCommand> _firstWindow(
    WindowingDoc doc, BufferId buffer, Map<String, String> arguments) {
  final shell = doc.focusedShellId;
  final scratch = TabId.generate();
  final window = WindowId.generate();
  return [
    NewTab(
        shellId: shell,
        tabId: scratch,
        buffer: (window, buffer),
        arguments: arguments),
    MoveWindow(window, tabId: doc.shells[shell]!.activeTabId),
    CloseTab(scratch),
  ];
}

/// Compiles a resolved link to [buffer], carrying [arguments], against
/// [doc] into the commands [WindowingController.openLink] dispatches as one
/// batch; null opens [buffer] through [WindowingController.openPolicy].
typedef WindowingLinkPolicy = List<WindowingCommand>? Function(
    WindowingDoc doc, BufferId buffer, Map<String, String> arguments);

/// Focuses a window showing [buffer] with [arguments], in any shell, the
/// focused shell's first. When [buffer] shows only with other arguments,
/// opens another window beside the active one (ADR 0005); else null, so the
/// open policy decides.
List<WindowingCommand>? defaultLinkPolicy(
    WindowingDoc doc, BufferId buffer, Map<String, String> arguments) {
  final any = doc.windowsShowing(buffer);
  if (any.isEmpty) return null;
  final shown = any
      .where((w) =>
          mapEquals(doc.windows[w]!.history.current.arguments, arguments))
      .toList();
  if (shown.isEmpty) {
    return splitBesideOpenPolicy(doc, buffer, arguments: arguments);
  }
  final here = shown.where((w) =>
      ActivateWindow(w).apply(doc).focusedShellId == doc.focusedShellId);
  return [ActivateWindow(here.firstOrNull ?? shown.first)];
}

/// Compiles back with nothing left in the active window's history into
/// commands for [WindowingController.back]; null leaves back unhandled, so
/// system back reaches the platform.
typedef EmptyBackPolicy = List<WindowingCommand>? Function(WindowingDoc doc);

/// Does nothing; back reports handled.
List<WindowingCommand>? emptyBackNothing(WindowingDoc doc) => const [];

/// Closes the active window; back reports handled.
List<WindowingCommand>? emptyBackCloseWindow(WindowingDoc doc) => [
      if (doc.activeWindowId case final w?) CloseWindow(w),
    ];

/// Does nothing; back reports unhandled.
List<WindowingCommand>? emptyBackUnhandled(WindowingDoc doc) => null;

/// What close, split and back do to focus (spec §6). Each effect is
/// dispatched right after the command it reacts to was intercepted and
/// applied, and passes through the interceptor itself; the defaults add
/// nothing.
class WindowingFocusPolicy {
  const WindowingFocusPolicy({
    this.splitTakesFocus = true,
    this.closeEmptyTab = false,
    this.focusAfterClose,
    this.emptyBack = emptyBackNothing,
  });

  /// Whether the new window of a split takes focus; else the split window
  /// keeps it.
  final bool splitTakesFocus;

  /// Whether closing a tab's last tree window also closes the tab (a
  /// shell's last tab never closes).
  final bool closeEmptyTab;

  /// Picks, against the doc before the close, the window to focus when the
  /// active window [closed] closes; null keeps the reducer's neighbour.
  final WindowId? Function(WindowingDoc doc, WindowId closed)? focusAfterClose;

  /// What [WindowingController.back] does with nothing to go back to.
  final EmptyBackPolicy emptyBack;

  /// The commands to append after [command] took [before] to [after].
  List<WindowingCommand> _effects(
          WindowingDoc before, WindowingCommand command, WindowingDoc after) =>
      switch (command) {
        SplitWindow(:final windowId, :final newWindowId)
            when !splitTakesFocus && !before.windows.containsKey(newWindowId) &&
                after.windows.containsKey(newWindowId) =>
          [ActivateWindow(windowId)],
        CloseWindow(:final windowId) when !after.windows.containsKey(windowId) =>
          switch (before.tabOf(windowId)) {
            final tab? when closeEmptyTab && after.tabs[tab]?.root == null =>
              [CloseTab(tab)],
            final tab? when before.tabs[tab]!.activeWindowId == windowId =>
              [
                if (focusAfterClose?.call(before, windowId) case final w?)
                  ActivateWindow(w),
              ],
            _ => const [],
          },
        _ => const [],
      };
}

/// Returns the doc a [WindowingController] saves in place of [doc].
typedef WindowingPersistence = WindowingDoc Function(WindowingDoc doc);

/// Owns the [WindowingDoc] and publishes it through [doc]. Pages call the
/// intent methods; [dispatch] and [dispatchAll] take commands directly.
class WindowingController {
  /// With [undo], each layout-changing batch records one entry on it
  /// (spec §4), published back through a [WindowingUndoHost].
  /// With [interceptor], every dispatched command is decided on first.
  /// With [platform], [openShell] opens real shells.
  /// With [store], it starts from the doc saved there and
  /// saves every published doc under [hibernationKey] (spec §11). A bad
  /// record is deleted and ignored. [persistence] shapes each saved doc
  /// and [extra] is saved next to it. [initial] runs only when nothing was
  /// restored; null, or a null result, starts from [WindowingDoc.initial].
  WindowingController({
    WindowingDoc? Function()? initial,
    UndoController? undo,
    this.interceptor,
    this.openPolicy = defaultOpenPolicy,
    this.linkPolicy = defaultLinkPolicy,
    this.focusPolicy = const WindowingFocusPolicy(),
    this.platform,
    HibernationStore? store,
    this.persistence = _saveWholeDoc,
  }) : _doc = ValueNotifier(
         _restore(store) ?? initial?.call() ?? WindowingDoc.initial(),
       ),
       _undo = undo,
       _store = store {
    undo?.registerHost<WindowingDoc>(WindowingUndoHost(_doc));
    // A discarded record was deleted by _restore, so it yields no extra.
    _extra = store?.load(hibernationKey)?['extra'];
    if (store != null) _doc.addListener(_save);
  }

  static WindowingDoc _saveWholeDoc(WindowingDoc doc) => doc;

  /// Turns the live doc into the doc that is saved; the live doc is kept.
  final WindowingPersistence persistence;

  Object? _extra;

  /// An app-owned JSON value saved next to the doc; restored from the
  /// record, null without one.
  Object? get extra => _extra;
  set extra(Object? value) {
    _extra = value;
    _save();
  }

  void _save() => _store?.save(hibernationKey, {
    ...persistence(_doc.value).toRecord(),
    'extra': _extra,
  });

  /// The reserved store id the doc hibernates under.
  static const hibernationKey = windowingHibernationKey;

  static WindowingDoc? _restore(HibernationStore? store) {
    final record = store?.load(hibernationKey);
    final doc = WindowingDoc.fromRecord(record);
    if (doc == null && record != null) store!.delete(hibernationKey);
    return doc;
  }

  final ValueNotifier<WindowingDoc> _doc;
  final UndoController? _undo;
  final HibernationStore? _store;

  /// Deletes the saved doc; the next published doc is saved again.
  void discardSavedLayout() => _store?.delete(hibernationKey);

  /// Opens and closes the real shells; null for a single-shell app.
  final ShellPlatform? platform;

  ShellCapabilities get capabilities =>
      ShellCapabilities(canPopOut: platform?.isSupported ?? false);

  ValueListenable<WindowingDoc> get doc => _doc;

  /// Decides on each dispatched command; undo and redo bypass it.
  WindowingInterceptor? interceptor;

  /// Decides where [openBuffer] puts a buffer.
  WindowingOpenPolicy openPolicy;

  /// Dispatches what [openPolicy] compiles for [buffer] as one batch.
  void openBuffer(BufferId buffer) =>
      dispatchAll(openPolicy(_doc.value, buffer));

  /// Decides what [openLink] does with a resolved buffer.
  WindowingLinkPolicy linkPolicy;

  /// Opens [buffer], a resolved link, with [arguments]. With [newShell]
  /// and pop-out support it opens in a new shell; otherwise, or when that
  /// shell fails to open, [linkPolicy] decides.
  Future<void> openLink(
    BufferId buffer, {
    Map<String, String> arguments = const {},
    bool newShell = false,
  }) async {
    if (newShell &&
        capabilities.canPopOut &&
        (await openShell(buffer: buffer, arguments: arguments)).isOk) {
      return;
    }
    final doc = _doc.value;
    dispatchAll(linkPolicy(doc, buffer, arguments) ??
        openPolicy(doc, buffer, arguments: arguments));
  }

  /// Decides what close, split and [back] do to focus.
  WindowingFocusPolicy focusPolicy;

  /// Steps the focused shell's active window back. With nothing to go back
  /// to in its window history,
  /// or without an active window, [focusPolicy] decides. Returns whether
  /// back was handled.
  bool back() {
    final window = _doc.value.activeTab.activeWindowId;
    if (window != null &&
        _doc.value.windows[window]!.history.back.isNotEmpty) {
      dispatch(PopBuffer(window));
      return true;
    }
    final commands = focusPolicy.emptyBack(_doc.value);
    if (commands == null) return false;
    dispatchAll(commands);
    return true;
  }

  final _vetoes = ValueNotifier<CommandVeto?>(null);

  /// The latest vetoed command; notifies on every veto.
  ValueListenable<CommandVeto?> get vetoes => _vetoes;

  void dispatch(WindowingCommand command) => dispatchAll([command]);

  /// Applies [commands] in order and publishes once, only when the resulting
  /// doc differs from the current one. Records one undo entry for the batch
  /// unless only focus or window history changed (navigation, not layout);
  /// a changed shell set clears the timeline.
  /// Consecutive batches with an equal [coalesceKey] merge into one entry.
  void dispatchAll(Iterable<WindowingCommand> commands,
          {Object? coalesceKey}) =>
      _dispatch(commands, coalesceKey: coalesceKey);

  /// [dispatchAll], publishing only when [accept] (if given) takes the
  /// intercepted result. Returns whether it did; vetoes surface either way.
  bool _dispatch(Iterable<WindowingCommand> commands,
      {Object? coalesceKey, bool Function(WindowingDoc next)? accept}) {
    final before = _doc.value;
    final vetoes = <CommandVeto>[];
    WindowingDoc step(WindowingDoc doc, WindowingCommand c) {
      final after = _intercepted(doc, c, vetoes);
      return focusPolicy._effects(doc, c, after).fold(after, step);
    }

    final next = commands.fold(before, step);
    final accepted = accept?.call(next) ?? true;
    if (accepted && next != before) _publish(before, next, coalesceKey);
    // After the doc, so veto listeners read the batch result.
    for (final veto in vetoes) {
      _vetoes.value = veto;
    }
    return accepted;
  }

  void _publish(WindowingDoc before, WindowingDoc next, Object? coalesceKey) {
    if (_undo case final undo?) {
      if (!setEquals(next.shells.keys.toSet(), before.shells.keys.toSet())) {
        undo.clearHost<WindowingDoc>(); // layout undo never crosses a pop-out
      } else if (_withNavigationFrom(next, source: before) != before) {
        undo.record(UndoEntry<WindowingDoc>(
          label: const UndoLabel('Change layout'),
          snapshotBefore: before,
          snapshotAfter: next,
          coalesceKey: coalesceKey,
        ));
      }
    }
    _doc.value = next;
    // Doc-first: real shells close only after the doc dropped them.
    if (platform case final platform?) {
      before.shells.keys
          .where((id) => !next.shells.containsKey(id))
          .forEach(platform.close);
    }
  }

  WindowingDoc _intercepted(WindowingDoc doc, WindowingCommand command,
      List<CommandVeto> vetoes) {
    switch (interceptor?.call(doc, command)) {
      case null || _Approve():
        return command.apply(doc);
      case _Replace(:final command):
        return command.apply(doc);
      case _Veto(:final reason):
        vetoes.add(CommandVeto(command, reason));
        return doc;
    }
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
  /// The platform shell is not opened here; [openShell] and [popOutTab] do.
  ShellId attachShell() {
    final shell = ShellId.generate();
    dispatch(AttachShell(shell, tabId: TabId.generate()));
    return shell;
  }

  /// Opens a real shell, then attaches it to the doc holding one empty tab,
  /// or one tab showing [buffer], and focuses it. Returns its id. Fails with
  /// `unsupported` without a supported platform, with the platform's error
  /// when the open fails (the doc is untouched), and with `refused` when an
  /// interceptor keeps the batch from landing whole (the real shell closes).
  Future<Result<ShellError, ShellId>> openShell(
      {BufferId? buffer, Map<String, String> arguments = const {}}) {
    final tab = TabId.generate();
    if (buffer == null) {
      return _openShellWith((shell) => [AttachShell(shell, tabId: tab)], tab);
    }
    final shown = TabId.generate();
    return _openShellWith(
      (shell) => [
        AttachShell(shell, tabId: tab),
        NewTab(
            shellId: shell,
            tabId: shown,
            buffer: (WindowId.generate(), buffer),
            arguments: arguments),
        CloseTab(tab),
      ],
      shown,
    );
  }

  /// Opens a real shell, then moves [tabId] into it as its only tab, in one
  /// batch, and focuses it. Returns its id. Fails like [openShell], and with
  /// `refused` before opening anything when the doc would refuse the move
  /// (an unknown tab, or a shell's last tab).
  Future<Result<ShellError, ShellId>> popOutTab(TabId tabId) {
    final placeholder = TabId.generate();
    return _openShellWith(
      (shell) => [
        AttachShell(shell, tabId: placeholder),
        MoveTab(tabId, shellId: shell, index: 1),
        CloseTab(placeholder),
      ],
      tabId,
    );
  }

  /// Opens a real shell and applies [batchFor] it, all or nothing: the batch
  /// lands only when the new shell then holds exactly [onlyTab]. Refused
  /// before opening when the bare doc would not land it; when an interceptor
  /// keeps it from landing, nothing is published and the real shell closes.
  Future<Result<ShellError, ShellId>> _openShellWith(
      List<WindowingCommand> Function(ShellId shell) batchFor,
      TabId onlyTab) async {
    final platform = this.platform;
    if (platform == null || !platform.isSupported) {
      return const Err(ShellError(ShellErrorKind.unsupported));
    }
    final shell = ShellId.generate();
    final batch = batchFor(shell);
    bool landed(WindowingDoc doc) =>
        listEquals(doc.shells[shell]?.tabIds, [onlyTab]);
    if (!landed(batch.fold(_doc.value, (doc, c) => c.apply(doc)))) {
      return const Err(ShellError(ShellErrorKind.refused));
    }
    if (await platform.open(shell) case Err(:final value)) return Err(value);
    if (!_dispatch(batch, accept: landed)) {
      platform.close(shell);
      return const Err(ShellError(ShellErrorKind.refused));
    }
    return Ok(shell);
  }

  void activateShell(ShellId shellId) => dispatch(ActivateShell(shellId));

  void closeShell(ShellId shellId) => dispatch(CloseShell(shellId));

  void activateWindow(WindowId windowId) => dispatch(ActivateWindow(windowId));

  void moveWindow(WindowId windowId,
          {required TabId tabId,
          WindowId? target,
          Axis axis = Axis.horizontal,
          DockSide side = DockSide.after}) =>
      dispatch(MoveWindow(windowId,
          tabId: tabId, target: target, axis: axis, side: side));

  /// Splits [windowId] along [axis]. Returns the new window's id.
  WindowId splitWindow(WindowId windowId,
      {required Axis axis, BufferId? buffer}) {
    final window = WindowId.generate();
    dispatch(SplitWindow(windowId,
        newWindowId: window, axis: axis, buffer: buffer));
    return window;
  }

  void closeWindow(WindowId windowId) => dispatch(CloseWindow(windowId));

  void floatWindow(WindowId windowId, {required FloatScope scope}) =>
      dispatch(FloatWindow(windowId, scope: scope));

  void dockWindow(WindowId windowId,
          {required TabId tabId,
          WindowId? target,
          Axis axis = Axis.horizontal,
          DockSide side = DockSide.after}) =>
      dispatch(DockWindow(windowId,
          tabId: tabId, target: target, axis: axis, side: side));

  void raiseWindow(WindowId windowId) => dispatch(RaiseWindow(windowId));

  void moveFloating(WindowId windowId, Rect geometry,
          {Object? coalesceKey}) =>
      dispatchAll([MoveFloating(windowId, geometry)],
          coalesceKey: coalesceKey);

  void resizeWindow(WindowId windowId, List<double> ratios,
          {int levels = 0, Object? coalesceKey}) =>
      dispatchAll([ResizeWindow(windowId, ratios, levels: levels)],
          coalesceKey: coalesceKey);

  /// Ends the current coalescing run on the undo timeline, if any: the next
  /// batch is its own undo step.
  void sealCoalescing() => _undo?.sealCoalescing();

  void attachBuffer(WindowId windowId, BufferId buffer) =>
      dispatch(AttachBuffer(windowId, buffer));

  void pushBuffer(WindowId windowId, BufferId buffer,
          {Map<String, String> arguments = const {}}) =>
      dispatch(PushBuffer(windowId, buffer, arguments: arguments));

  void popBuffer(WindowId windowId) => dispatch(PopBuffer(windowId));

  void navigateForward(WindowId windowId) =>
      dispatch(NavigateForward(windowId));

  void replaceBuffer(WindowId windowId, BufferId buffer) =>
      dispatch(ReplaceBuffer(windowId, buffer));

  void dispose() {
    _doc.dispose();
    _vetoes.dispose();
  }
}

/// [doc] with [focusSource]'s focused shell, active tabs and active windows, so
/// comparing it to [focusSource] ignores focus-only changes.
WindowingDoc _withFocusFrom(WindowingDoc doc,
        {required WindowingDoc focusSource}) =>
    doc.copyWith(
      focusedShellId: focusSource.focusedShellId,
      shells: doc.shells.map((id, s) => MapEntry(
          id,
          ShellState(
              tabIds: s.tabIds,
              activeTabId: focusSource.shells[id]?.activeTabId ?? s.activeTabId))),
      tabs: doc.tabs.map((id, t) => MapEntry(
          id,
          TabState(
              root: t.root,
              activeWindowId: focusSource.tabs[id]?.activeWindowId ??
                  t.activeWindowId))),
    );

/// [doc] with focus, and the history of each window [source] also has, taken
/// from [source]: equal to [source] when only navigation changed.
WindowingDoc _withNavigationFrom(WindowingDoc doc,
        {required WindowingDoc source}) =>
    _withFocusFrom(doc, focusSource: source).copyWith(
      windows: doc.windows.map((id, w) => MapEntry(id, source.windows[id] ?? w)),
    );

/// Publishes [WindowingDoc] snapshots into a controller's doc without
/// recording them.
class WindowingUndoHost implements UndoHost<WindowingDoc> {
  WindowingUndoHost(this._doc);

  final ValueNotifier<WindowingDoc> _doc;

  @override
  void undo(WindowingDoc snapshotBefore) => _doc.value = snapshotBefore;

  @override
  void redo(WindowingDoc snapshotAfter) => _doc.value = snapshotAfter;
}
