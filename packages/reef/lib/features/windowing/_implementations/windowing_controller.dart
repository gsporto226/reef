import 'package:flutter/foundation.dart';
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
      tabs: {...doc.tabs, tabId: TabState(root: window, activeWindowId: window)},
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
      windows: {...doc.windows}..remove(root),
    );
  }
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

  void dispose() => _doc.dispose();
}
