// A shell's chrome: the tab strip, the toolbar with its address bar, and a
// floating window's frame.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reef/reef.dart';
import 'package:reef_router/reef_router.dart';

import 'main.dart';
import 'src/tokens.g.dart';

/// Shell [shellId]'s surface in its view: the app, its shortcuts, the shell.
class BrowserShell extends StatelessWidget {
  const BrowserShell(this.shellId, {super.key});

  final ShellId shellId;

  @override
  Widget build(BuildContext context) {
    final app = BrowserApp.of(context);
    return LayoutBuilder(
      builder: (_, box) {
        app.shellWidths[shellId] = box.maxWidth;
        return _app(app);
      },
    );
  }

  Widget _app(BrowserAppState app) {
    return MaterialApp(
      title: 'Browser',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: T.accentDefault),
      home: Material(
        color: T.surfaceChrome,
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyT, control: true):
                app.newTab,
            const SingleActivator(
              LogicalKeyboardKey.keyT,
              control: true,
              shift: true,
            ): app.undo.undo,
          },
          child: Column(
            children: [
              _ClosePrompt(shellId),
              const _VetoNotice(),
              Expanded(
                child: FocusScope(
                  autofocus: true,
                  child: ShellProjection(shellId),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks before shell [shellId] closes with its tabs, after the interceptor
/// vetoed that close.
class _ClosePrompt extends StatelessWidget {
  const _ClosePrompt(this.shellId);

  final ShellId shellId;

  @override
  Widget build(BuildContext context) {
    final app = BrowserApp.of(context);
    return ValueListenableBuilder(
      valueListenable: app.closePrompt,
      builder: (_, shell, _) => shell != shellId
          ? const SizedBox.shrink()
          : MaterialBanner(
              content: Text(
                'Close ${app.controller.doc.value.shells[shellId]!.tabIds.length} tabs?',
              ),
              actions: [
                TextButton(
                  onPressed: () => app.answerClose(confirmed: false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => app.answerClose(confirmed: true),
                  child: const Text('Close'),
                ),
              ],
            ),
    );
  }
}

/// Shows why the interceptor vetoed a command, until dismissed.
class _VetoNotice extends StatelessWidget {
  const _VetoNotice();

  @override
  Widget build(BuildContext context) {
    final notice = BrowserApp.of(context).vetoNotice;
    return ValueListenableBuilder(
      valueListenable: notice,
      builder: (_, reason, _) => reason == null
          ? const SizedBox.shrink()
          : MaterialBanner(
              content: Text(reason),
              actions: [
                TextButton(
                  onPressed: () => notice.value = null,
                  child: const Text('OK'),
                ),
              ],
            ),
    );
  }
}

/// Shell [shellId]'s tabs: a tap activates, the close button closes, + opens
/// a new tab. A tab is a reef dock drag: dropped on a strip, this shell's or
/// another's, it moves there; dropped outside its window, it pops out.
class TabStrip extends StatelessWidget {
  const TabStrip(this.shellId, {super.key});

  final ShellId shellId;

  @override
  Widget build(BuildContext context) {
    final app = BrowserApp.of(context);
    final labels = WindowingDelegateScope.of(context).labels;
    return SizedBox(
      height: T.tabbarHeight,
      child: TabStripSlot(
        shellId,
        // A drop past the last tab appends; on a tab, beside it.
        builder: (context, strip) => DockArea(
          target: (_, _) => TabStripTarget(shellId, strip.tabIds.length),
          // Titles follow navigation, not only the strip's tab list.
          child: ListenableBuilder(
            listenable: Listenable.merge([app.controller.doc, app.pinnedTabs]),
            builder: (_, _) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: T.space8),
              child: Row(
                children: [
                  for (final (i, id) in strip.tabIds.indexed) ...[
                    _Tab(
                      id: id,
                      target: DockArea.tab(shellId, i),
                      title: labels.tab(id)!.localize(),
                      pinned: app.pinnedTabs.value.contains(id),
                      active: id == strip.activeTabId,
                      onTap: () => strip.activate(id),
                      onClose: () => strip.close(id),
                    ),
                    const SizedBox(width: T.space4),
                  ],
                  IconButton(
                    tooltip: 'New tab',
                    icon: const Icon(Icons.add),
                    onPressed: app.newTab,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.id,
    required this.target,
    required this.title,
    required this.pinned,
    required this.active,
    required this.onTap,
    required this.onClose,
  });

  final TabId id;
  final DockTargetPicker target;
  final String title;
  final bool pinned;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Flexible(
    child: DockArea(
      target: target,
      child: DockSource(dockable: TabDockable(id), child: _body()),
    ),
  );

  Widget _body() => Material(
    color: active ? T.surfaceTabActive : Colors.transparent,
    borderRadius: BorderRadius.circular(T.radiusSm),
    child: InkWell(
      borderRadius: BorderRadius.circular(T.radiusSm),
      onTap: onTap,
      child: SizedBox(
        width: T.tabWidth,
        height: T.tabbarHeight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(T.space12, 0, T.space4, 0),
          child: Row(
            children: [
              Icon(
                pinned ? Icons.push_pin : Icons.public,
                size: 18,
                color: T.textMuted,
              ),
              const SizedBox(width: T.space8),
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, color: T.textPrimary),
                ),
              ),
              IconButton(
                tooltip: 'Close tab',
                iconSize: 18,
                icon: const Icon(Icons.close),
                onPressed: onClose,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The toolbar of shell [shellId]. Its address bar is the shell's route
/// information: a per-shell [WindowingLinkSync] reports the shell's active
/// window into it, and a submitted address is a route notification that
/// opens in this shell (ADR 0011).
class Toolbar extends StatefulWidget {
  const Toolbar(this.shellId, {super.key});

  final ShellId shellId;

  @override
  State<Toolbar> createState() => _ToolbarState();
}

class _ToolbarState extends State<Toolbar> {
  final text = TextEditingController();
  final bar = AddressBarProvider();
  late final app = BrowserApp.of(context);

  @override
  void initState() {
    super.initState();
    bar.shown.addListener(_address);
  }

  void _address() => text.text = addressOf(links.routeOf(bar.value.uri));

  @override
  void dispose() {
    bar.dispose();
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WindowingLinkSync(
    tree: links,
    shell: widget.shellId,
    routeInformationProvider: bar,
    child: _bar(),
  );

  Widget _bar() => Container(
    height: T.toolbarHeight,
    padding: const EdgeInsets.symmetric(horizontal: T.space12),
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      color: T.surfaceChrome,
      border: Border(bottom: BorderSide(color: T.borderHairline)),
    ),
    child: Container(
      height: T.addressbarHeight,
      padding: const EdgeInsets.symmetric(horizontal: T.space16),
      decoration: ShapeDecoration(
        color: T.surfaceField,
        shape: const StadiumBorder(side: BorderSide(color: T.borderHairline)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back),
            onPressed: app.controller.back,
          ),
          IconButton(
            tooltip: 'Forward',
            icon: const Icon(Icons.arrow_forward),
            onPressed: app.nav.forward,
          ),
          const Icon(Icons.lock_outline, size: 20, color: T.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Semantics(
              label: 'Address bar',
              child: TextField(
                controller: text,
                textInputAction: TextInputAction.go,
                style: const TextStyle(fontSize: 15, color: T.textPrimary),
                decoration: const InputDecoration.collapsed(
                  hintText: 'Search or type a URL',
                ),
                onSubmitted: (t) {
                  if (t.trim().isNotEmpty) {
                    bar.browse(links.uriOf(routeOfInput(t)));
                  }
                },
              ),
            ),
          ),
          ListenableBuilder(
            listenable: Listenable.merge([bar.shown, app.bookmarks]),
            // The star reads this shell's page, not the focused shell's.
            builder: (_, _) {
              final route = links.routeOf(bar.value.uri);
              return IconButton(
                tooltip: 'Bookmark',
                icon: Icon(
                  app.bookmarks.value.contains(route)
                      ? Icons.star
                      : Icons.star_border,
                ),
                onPressed: () => app.toggleBookmark(route),
              );
            },
          ),
          PopupMenuButton<VoidCallback>(
            tooltip: 'Menu',
            icon: const Icon(Icons.more_vert),
            onSelected: (action) => action(),
            itemBuilder: (_) => [
              for (final (label, route) in const [
                ('History', HistoryRoute()),
                ('Bookmarks', BookmarksRoute()),
                ('Settings', SettingsRoute()),
              ])
                PopupMenuItem(
                  value: () => app.nav.go(route),
                  child: Text(label),
                ),
              PopupMenuItem(
                value: () => app.openInSplit(),
                child: const Text('Open in split'),
              ),
              if (app.controller.capabilities.canPopOut)
                PopupMenuItem(
                  value: () => app.openInNewWindow(),
                  child: const Text('Open in new window'),
                ),
              PopupMenuItem(
                value: app.mirrorSplit,
                child: const Text('Mirror split'),
              ),
              ..._paneMoves(app),
              for (final (label, open) in [
                ('Picture in picture', app.pictureInPicture),
                ('Find in page', app.findInPage),
                ('Downloads', app.downloads),
              ])
                PopupMenuItem(value: () => open(), child: Text(label)),
              CheckedPopupMenuItem(
                checked: app.pinnedTabs.value.contains(app.focusedTab),
                value: app.togglePin,
                child: const Text('Pin tab'),
              ),
              CheckedPopupMenuItem(
                checked: app.settingsLocked.value,
                value: () =>
                    app.settingsLocked.value = !app.settingsLocked.value,
                child: const Text('Lock settings'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// "Move to new tab" and "Move to window N" (each other shell) for the
/// focused pane, when its tab is split.
List<PopupMenuEntry<VoidCallback>> _paneMoves(BrowserAppState app) {
  final doc = app.controller.doc.value;
  final window = doc.activeWindowId;
  final tab = window == null ? null : doc.tabs[doc.tabOf(window)];
  if ((tab?.root?.windowIds.length ?? 0) < 2) return const [];
  final shells = doc.shells.keys.toList();
  return [
    PopupMenuItem(
      value: app.moveToNewTab,
      child: const Text('Move to new tab'),
    ),
    for (final (i, shell) in shells.indexed)
      if (shell != doc.focusedShellId)
        PopupMenuItem(
          value: () => app.moveToShell(shell),
          child: Text('Move to window ${i + 1}'),
        ),
  ];
}

/// A shell's address bar as route information. Reports land in [shown];
/// only [browse] (a submitted address) notifies the sync.
class AddressBarProvider extends RouteInformationProvider with ChangeNotifier {
  /// The reported route information.
  final shown = ValueNotifier(RouteInformation(uri: Uri.parse('/')));

  @override
  RouteInformation get value => shown.value;

  /// A typed address: opens [uri] in the bar's shell.
  void browse(Uri uri) {
    shown.value = RouteInformation(uri: uri);
    notifyListeners();
  }

  @override
  void routerReportsNewRouteInformation(
    RouteInformation routeInformation, {
    RouteInformationReportingType type = RouteInformationReportingType.none,
  }) => shown.value = routeInformation;

  @override
  void dispose() {
    shown.dispose();
    super.dispose();
  }
}

/// A tree pane's frame: a [PaneBar] over [page].
class Pane extends StatelessWidget {
  const Pane(this.windowId, this.page, {super.key});

  final WindowId windowId;
  final Widget page;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      PaneBar(windowId, children: const [Spacer()]),
      Expanded(child: page),
    ],
  );
}

/// A floating window's frame: a [PaneBar] with its title and dock buttons
/// over [page].
class FloatPanel extends StatelessWidget {
  const FloatPanel(this.windowId, this.page, {super.key});

  final WindowId windowId;
  final Widget page;

  @override
  Widget build(BuildContext context) {
    final app = BrowserApp.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: T.surfacePage,
        border: Border.all(color: T.borderHairline),
        borderRadius: BorderRadius.circular(T.radiusSm),
        boxShadow: const [BoxShadow(blurRadius: 12, color: Color(0x33000000))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PaneBar(
            windowId,
            children: [
              Expanded(
                child: Text(
                  WindowingDelegateScope.of(context).labels
                      .window(windowId)!
                      .localize(),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: T.textPrimary),
                ),
              ),
              // The keyboard's way to dock; the grip drags anywhere.
              _barAction(
                'Dock left',
                Icons.align_horizontal_left,
                () => app.dock(windowId, DockSide.before),
              ),
              _barAction(
                'Dock right',
                Icons.align_horizontal_right,
                () => app.dock(windowId, DockSide.after),
              ),
            ],
          ),
          Expanded(child: page),
        ],
      ),
    );
  }
}

/// A pane's header: a grip that drags the pane as a reef dock drag (onto a
/// pane's edge or centre, a tab strip, or out of its window), [children],
/// and close.
class PaneBar extends StatelessWidget {
  const PaneBar(this.windowId, {super.key, this.children = const []});

  final WindowId windowId;
  final List<Widget> children;

  static const height = 28.0;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    color: T.surfaceChrome,
    child: Row(
      children: [
        DockSource(
          dockable: WindowDockable(windowId),
          child: const Tooltip(
            message: 'Drag pane',
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: SizedBox.square(
                dimension: height,
                child: Icon(Icons.drag_indicator, size: 16, color: T.textMuted),
              ),
            ),
          ),
        ),
        ...children,
        _barAction(
          'Close',
          Icons.close,
          () => BrowserApp.of(context).controller.closeWindow(windowId),
        ),
      ],
    ),
  );
}

Widget _barAction(String tooltip, IconData icon, VoidCallback onPressed) =>
    IconButton(
      tooltip: tooltip,
      iconSize: 16,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(
        width: PaneBar.height,
        height: PaneBar.height,
      ),
      icon: Icon(icon),
      onPressed: onPressed,
    );
