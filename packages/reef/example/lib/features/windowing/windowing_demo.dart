import 'package:flutter/material.dart';
import 'package:reef/reef.dart';

/// A playground over a [WindowingController]: shells and tabs across the top,
/// the active tab's window tree in the middle (drag the dividers to resize),
/// its floating windows on top, and the focus chain in the status bar. Every
/// control dispatches one controller intent. Drives the windowing integration
/// flow. Needs a [MaterialApp] above it.
class WindowingDemo extends StatefulWidget {
  const WindowingDemo({super.key, required this.controller});

  final WindowingController controller;

  @override
  State<WindowingDemo> createState() => _WindowingDemoState();
}

class _WindowingDemoState extends State<WindowingDemo> {
  WindowingController get _c => widget.controller;
  int _buffers = 0;

  /// Where each floating window is drawn. Placement is view state, not doc
  /// state (W1 has no geometry).
  final _positions = <WindowId, Offset>{};

  BufferId _nextBuffer() => BufferId.manual('buffer ${++_buffers}');

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<WindowingDoc>(
        valueListenable: _c.doc,
        builder: (context, doc, _) {
          final shellIds = doc.shells.keys.toList();
          final shell = doc.shells[doc.focusedShellId]!;
          final tab = doc.tabs[shell.activeTabId]!;
          return Column(children: [
            _shellBar(doc, shellIds),
            _tabBar(doc, shellIds, shell),
            const Divider(height: 1),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) => Stack(children: [
                  Positioned.fill(
                    child: tab.root == null
                        ? const Center(
                            child: Text('Empty tab: dock a floating window '
                                'here, or close it'),
                          )
                        : Padding(
                            padding: const EdgeInsets.all(4),
                            child: _node(doc, tab, tab.root!),
                          ),
                  ),
                  for (final (i, w) in _visibleFloating(doc, shell).indexed)
                    _floating(doc, shell, w, i, box.biggest),
                ]),
              ),
            ),
            _statusBar(doc, shellIds, shell),
          ]);
        },
      );

  Widget _shellBar(WindowingDoc doc, List<ShellId> shellIds) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(children: [
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
      ]),
    );
  }

  Widget _tabBar(WindowingDoc doc, List<ShellId> shellIds, ShellState shell) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(children: [
        for (final (i, id) in shell.tabIds.indexed) ...[
          InputChip(
            label: Text('Tab ${i + 1}'),
            selected: id == shell.activeTabId,
            selectedColor: scheme.primaryContainer,
            onPressed: () => _c.activateTab(id),
            onDeleted: () => _c.closeTab(id),
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
            onSelected: (to) => _c.moveTab(shell.activeTabId,
                shellId: to, index: doc.shells[to]!.tabIds.length),
            itemBuilder: (_) => [
              for (final (i, id) in shellIds.indexed)
                if (id != doc.focusedShellId)
                  PopupMenuItem(value: id, child: Text('To shell ${i + 1}')),
            ],
          ),
      ]),
    );
  }

  Widget _node(WindowingDoc doc, TabState tab, WindowNode node) =>
      switch (node) {
        WindowLeaf(:final id) => _window(doc, tab, id),
        WindowBranch() => _branch(doc, tab, node),
      };

  Widget _branch(WindowingDoc doc, TabState tab, WindowBranch branch) {
    // ResizeWindow addresses a branch through a window directly inside it.
    final handle = branch.children.whereType<WindowLeaf>().firstOrNull?.id;
    return LayoutBuilder(builder: (context, box) {
      final extent =
          branch.axis == Axis.horizontal ? box.maxWidth : box.maxHeight;
      return Flex(direction: branch.axis, children: [
        for (final (i, child) in branch.children.indexed) ...[
          if (i > 0)
            _Divider(
              key: const ValueKey('divider'),
              axis: branch.axis,
              ratios: branch.ratios,
              onDrag: handle == null
                  ? null
                  : (start, offset) => _c.resizeWindow(
                      handle, _shift(start, i - 1, offset / extent)),
            ),
          Expanded(
            flex: (branch.ratios[i] * 1000).round(),
            child: _node(doc, tab, child),
          ),
        ],
      ]);
    });
  }

  Widget _window(WindowingDoc doc, TabState tab, WindowId id) {
    final scheme = Theme.of(context).colorScheme;
    final active = id == tab.activeWindowId;
    return Padding(
      padding: const EdgeInsets.all(2),
      child: GestureDetector(
        onTap: () => _c.activateWindow(id),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: active ? scheme.primary : scheme.outlineVariant,
              width: active ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(children: [
            _windowHeader(doc, id, floating: false),
            Expanded(child: _windowBody(doc, id)),
          ]),
        ),
      ),
    );
  }

  Widget _windowHeader(WindowingDoc doc, WindowId id,
      {required bool floating}) {
    final history = doc.windows[id]!.history;
    final shell = doc.shells[doc.focusedShellId]!;
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Row(children: [
        _icon(Icons.arrow_back, 'Back',
            history.back.isEmpty ? null : () => _c.popBuffer(id)),
        _icon(Icons.arrow_forward, 'Forward',
            history.forward.isEmpty ? null : () => _c.navigateForward(id)),
        Expanded(
          child: Text(history.current.value,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        _icon(Icons.note_add_outlined, 'Open new buffer',
            () => _c.pushBuffer(id, _nextBuffer())),
        if (floating)
          PopupMenuButton<(Axis, DockSide)>(
            tooltip: 'Dock',
            icon: const Icon(Icons.vertical_split_outlined, size: 18),
            onSelected: (to) => _c.dockWindow(id,
                tabId: shell.activeTabId, axis: to.$1, side: to.$2),
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: (Axis.horizontal, DockSide.before),
                  child: Text('Dock left')),
              PopupMenuItem(
                  value: (Axis.horizontal, DockSide.after),
                  child: Text('Dock right')),
              PopupMenuItem(
                  value: (Axis.vertical, DockSide.before),
                  child: Text('Dock top')),
              PopupMenuItem(
                  value: (Axis.vertical, DockSide.after),
                  child: Text('Dock bottom')),
            ],
          )
        else ...[
          _icon(Icons.splitscreen_outlined, 'Split right',
              () => _c.splitWindow(id, axis: Axis.horizontal),
              quarterTurns: 1),
          _icon(Icons.splitscreen_outlined, 'Split down',
              () => _c.splitWindow(id, axis: Axis.vertical)),
          PopupMenuButton<FloatScope>(
            tooltip: 'Float',
            icon: const Icon(Icons.picture_in_picture_alt_outlined, size: 18),
            onSelected: (scope) => _c.floatWindow(id, scope: scope),
            itemBuilder: (_) => [
              PopupMenuItem(
                  value: TabScope(shell.activeTabId),
                  child: const Text('Float over tab')),
              PopupMenuItem(
                  value: ShellScope(doc.focusedShellId),
                  child: const Text('Float over shell')),
            ],
          ),
          _moveMenu(doc, id),
        ],
        _icon(Icons.close, 'Close window', () => _c.closeWindow(id)),
      ]),
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

  /// Floating windows over the focused shell, its active tab, or a window
  /// already on screen; bottom to top within each scope.
  List<WindowId> _visibleFloating(WindowingDoc doc, ShellState shell) {
    final visible = <Object>{
      ShellScope(doc.focusedShellId),
      TabScope(shell.activeTabId),
      ...?doc.tabs[shell.activeTabId]!.root?.windowIds.map(WindowScope.new),
    };
    final out = <WindowId>[];
    for (var grew = true; grew;) {
      final next = [
        for (final MapEntry(:key, :value) in doc.floating.entries)
          if (!out.contains(key) && visible.contains(value.scope)) key,
      ]..sort((a, b) =>
          doc.floating[a]!.zIndex.compareTo(doc.floating[b]!.zIndex));
      out.addAll(next);
      visible.addAll(next.map(WindowScope.new));
      grew = next.isNotEmpty;
    }
    return out;
  }

  Widget _floating(
      WindowingDoc doc, ShellState shell, WindowId id, int i, Size area) {
    final scheme = Theme.of(context).colorScheme;
    const size = Size(280, 160);
    final max = Offset((area.width - size.width).clamp(0, double.infinity),
        (area.height - size.height).clamp(0, double.infinity));
    Offset clamp(Offset p) =>
        Offset(p.dx.clamp(0, max.dx), p.dy.clamp(0, max.dy));
    final pos = clamp(_positions[id] ?? Offset(40 + 32.0 * i, 40 + 32.0 * i));
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      width: size.width,
      height: size.height,
      child: GestureDetector(
        onTap: () => _c.activateWindow(id),
        // Read the stored position, not the build-time one, so several pan
        // events in one frame all count.
        onPanUpdate: (d) => setState(
            () => _positions[id] = clamp((_positions[id] ?? pos) + d.delta)),
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          color: scheme.surface,
          child: Column(children: [
            _windowHeader(doc, id, floating: true),
            Expanded(child: _windowBody(doc, id)),
          ]),
        ),
      ),
    );
  }

  Widget _statusBar(
      WindowingDoc doc, List<ShellId> shellIds, ShellState shell) {
    final tab = doc.tabs[shell.activeTabId]!;
    final window = tab.activeWindowId;
    final chain = [
      'Shell ${shellIds.indexOf(doc.focusedShellId) + 1}',
      'Tab ${shell.tabIds.indexOf(shell.activeTabId) + 1}',
      if (window != null) doc.windows[window]!.history.current.value,
    ].join(' > ');
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text('Focus: $chain    '
          'windows in tab: ${tab.root?.windowIds.length ?? 0}    '
          'floating: ${doc.floating.length}'),
    );
  }

  Widget _icon(IconData icon, String tooltip, VoidCallback? onPressed,
          {int quarterTurns = 0}) =>
      IconButton(
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        iconSize: 18,
        icon: RotatedBox(quarterTurns: quarterTurns, child: Icon(icon)),
        onPressed: onPressed,
      );
}

/// Moves [delta] of the total from ratio `i + 1` to ratio `i`, keeping both
/// at least 5% and the sum at exactly one.
List<double> _shift(List<double> ratios, int i, double delta) {
  final pair = ratios[i] + ratios[i + 1];
  final a = (ratios[i] + delta).clamp(0.05, pair - 0.05);
  final out = [...ratios]
    ..[i] = a
    ..[i + 1] = pair - a;
  // Absorb float drift into the last ratio so ResizeWindow accepts the sum.
  out[out.length - 1] += 1 - out.fold(0.0, (s, r) => s + r);
  return out;
}

/// A drag handle between two children. Reports the ratios at drag start and
/// the offset since then, so updates landing in the same frame never stack on
/// stale ratios.
class _Divider extends StatefulWidget {
  const _Divider(
      {super.key,
      required this.axis,
      required this.ratios,
      required this.onDrag});

  final Axis axis;
  final List<double> ratios;
  final void Function(List<double> start, double offset)? onDrag;

  @override
  State<_Divider> createState() => _DividerState();
}

class _DividerState extends State<_Divider> {
  List<double> _start = const [];
  double _offset = 0;

  void _begin(DragStartDetails _) {
    _start = widget.ratios;
    _offset = 0;
  }

  void _update(double delta) => widget.onDrag!(_start, _offset += delta);

  @override
  Widget build(BuildContext context) {
    final horizontal = widget.axis == Axis.horizontal;
    final drag = widget.onDrag != null;
    return MouseRegion(
      cursor: !drag
          ? MouseCursor.defer
          : horizontal
              ? SystemMouseCursors.resizeColumn
              : SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: horizontal && drag ? _begin : null,
        onHorizontalDragUpdate:
            horizontal && drag ? (d) => _update(d.delta.dx) : null,
        onVerticalDragStart: !horizontal && drag ? _begin : null,
        onVerticalDragUpdate:
            !horizontal && drag ? (d) => _update(d.delta.dy) : null,
        child: SizedBox(
          width: horizontal ? 8 : null,
          height: horizontal ? null : 8,
          child: Center(
            child: Container(
              width: horizontal ? 2 : 40,
              height: horizontal ? 40 : 2,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
      ),
    );
  }
}
