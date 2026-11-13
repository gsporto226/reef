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
          child: FocusScope(autofocus: true, child: ShellProjection(shellId)),
        ),
      ),
    );
  }
}

/// Shell [shellId]'s tabs: a tap activates, the close button closes, + opens a new tab.
class TabStrip extends StatelessWidget {
  const TabStrip(this.shellId, {super.key});

  final ShellId shellId;

  @override
  Widget build(BuildContext context) {
    final app = BrowserApp.of(context);
    // A tab dropped here from another shell moves in; one dropped on no
    // strip pops out into a new shell.
    return DragTarget<(TabId,)>(
      onAcceptWithDetails: (d) => app.moveTabTo(d.data.$1, shellId),
      builder: (_, _, _) => _strip(app),
    );
  }

  Widget _strip(BrowserAppState app) {
    return SizedBox(
      height: T.tabbarHeight,
      child: TabStripSlot(
        shellId,
        // Titles follow navigation, not only the strip's tab list.
        builder: (context, strip) => ListenableBuilder(
          listenable: app.controller.doc,
          builder: (_, _) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: T.space8),
            child: Row(
              children: [
                for (final id in strip.tabIds) ...[
                  _Tab(
                    id: id,
                    title: titleOf(
                      app.routeOf(
                            app.controller.doc.value.tabs[id]?.activeWindowId,
                          ) ??
                          const NewTabRoute(),
                    ),
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
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.id,
    required this.title,
    required this.active,
    required this.onTap,
    required this.onClose,
  });

  final TabId id;
  final String title;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Flexible(
    child: Draggable<(TabId,)>(
      data: (id,),
      feedback: Material(
        color: T.surfaceTabActive,
        elevation: 4,
        borderRadius: BorderRadius.circular(T.radiusSm),
        child: Padding(
          padding: const EdgeInsets.all(T.space12),
          child: Text(title),
        ),
      ),
      onDraggableCanceled: (_, _) =>
          BrowserApp.of(context).controller.popOutTab(id),
      child: _body(),
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
              const Icon(Icons.public, size: 18, color: T.textMuted),
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
            onPressed: app.nav.back,
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
              PopupMenuItem(
                value: app.mirrorSplit,
                child: const Text('Mirror split'),
              ),
              for (final (label, open) in [
                ('Picture in picture', app.pictureInPicture),
                ('Find in page', app.findInPage),
                ('Downloads', app.downloads),
              ])
                PopupMenuItem(value: () => open(), child: Text(label)),
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

/// A floating window's frame: a title bar with dock and close over [page].
class FloatPanel extends StatelessWidget {
  const FloatPanel(this.windowId, this.page, {super.key});

  final WindowId windowId;
  final Widget page;

  static const barHeight = 28.0;

  @override
  Widget build(BuildContext context) {
    final app = BrowserApp.of(context);
    Widget action(String tooltip, IconData icon, VoidCallback onPressed) =>
        IconButton(
          tooltip: tooltip,
          iconSize: 16,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(
            width: barHeight,
            height: barHeight,
          ),
          icon: Icon(icon),
          onPressed: onPressed,
        );
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
          Container(
            height: barHeight,
            color: T.surfaceChrome,
            padding: const EdgeInsets.only(left: T.space8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    titleOf(app.routeOf(windowId) ?? const NewTabRoute()),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: T.textPrimary),
                  ),
                ),
                action(
                  'Dock left',
                  Icons.align_horizontal_left,
                  () => app.dock(windowId, DockSide.before),
                ),
                action(
                  'Dock right',
                  Icons.align_horizontal_right,
                  () => app.dock(windowId, DockSide.after),
                ),
                action(
                  'Close',
                  Icons.close,
                  () => app.controller.closeWindow(windowId),
                ),
              ],
            ),
          ),
          Expanded(child: page),
        ],
      ),
    );
  }
}
