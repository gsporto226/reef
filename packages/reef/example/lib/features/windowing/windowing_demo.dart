import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reef/reef.dart';
import 'package:reef_example/undo_providers.dart';

/// A playground over a [WindowingController]: shells and tabs across the top,
/// the active tab's window tree in the middle (drag the dividers to resize),
/// its floating windows on top, and the focus chain in the status bar. Every
/// control dispatches one controller intent. Drives the windowing integration
/// flow. Needs a [MaterialApp] and a [ProviderScope] above it; Undo and Redo
/// drive [undoControllerProvider], which [controller] must record on.
class WindowingDemo extends ConsumerStatefulWidget {
  const WindowingDemo({super.key, required this.controller});

  final WindowingController controller;

  @override
  ConsumerState<WindowingDemo> createState() => _WindowingDemoState();
}

class _WindowingDemoState extends ConsumerState<WindowingDemo> {
  WindowingController get _c => widget.controller;
  UndoController get _undo => ref.read(undoControllerProvider);
  int _buffers = 0;

  BufferId _nextBuffer() => BufferId.manual('buffer ${++_buffers}');

  @override
  Widget build(BuildContext context) => WindowingRoot(
    controller: _c,
    bufferBuilder: (context, _) =>
        _windowBody(_c.doc.value, WindowHost.of(context)),
    delegate: WindowingDelegate(
      windowChrome: _chrome,
      tabStrip: (context, shellId) => _tabBar(_c.doc.value, shellId),
      interceptor: _atMostFourWindows,
      emptyBuilder: (_, _) => const Center(
        child: Text('Empty tab: dock a floating window here, or close it'),
      ),
    ),
    child: ValueListenableBuilder<WindowingDoc>(
      valueListenable: _c.doc,
      builder: (context, doc, _) {
        final shellIds = doc.shells.keys.toList();
        final shell = doc.shells[doc.focusedShellId]!;
        return Column(
          children: [
            _shellBar(doc, shellIds),
            Builder(
              builder: (context) =>
                  WindowingDelegateScope.of(context)
                      .tabStrip(context, doc.focusedShellId),
            ),
            const Divider(height: 1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: ShellHost(doc.focusedShellId),
              ),
            ),
            _statusBar(doc, shellIds, shell),
          ],
        );
      },
    ),
  );

  Widget _shellBar(WindowingDoc doc, List<ShellId> shellIds) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          const Text('Shells'),
          const SizedBox(width: 8),
          for (final (i, id) in shellIds.indexed) ...[
            InputChip(
              label: Text('Shell ${i + 1}'),
              selected: id == doc.focusedShellId,
              onPressed: () => _c.activateShell(id),
              onDeleted: shellIds.length > 1 ? () => _c.closeShell(id) : null,
              deleteButtonTooltipMessage: 'Close shell ${i + 1}',
            ),
            const SizedBox(width: 4),
          ],
          IconButton(
            tooltip: 'New shell',
            icon: const Icon(Icons.add_to_queue),
            onPressed: _c.attachShell,
          ),
          const Spacer(),
          _undoButton('Undo', Icons.undo, _undo.$canUndo, _undo.undo),
          _undoButton('Redo', Icons.redo, _undo.$canRedo, _undo.redo),
        ],
      ),
    );
  }

  /// The delegate's tab strip: chips over [TabStripSlot], plus new-tab and
  /// move-to-shell controls.
  Widget _tabBar(WindowingDoc doc, ShellId shellId) {
    final scheme = Theme.of(context).colorScheme;
    final shellIds = doc.shells.keys.toList();
    return TabStripSlot(
      shellId,
      builder: (context, strip) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            for (final (i, id) in strip.tabIds.indexed) ...[
              InputChip(
                label: Text('Tab ${i + 1}'),
                selected: id == strip.activeTabId,
                selectedColor: scheme.primaryContainer,
                onPressed: () => strip.activate(id),
                onDeleted: () => strip.close(id),
                deleteButtonTooltipMessage: 'Close tab ${i + 1}',
              ),
              const SizedBox(width: 4),
            ],
            IconButton(
              tooltip: 'New tab',
              icon: const Icon(Icons.add),
              onPressed: () => _c.newTab(buffer: _nextBuffer()),
            ),
            const Spacer(),
            if (shellIds.length > 1)
              PopupMenuButton<ShellId>(
                tooltip: 'Move tab to shell',
                icon: const Icon(Icons.drive_file_move_outline),
                onSelected: (to) => _c.moveTab(
                  strip.activeTabId,
                  shellId: to,
                  index: doc.shells[to]!.tabIds.length,
                ),
                itemBuilder: (_) => [
                  for (final (i, id) in shellIds.indexed)
                    if (id != shellId)
                      PopupMenuItem(
                        value: id,
                        child: Text('To shell ${i + 1}'),
                      ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// The delegate's window chrome: the window's header over its page, inside
  /// the default focus border; floating windows on a raised card.
  Widget _chrome(
    BuildContext context,
    WindowId id,
    bool focused,
    Widget page,
  ) {
    final floating = _c.doc.value.floating.containsKey(id);
    final window = const WindowingDelegate().windowChrome(
      context,
      id,
      focused,
      Padding(
        padding: const EdgeInsets.all(2),
        child: Column(
          children: [
            _windowHeader(_c.doc.value, id, floating: floating),
            Expanded(child: page),
          ],
        ),
      ),
    );
    if (!floating) return window;
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      color: Theme.of(context).colorScheme.surface,
      child: window,
    );
  }

  Widget _windowHeader(
    WindowingDoc doc,
    WindowId id, {
    required bool floating,
  }) {
    final history = doc.windows[id]!.history;
    final shell = doc.shells[doc.focusedShellId]!;
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Row(
        children: [
          _icon(
            Icons.arrow_back,
            'Back',
            history.back.isEmpty ? null : () => _c.popBuffer(id),
          ),
          _icon(
            Icons.arrow_forward,
            'Forward',
            history.forward.isEmpty ? null : () => _c.navigateForward(id),
          ),
          Expanded(
            child: Text(
              history.current.value,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          _icon(
            Icons.note_add_outlined,
            'Open new buffer',
            () => _c.pushBuffer(id, _nextBuffer()),
          ),
          if (floating)
            PopupMenuButton<(Axis, DockSide)>(
              tooltip: 'Dock',
              icon: const Icon(Icons.vertical_split_outlined, size: 18),
              onSelected: (to) => _c.dockWindow(
                id,
                tabId: shell.activeTabId,
                axis: to.$1,
                side: to.$2,
              ),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: (Axis.horizontal, DockSide.before),
                  child: Text('Dock left'),
                ),
                PopupMenuItem(
                  value: (Axis.horizontal, DockSide.after),
                  child: Text('Dock right'),
                ),
                PopupMenuItem(
                  value: (Axis.vertical, DockSide.before),
                  child: Text('Dock top'),
                ),
                PopupMenuItem(
                  value: (Axis.vertical, DockSide.after),
                  child: Text('Dock bottom'),
                ),
              ],
            )
          else ...[
            _icon(
              Icons.splitscreen_outlined,
              'Split right',
              () => _c.splitWindow(id, axis: Axis.horizontal),
              quarterTurns: 1,
            ),
            _icon(
              Icons.splitscreen_outlined,
              'Split down',
              () => _c.splitWindow(id, axis: Axis.vertical),
            ),
            PopupMenuButton<FloatScope>(
              tooltip: 'Float',
              icon: const Icon(Icons.picture_in_picture_alt_outlined, size: 18),
              onSelected: (scope) => _c.floatWindow(id, scope: scope),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: TabScope(shell.activeTabId),
                  child: const Text('Float over tab'),
                ),
                PopupMenuItem(
                  value: ShellScope(doc.focusedShellId),
                  child: const Text('Float over shell'),
                ),
              ],
            ),
            _moveMenu(doc, id),
          ],
          _icon(Icons.close, 'Close window', () => _c.closeWindow(id)),
        ],
      ),
    );
  }

  Widget _moveMenu(WindowingDoc doc, WindowId id) {
    final targets = [
      for (final (s, shellId) in doc.shells.keys.indexed)
        for (final (t, tabId) in doc.shells[shellId]!.tabIds.indexed)
          (tabId, 'Shell ${s + 1}, tab ${t + 1}'),
    ];
    return PopupMenuButton<TabId>(
      tooltip: 'Move to tab',
      icon: const Icon(Icons.open_in_new, size: 18),
      onSelected: (tabId) => _c.moveWindow(id, tabId: tabId),
      itemBuilder: (_) => [
        for (final (tabId, label) in targets)
          PopupMenuItem(value: tabId, child: Text('To $label')),
      ],
    );
  }

  Widget _windowBody(WindowingDoc doc, WindowId id) {
    final h = doc.windows[id]!.history;
    final style = Theme.of(context).textTheme.bodySmall;
    return Center(
      child: Text(
        'back: ${h.back.map((b) => b.value).join(', ')}\n'
        'forward: ${h.forward.map((b) => b.value).join(', ')}',
        textAlign: TextAlign.center,
        style: style,
      ),
    );
  }

  /// The playground's app rule: a split that would put a fifth window in a
  /// tab is vetoed, and the status bar shows why.
  static CommandDecision _atMostFourWindows(
    WindowingDoc doc,
    WindowingCommand command,
  ) => command is SplitWindow &&
          doc.tabs.values.any(
            (t) => (t.root?.windowIds.length ?? 0) >= 4 &&
                t.root!.windowIds.contains(command.windowId),
          )
      ? const CommandDecision.veto(UndoLabel('At most 4 windows per tab'))
      : const CommandDecision.approve();

  Widget _statusBar(
    WindowingDoc doc,
    List<ShellId> shellIds,
    ShellState shell,
  ) {
    final tab = doc.tabs[shell.activeTabId]!;
    final window = tab.activeWindowId;
    final chain = [
      'Shell ${shellIds.indexOf(doc.focusedShellId) + 1}',
      'Tab ${shell.tabIds.indexOf(shell.activeTabId) + 1}',
      if (window != null) doc.windows[window]!.history.current.value,
    ].join(' > ');
    final bar = Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text(
        'Focus: $chain    '
        'windows in tab: ${tab.root?.windowIds.length ?? 0}    '
        'floating: ${doc.floating.length}',
      ),
    );
    return Column(
      children: [
        ValueListenableBuilder<CommandVeto?>(
          valueListenable: _c.vetoes,
          builder: (_, veto, _) => veto == null
              ? const SizedBox.shrink()
              : Text('Vetoed: ${veto.reason.localize()}'),
        ),
        bar,
      ],
    );
  }

  Widget _undoButton(
    String tooltip,
    IconData icon,
    ValueListenable<bool> enabled,
    VoidCallback action,
  ) => ValueListenableBuilder<bool>(
    valueListenable: enabled,
    builder: (_, on, _) => IconButton(
      tooltip: tooltip,
      icon: Icon(icon),
      onPressed: on ? action : null,
    ),
  );

  Widget _icon(
    IconData icon,
    String tooltip,
    VoidCallback? onPressed, {
    int quarterTurns = 0,
  }) => IconButton(
    tooltip: tooltip,
    visualDensity: VisualDensity.compact,
    iconSize: 18,
    icon: RotatedBox(quarterTurns: quarterTurns, child: Icon(icon)),
    onPressed: onPressed,
  );
}
