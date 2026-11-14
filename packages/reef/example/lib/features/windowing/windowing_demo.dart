import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reef/reef.dart';
import 'package:reef_example/undo_providers.dart';

/// The windowing playground's root: a [WindowingRoot] over [controller] with
/// the playground's delegate (window headers, tab bar, app rules, the
/// projection switch). Place it above every shell's view, with a
/// [PlaygroundShell] per shell below it and a [ProviderScope] above; Undo and
/// Redo drive [undoControllerProvider], which [controller] must record on.
class WindowingPlayground extends ConsumerStatefulWidget {
  const WindowingPlayground({
    super.key,
    required this.controller,
    required this.child,
  });

  final WindowingController controller;
  final Widget child;

  @override
  ConsumerState<WindowingPlayground> createState() =>
      _WindowingPlaygroundState();
}

/// Shell [shellId]'s surface in the playground: the shell controls and the
/// projection switch across the top, the shell as its projection lays it out
/// in the middle (drag the dividers to resize), its focus chain and the
/// latest veto in the status bar. Every control dispatches one controller
/// intent. Needs a [WindowingPlayground] above it.
class PlaygroundShell extends StatelessWidget {
  const PlaygroundShell(this.shellId, {super.key});

  final ShellId shellId;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Reef windowing',
    theme: ThemeData(useMaterial3: true),
    home: Scaffold(
      body: Builder(
        builder: (context) => context
            .findAncestorStateOfType<_WindowingPlaygroundState>()!
            ._shell(context, shellId),
      ),
    ),
  );
}

class _WindowingPlaygroundState extends ConsumerState<WindowingPlayground> {
  WindowingController get _c => widget.controller;
  UndoController get _undo => ref.read(undoControllerProvider);
  int _buffers = 0;

  /// The projection switch by the name it is saved under in the
  /// `playground` restoration bucket.
  static const _projections = {
    'auto': defaultWindowingProjection,
    'desktop': _desktop,
    'tabbed': _tabbed,
  };

  /// The projection switch: by screen class, or forced.
  late WindowingProjectionPolicy _policy =
      _projections[_projection.value] ?? defaultWindowingProjection;

  final _projection = ReefRestorableValue('auto');

  @override
  void initState() {
    super.initState();
    _c.restoration.claimChild('playground').register('projection', _projection);
  }

  @override
  void dispose() {
    _c.restoration.claimChild('playground').unregister('projection');
    _projection.dispose();
    super.dispose();
  }

  BufferId _nextBuffer() => BufferId.manual('buffer ${++_buffers}');

  @override
  Widget build(BuildContext context) => WindowingRoot(
    controller: _c,
    bufferBuilder: (context, _) =>
        _windowBody(context, _c.doc.value, WindowHost.of(context)),
    delegate: WindowingDelegate(
      windowChrome: _chrome,
      tabStrip: (context, shellId) => _tabBar(context, _c.doc.value, shellId),
      interceptor: _rules,
      projectionPolicy: _policy,
      emptyBuilder: (_, _) => const Center(
        child: Text('Empty tab: dock a floating window here, or close it'),
      ),
    ),
    child: widget.child,
  );

  Widget _shell(BuildContext context, ShellId shellId) => WindowingShortcuts(
    undo: _undo,
    child: ValueListenableBuilder<WindowingDoc>(
      valueListenable: _c.doc,
      builder: (context, doc, _) => Column(
        children: [
          _shellBar(context, doc, shellId),
          const Divider(height: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: ShellProjection(shellId),
            ),
          ),
          _statusBar(context, doc, shellId),
        ],
      ),
    ),
  );

  static WindowingProjection _desktop(
    BuildContext _,
    WindowingController _,
    ShellId _,
  ) => (_, _, shellId) => DesktopProjection(shellId);

  static WindowingProjection _tabbed(
    BuildContext _,
    WindowingController _,
    ShellId _,
  ) => (_, _, shellId) => TabbedProjection(shellId);

  Widget _shellBar(BuildContext context, WindowingDoc doc, ShellId shellId) {
    final scheme = Theme.of(context).colorScheme;
    final number = doc.shells.keys.toList().indexOf(shellId) + 1;
    return Container(
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Text('Shell $number'),
          const SizedBox(width: 8),
          if (_c.capabilities.canPopOut)
            IconButton(
              tooltip: 'New shell',
              icon: const Icon(Icons.add_to_queue),
              onPressed: _c.openShell,
            ),
          if (doc.shells.length > 1)
            IconButton(
              tooltip: 'Close shell',
              icon: const Icon(Icons.cancel_presentation),
              onPressed: () => _c.closeShell(shellId),
            ),
          const Spacer(),
          PopupMenuButton<WindowingProjectionPolicy>(
            tooltip: 'Projection',
            icon: const Icon(Icons.view_quilt_outlined),
            initialValue: WindowingDelegateScope.of(context).projectionPolicy,
            onSelected: (policy) {
              setState(() => _policy = policy);
              _projection.value = _projections.entries
                  .firstWhere((e) => e.value == policy)
                  .key;
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: defaultWindowingProjection,
                child: Text('Auto'),
              ),
              PopupMenuItem(value: _desktop, child: Text('Desktop')),
              PopupMenuItem(value: _tabbed, child: Text('Tabbed')),
            ],
          ),
          _undoButton('Undo', Icons.undo, _undo.$canUndo, _undo.undo),
          _undoButton('Redo', Icons.redo, _undo.$canRedo, _undo.redo),
        ],
      ),
    );
  }

  /// The delegate's tab strip: chips over [TabStripSlot], plus new-tab,
  /// pop-out and move-to-shell controls.
  Widget _tabBar(BuildContext context, WindowingDoc doc, ShellId shellId) {
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
            if (_c.capabilities.canPopOut)
              IconButton(
                tooltip: 'Pop out tab',
                icon: const Icon(Icons.open_in_new),
                onPressed: () => _c.popOutTab(strip.activeTabId),
              ),
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
            _windowHeader(context, _c.doc.value, id, floating: floating),
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
    BuildContext context,
    WindowingDoc doc,
    WindowId id, {
    required bool floating,
  }) {
    final history = doc.windows[id]!.history;
    final shellId = context
        .findAncestorWidgetOfExactType<PlaygroundShell>()!
        .shellId;
    final shell = doc.shells[shellId]!;
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
              history.current.buffer.value,
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
                  value: ShellScope(shellId),
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
      icon: const Icon(Icons.low_priority, size: 18),
      onSelected: (tabId) => _c.moveWindow(id, tabId: tabId),
      itemBuilder: (_) => [
        for (final (tabId, label) in targets)
          PopupMenuItem(value: tabId, child: Text('To $label')),
      ],
    );
  }

  Widget _windowBody(BuildContext context, WindowingDoc doc, WindowId id) {
    final h = doc.windows[id]!.history;
    final style = Theme.of(context).textTheme.bodySmall;
    return Center(
      child: Text(
        'back: ${h.back.map((e) => e.buffer.value).join(', ')}\n'
        'forward: ${h.forward.map((e) => e.buffer.value).join(', ')}',
        textAlign: TextAlign.center,
        style: style,
      ),
    );
  }

  /// The playground's app rules: a split that would put a fifth window in a
  /// tab and closing a shell that holds more than one tab are vetoed, and
  /// the status bar shows why.
  static CommandDecision _rules(WindowingDoc doc, WindowingCommand command) =>
      switch (command) {
        SplitWindow(:final windowId)
            when doc.tabs.values.any(
              (t) =>
                  (t.root?.windowIds.length ?? 0) >= 4 &&
                  t.root!.windowIds.contains(windowId),
            ) =>
          const CommandDecision.veto(UndoLabel('At most 4 windows per tab')),
        CloseShell(:final shellId)
            when (doc.shells[shellId]?.tabIds.length ?? 0) > 1 =>
          const CommandDecision.veto(
            UndoLabel("Close the shell's other tabs first"),
          ),
        _ => const CommandDecision.approve(),
      };

  /// Shell [shellId]'s own focus chain, with the latest veto above it.
  Widget _statusBar(BuildContext context, WindowingDoc doc, ShellId shellId) {
    final shell = doc.shells[shellId]!;
    final tab = doc.tabs[shell.activeTabId]!;
    final window = tab.activeWindowId;
    final chain = [
      'Shell ${doc.shells.keys.toList().indexOf(shellId) + 1}',
      'Tab ${shell.tabIds.indexOf(shell.activeTabId) + 1}',
      if (window != null) doc.windows[window]!.history.current.buffer.value,
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
