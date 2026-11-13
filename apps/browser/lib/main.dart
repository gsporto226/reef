// The browser integration app (docs/integration-apps.md): real web pages in
// reef windows. reef owns every navigation; the webview only renders the
// current history entry. This is the tracer: one shell, an address bar, the
// link tree, and tabs.
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:reef/reef.dart';
import 'package:reef_router/reef_router.dart';

void main() => runApp(BrowserApp(store: InMemoryHibernationStore()));

/// Design tokens, from design/tokens.json.
abstract final class T {
  static const accent = Color(0xFF0F6E66);
  static const border = Color(0xFFE8E1D6);
  static const chrome = Color(0xFFF3EEE6);
  static const field = Color(0xFFFFFFFF);
  static const tabActive = Color(0xFFFFFDF9);
  static const page = Color(0xFFFFFFFF);
  static const textPrimary = Color(0xFF1F1B16);
  static const textMuted = Color(0xFF7A7064);
  static const toolbarHeight = 56.0;
  static const addressBarHeight = 44.0;
  static const tabbarHeight = 44.0;
  static const tabWidth = 220.0;
  static const radiusSm = 8.0;
  static const space4 = 4.0;
  static const space8 = 8.0;
  static const space12 = 12.0;
  static const space16 = 16.0;
  static const space40 = 40.0;
}

/// A site's host with its port: `127.0.0.1:8080`.
extension type const Host(String value) {}

/// A web page: `/web/{scheme}/{host}/**`. The site's whole query string is
/// one opaque argument; its keys never enter reef's query bag.
final class WebPage {
  const WebPage(this.scheme, this.host, this.path, this.query);

  /// [uri] as a page.
  WebPage.of(Uri uri)
    : this(uri.scheme, Host(uri.authority), [
        ...uri.pathSegments.where((s) => s.isNotEmpty),
      ], uri.query);

  final String scheme;
  final Host host;
  final List<String> path;
  final String query;

  // ponytail: drops a trailing slash; keep it in the route if a site cares.
  Uri get uri =>
      Uri.parse('$scheme://${host.value}')
          .replace(pathSegments: path, query: query.isEmpty ? null : query);

  static final link = Link<WebPage>('web')
      .field((r) => r.scheme)
      .field((r) => r.host, codec: LinkCodec.of((h) => h.value, Host.new))
      .rest((r) => r.path)
      .query('q', (r) => r.query, fallback: '')
      .build(WebPage.new);

  @override
  bool operator ==(Object other) =>
      other is WebPage &&
      other.scheme == scheme &&
      other.host == host &&
      listEquals(other.path, path) &&
      other.query == query;

  @override
  int get hashCode => Object.hash(scheme, host, Object.hashAll(path), query);

  @override
  String toString() => 'WebPage($uri)';
}

/// The new tab page: `/`. Fresh, so two new tabs are two pages (D3).
final class NewTabRoute {
  const NewTabRoute();

  static final link = Link<NewTabRoute>('').build(NewTabRoute.new).fresh();
}

/// Any other internal path.
final class NotFoundRoute {
  const NotFoundRoute(this.path);
  final List<String> path;

  static final link = Link<NotFoundRoute>('')
      .rest((r) => r.path)
      .build(NotFoundRoute.new);

  @override
  bool operator ==(Object other) =>
      other is NotFoundRoute && listEquals(other.path, path);

  @override
  int get hashCode => Object.hashAll(path);

  @override
  String toString() => 'NotFoundRoute($path)';
}

/// `/history`: every web page in the doc's histories.
final class HistoryRoute {
  const HistoryRoute();

  static final link = Link<HistoryRoute>('history')
      .build(() => const HistoryRoute());
}

/// `/bookmarks`: the web pages whose entry is bookmarked.
final class BookmarksRoute {
  const BookmarksRoute();

  static final link = Link<BookmarksRoute>('bookmarks')
      .build(() => const BookmarksRoute());
}

/// `/settings`, guarded: while the lock is set it redirects to a new tab,
/// replacing the entry (D7), and re-checks when the lock changes (D8).
final class SettingsRoute {
  const SettingsRoute();

  static final link = Link<SettingsRoute>('settings')
      .build(() => const SettingsRoute())
      .guard<Object, ValueListenable<bool>>(
        (_, _, locked) => locked.value
            ? const GuardDecision.redirect(NewTabRoute())
            : const GuardDecision.allow(),
        name: 'settings lock',
      );
}

/// `/find`: the find panel, floating over the window it searches.
final class FindRoute {
  const FindRoute();

  static final link = Link<FindRoute>('find').build(() => const FindRoute());
}

/// `/downloads`: the downloads popup, floating over its tab. The entries are
/// fake (real downloads are out of scope).
final class DownloadsRoute {
  const DownloadsRoute();

  static final link = Link<DownloadsRoute>('downloads')
      .build(() => const DownloadsRoute());
}

const fakeDownloads = ['report.pdf', 'photos.zip', 'setup.exe'];

final links = LinkTree<Object>([
  WebPage.link,
  NewTabRoute.link,
  HistoryRoute.link,
  BookmarksRoute.link,
  SettingsRoute.link,
  FindRoute.link,
  DownloadsRoute.link,
  NotFoundRoute.link,
]);

/// The entry argument that bookmarks an entry. The doc is the only store,
/// so a bookmark is a mark on a history entry.
// ponytail: a bookmark lives and dies with its entry (closing the tab drops
// it); a doc-level app-data slot in reef would fix that.
const bookmarkKey = 'bookmark';

/// Every history entry in [doc], back, current and forward, as routes.
Iterable<(Object, HistoryEntry)> _entries(WindowingDoc doc) => [
  for (final w in doc.windows.values)
    for (final e in [
      ...w.history.back,
      w.history.current,
      ...w.history.forward,
    ])
      (links.routeOfBuffer(e.buffer, e.arguments), e),
];

/// Every web page in [doc]'s histories, once each.
List<WebPage> historyOf(WindowingDoc doc) => {
  for (final (r, _) in _entries(doc))
    if (r is WebPage) r,
}.toList();

/// The web pages with a bookmarked entry in [doc], once each.
List<WebPage> bookmarksOf(WindowingDoc doc) => {
  for (final (r, e) in _entries(doc))
    if (r is WebPage && e.arguments.containsKey(bookmarkKey)) r,
}.toList();

/// What typing [text] into the address bar opens: a path is an internal
/// page, anything else a web URL (https when it names no scheme).
Object routeOfInput(String text) {
  final t = text.trim();
  if (t.startsWith('/')) return links.routeOf(Uri.parse(t));
  return WebPage.of(Uri.parse(t.contains('://') ? t : 'https://$t'));
}

/// How reef takes a main-frame navigation the webview is about to make to
/// [url] while its window shows [current]: null lets it load (it is the
/// entry itself); otherwise the load is cancelled and the verb goes through
/// reef. A server redirect replaces; anything else pushes.
LinkVerb? verbOfNavigation(Object? current, Uri url, {required bool redirect}) {
  if (WebPage.of(url) == current) return null;
  return redirect ? LinkVerb.replace : LinkVerb.push;
}

/// Reports the page's pushState/replaceState to reef, after they ran.
const historyScript = '''
for (const kind of ['pushState', 'replaceState']) {
  const original = history[kind].bind(history);
  history[kind] = (...args) => {
    original(...args);
    window.flutter_inappwebview.callHandler('reefHistory', kind, location.href);
  };
}
''';

/// Sends `target=_blank` links and `window.open` to reef as new tabs. The
/// plugin's onCreateWindow hangs the page when the app opens the tab itself
/// (its WebView2 deferral is never completed), so the page asks instead.
// ponytail: _blank only; named targets still load in place.
const newTabScript = '''
const reefOpen = (url) =>
  window.flutter_inappwebview.callHandler('reefOpen', new URL(url, location.href).href);
window.open = (url) => { if (url) reefOpen(String(url)); return null; };
document.addEventListener('click', (e) => {
  const a = e.target.closest && e.target.closest('a[href]');
  if (!a) return;
  if (e.ctrlKey) {
    e.preventDefault();
    window.flutter_inappwebview.callHandler('reefSplit', a.href);
  } else if (a.target == '_blank') {
    e.preventDefault();
    reefOpen(a.href);
  }
}, true);
''';

/// Sends the app's shortcuts to reef while the page has keyboard focus:
/// WebView2 then holds native focus and Flutter sees no key events.
const shortcutScript = '''
document.addEventListener('keydown', (e) => {
  if (!e.ctrlKey || e.altKey || e.key.toLowerCase() != 't') return;
  e.preventDefault();
  window.flutter_inappwebview.callHandler('reefShortcut', e.shiftKey ? 'reopen' : 'newTab');
}, true);
''';

/// The address bar text for [route].
String addressOf(Object route) => switch (route) {
  WebPage() => route.uri.toString(),
  NewTabRoute() => '',
  _ => links.uriOf(route).toString(),
};

/// A tab's title for [route].
String titleOf(Object route) => switch (route) {
  WebPage(:final host, :final path) => [host.value, ...path].join('/'),
  NewTabRoute() => 'New tab',
  FindRoute() => 'Find in page',
  DownloadsRoute() => 'Downloads',
  _ => links.uriOf(route).toString(),
};

class BrowserApp extends StatefulWidget {
  const BrowserApp({super.key, required this.store});

  final HibernationStore store;

  static BrowserAppState of(BuildContext context) =>
      context.findAncestorStateOfType<BrowserAppState>()!;

  @override
  State<BrowserApp> createState() => BrowserAppState();
}

class BrowserAppState extends State<BrowserApp> {
  /// The global undo timeline: Ctrl+Shift+T reopens a closed tab on it.
  final undo = UndoController();

  /// The settings lock: the guard's environment (D8).
  final settingsLocked = ValueNotifier(false);
  late final _bound = links.bind(settingsLocked);
  late final controller = WindowingController(
    undo: undo,
    initial: () =>
        WindowingDoc.initial(buffer: links.linkOf(const NewTabRoute()).buffer),
    store: widget.store,
    interceptor: _bound.interceptor,
  );
  late final nav = LinkNavigator(links, controller);
  late final void Function() _unwatch;

  @override
  void initState() {
    super.initState();
    _unwatch = _bound.watch(controller, refresh: settingsLocked);
  }

  /// Bookmarks the focused window's entry, or clears its bookmark.
  void toggleBookmark() {
    final doc = controller.doc.value;
    final id = doc.activeWindowId;
    final entry = doc.windows[id]?.history.current;
    if (id == null || entry == null) return;
    final arguments = {...entry.arguments};
    if (arguments.remove(bookmarkKey) == null) arguments[bookmarkKey] = '';
    controller.dispatch(ReplaceBuffer(id, entry.buffer, arguments: arguments));
  }

  /// Whether the focused window's entry is bookmarked.
  bool get bookmarked =>
      controller
          .doc
          .value
          .windows[controller.doc.value.activeWindowId]
          ?.history
          .current
          .arguments
          .containsKey(bookmarkKey) ??
      false;

  /// Each web page window's webview, for tests to read the page through.
  final webViews = <WindowId, InAppWebViewController>{};

  /// The route the focused window shows; null without one.
  Object? get focusedRoute => routeOf(controller.doc.value.activeWindowId);

  /// Route [window]'s current entry; null once the window is gone.
  Object? routeOf(WindowId? window) {
    final entry = controller.doc.value.windows[window]?.history.current;
    return entry == null
        ? null
        : links.routeOfBuffer(entry.buffer, entry.arguments);
  }

  @override
  void dispose() {
    _unwatch();
    controller.dispose();
    settingsLocked.dispose();
    super.dispose();
  }

  /// Opens [route] (a copy of the focused page when null) in a new window
  /// floating over the scope [scopeOf] picks, on top of its floats.
  WindowId? _float(
    FloatScope Function(WindowingDoc doc, WindowId focused) scopeOf, [
    Object? route,
  ]) {
    final doc = controller.doc.value;
    final focused = doc.activeWindowId;
    if (focused == null) return null;
    final id = WindowId.generate();
    final link = route == null ? null : links.linkOf(route);
    controller.dispatchAll([
      SplitWindow(
        focused,
        newWindowId: id,
        axis: Axis.horizontal,
        buffer: link?.buffer,
        arguments: link?.arguments ?? const {},
      ),
      FloatWindow(id, scope: scopeOf(doc, focused)),
    ]);
    return id;
  }

  /// Picture in picture: the focused page floats over the whole shell.
  WindowId? pictureInPicture() =>
      _float((doc, _) => ShellScope(doc.focusedShellId));

  /// The find panel floats over the focused window.
  WindowId? findInPage() => _float((_, w) => WindowScope(w), const FindRoute());

  /// The downloads popup floats over the focused tab.
  WindowId? downloads() => _float(
    (doc, _) => TabScope(doc.shells[doc.focusedShellId]!.activeTabId),
    const DownloadsRoute(),
  );

  /// Docks floating [window] on [side] of the focused tab's active window.
  void dock(WindowId window, DockSide side) {
    final doc = controller.doc.value;
    controller.dockWindow(
      window,
      tabId: doc.shells[doc.focusedShellId]!.activeTabId,
      side: side,
    );
  }

  /// Opens a fresh new tab page in a new tab.
  void newTab() => nav.openInNewTab(const NewTabRoute());

  /// Opens [route], the focused page when null, in a new window beside the
  /// focused one: an independent view with its own webview.
  void openInSplit([Object? route]) {
    if (route ?? focusedRoute case final r?) nav.openInSplit(r);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Browser',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: T.accent),
    home: Material(
      color: T.chrome,
      child: LinkScope(
        navigator: nav,
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyT, control: true):
                newTab,
            const SingleActivator(
              LogicalKeyboardKey.keyT,
              control: true,
              shift: true,
            ): undo.undo,
          },
          child: FocusScope(
            autofocus: true,
            child: WindowingRoot(
              controller: controller,
              bufferBuilder: (_, buffer) => BrowserPage(buffer),
              delegate: WindowingDelegate(
                windowChrome: (_, id, _, page) =>
                    controller.doc.value.floating.containsKey(id)
                    ? FloatPanel(id, page)
                    : page,
                // The chrome: tab strip over the toolbar.
                tabStrip: (_, shellId) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [TabStrip(shellId), const Toolbar()],
                ),
                projectionPolicy: (_, _, _) =>
                    (_, _, shellId) => DesktopProjection(shellId),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Shell [shellId]'s tabs: a tap activates, Ã— closes, + opens a new tab.
class TabStrip extends StatelessWidget {
  const TabStrip(this.shellId, {super.key});

  final ShellId shellId;

  @override
  Widget build(BuildContext context) {
    final app = BrowserApp.of(context);
    return SizedBox(
      height: T.tabbarHeight,
      child: TabStripSlot(
        shellId,
        builder: (context, strip) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: T.space8),
          child: Row(
            children: [
              for (final id in strip.tabIds) ...[
                _Tab(
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
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.title,
    required this.active,
    required this.onTap,
    required this.onClose,
  });

  final String title;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Flexible(
    child: Material(
      color: active ? T.tabActive : Colors.transparent,
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
    ),
  );
}

/// The toolbar: the address bar, showing the focused window's address.
class Toolbar extends StatefulWidget {
  const Toolbar({super.key});

  @override
  State<Toolbar> createState() => _ToolbarState();
}

class _ToolbarState extends State<Toolbar> {
  final text = TextEditingController();
  late final app = BrowserApp.of(context);

  @override
  void initState() {
    super.initState();
    app.controller.doc.addListener(_follow);
    _address();
  }

  void _follow() => setState(_address);

  void _address() => text.text = switch (app.focusedRoute) {
    final r? => addressOf(r),
    null => '',
  };

  @override
  void dispose() {
    app.controller.doc.removeListener(_follow);
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    height: T.toolbarHeight,
    padding: const EdgeInsets.symmetric(horizontal: T.space12),
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      color: T.chrome,
      border: Border(bottom: BorderSide(color: T.border)),
    ),
    child: Container(
      height: T.addressBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: T.space16),
      decoration: ShapeDecoration(
        color: T.field,
        shape: const StadiumBorder(side: BorderSide(color: T.border)),
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
                  if (t.trim().isNotEmpty) app.nav.go(routeOfInput(t));
                },
              ),
            ),
          ),
          IconButton(
            tooltip: 'Bookmark',
            icon: Icon(app.bookmarked ? Icons.star : Icons.star_border),
            onPressed: app.toggleBookmark,
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

/// The page [buffer] shows in its window.
class BrowserPage extends StatefulWidget {
  const BrowserPage(this.buffer, {super.key});

  final BufferId buffer;

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> {
  late final app = BrowserApp.of(context);
  late final window = WindowHost.of(context);
  late Object route = _entryRoute();
  InAppWebViewController? web;

  // flutter_inappwebview_windows 0.6.0 never sets isRedirect (it reads
  // Fetch.requestPaused's redirectedRequestId from inside `request`, where
  // CDP doesn't put it). So a main-frame request that arrives while the
  // entry's own load is still running counts as a server redirect.
  // ponytail: a script navigating before load stop also replaces; drop this
  // once the plugin reports isRedirect.
  bool _loading = false;

  /// This window's current entry as a route, read from the doc: the builder
  /// only gets the buffer.
  Object _entryRoute() {
    final entry = app.controller.doc.value.windows[window]?.history.current;
    return links.routeOfBuffer(
      widget.buffer,
      entry?.buffer == widget.buffer ? entry!.arguments : const {},
    );
  }

  @override
  void initState() {
    super.initState();
    app.controller.doc.addListener(_follow);
  }

  /// The entry changed on this buffer (back/forward, pushState, a replace):
  /// render it, loading it unless the webview already shows it (pushState).
  Future<void> _follow() async {
    if (app.controller.doc.value.windows[window] == null) return;
    final next = _entryRoute();
    if (next == route) return;
    setState(() => route = next);
    final w = web;
    if (next is! WebPage || w == null || next == _shown) return;
    await w.loadUrl(urlRequest: URLRequest(url: WebUri.uri(next.uri)));
  }

  /// The page the webview's document is at, as pushState left it.
  WebPage? _shown;

  /// Navigates this page's own window, focused or not.
  void _go(LinkVerb verb, Uri url) => verb == LinkVerb.replace
      ? app.nav.replace(WebPage.of(url), window: window)
      : app.nav.push(WebPage.of(url), window: window);

  @override
  void dispose() {
    app.controller.doc.removeListener(_follow);
    app.webViews.remove(window);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: T.page,
    child: switch (route) {
      final WebPage page => InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri.uri(page.uri)),
        initialSettings: InAppWebViewSettings(
          useShouldOverrideUrlLoading: true,
        ),
        initialUserScripts: UnmodifiableListView([
          for (final source in [historyScript, newTabScript, shortcutScript])
            UserScript(
              source: source,
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            ),
        ]),
        onWebViewCreated: (c) {
          web = app.webViews[window] = c;
          c.addJavaScriptHandler(
            handlerName: 'reefOpen',
            callback: (args) =>
                app.nav.openInNewTab(WebPage.of(Uri.parse(args[0] as String))),
          );
          c.addJavaScriptHandler(
            handlerName: 'reefSplit',
            callback: (args) =>
                app.openInSplit(WebPage.of(Uri.parse(args[0] as String))),
          );
          c.addJavaScriptHandler(
            handlerName: 'reefShortcut',
            callback: (args) =>
                args[0] == 'reopen' ? app.undo.undo() : app.newTab(),
          );
          c.addJavaScriptHandler(
            handlerName: 'reefHistory',
            callback: (args) {
              final url = Uri.parse(args[1] as String);
              _shown = WebPage.of(url);
              _go(
                args[0] == 'replaceState' ? LinkVerb.replace : LinkVerb.push,
                url,
              );
            },
          );
        },
        shouldOverrideUrlLoading: (_, action) async {
          final url = action.request.url;
          if (action.isForMainFrame == false || url == null) {
            return NavigationActionPolicy.ALLOW;
          }
          final verb = verbOfNavigation(
            route,
            url,
            redirect: (action.isRedirect ?? false) || _loading,
          );
          if (verb == null) {
            _loading = true;
            _shown = WebPage.of(url);
            return NavigationActionPolicy.ALLOW;
          }
          _go(verb, url);
          return NavigationActionPolicy.CANCEL;
        },
        onLoadStop: (_, _) => _loading = false,
      ),
      NotFoundRoute(:final path) => _Notice(
        'Page not found',
        '/${path.join('/')}',
      ),
      FindRoute() => const _FindPanel(),
      DownloadsRoute() => ListView(
        children: [
          for (final name in fakeDownloads)
            ListTile(
              dense: true,
              leading: const Icon(Icons.insert_drive_file, color: T.textMuted),
              title: Text(name),
            ),
        ],
      ),
      HistoryRoute() => _PageList('History', historyOf),
      BookmarksRoute() => _PageList('Bookmarks', bookmarksOf),
      SettingsRoute() => const _Notice(
        'Settings',
        'Settings is guarded: while it is locked from the menu, opening it '
            'redirects to the new tab page.',
      ),
      _ => const _Notice('New tab', null),
    },
  );
}

/// An internal page listing the web pages [pagesOf] reads from the doc.
class _PageList extends StatelessWidget {
  const _PageList(this.heading, this.pagesOf);

  final String heading;
  final List<WebPage> Function(WindowingDoc) pagesOf;

  @override
  Widget build(BuildContext context) {
    final app = BrowserApp.of(context);
    return ValueListenableBuilder(
      valueListenable: app.controller.doc,
      builder: (_, doc, _) => Material(
        color: T.page,
        child: ListView(
          padding: const EdgeInsets.all(T.space40),
          children: [
            Text(
              heading,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w600,
                color: T.textPrimary,
              ),
            ),
            const SizedBox(height: T.space16),
            for (final page in pagesOf(doc))
              ListTile(
                leading: const Icon(Icons.public, color: T.textMuted),
                title: Text(titleOf(page)),
                subtitle: Text(addressOf(page)),
                onTap: () => app.nav.go(page),
              ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.heading, this.detail);

  final String heading;
  final String? detail;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(T.space40),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            heading,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: T.textPrimary,
            ),
          ),
          if (detail case final d?) ...[
            const SizedBox(height: T.space16),
            Text(d, style: const TextStyle(fontSize: 15, color: T.textMuted)),
          ],
        ],
      ),
    ),
  );
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
        color: T.page,
        border: Border.all(color: T.border),
        borderRadius: BorderRadius.circular(T.radiusSm),
        boxShadow: const [BoxShadow(blurRadius: 12, color: Color(0x33000000))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: barHeight,
            color: T.chrome,
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

/// Finds text in the page of the window the panel floats over.
class _FindPanel extends StatelessWidget {
  const _FindPanel();

  @override
  Widget build(BuildContext context) {
    final app = BrowserApp.of(context);
    final self = WindowHost.of(context);
    return Padding(
      padding: const EdgeInsets.all(T.space8),
      child: Semantics(
        label: 'Find',
        child: TextField(
          decoration: const InputDecoration(hintText: 'Find in page'),
          onSubmitted: (text) {
            if (app.controller.doc.value.floating[self]?.scope case WindowScope(
              :final id,
            )) {
              app.webViews[id]?.evaluateJavascript(
                source: 'window.find(${jsonEncode(text)})',
              );
            }
          },
        ),
      ),
    );
  }
}
