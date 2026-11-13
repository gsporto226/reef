// The browser integration app (docs/integration-apps.md): real web pages in
// reef windows. reef owns every navigation; the webview only renders the
// current history entry. This is the tracer: one shell, an address bar, the
// link tree, and tabs.
import 'dart:collection';

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

final links = LinkTree<Object>([
  WebPage.link,
  NewTabRoute.link,
  NotFoundRoute.link,
]);

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
  const a = e.target.closest && e.target.closest('a[target="_blank"][href]');
  if (!a) return;
  e.preventDefault();
  reefOpen(a.href);
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
  late final controller = WindowingController(
    undo: undo,
    initial: () =>
        WindowingDoc.initial(buffer: links.linkOf(const NewTabRoute()).buffer),
    store: widget.store,
  );
  late final nav = LinkNavigator(links, controller);

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
    controller.dispose();
    super.dispose();
  }

  /// Opens a fresh new tab page in a new tab.
  void newTab() => nav.openInNewTab(const NewTabRoute());

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
                windowChrome: (_, _, _, page) => page,
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

/// Shell [shellId]'s tabs: a tap activates, × closes, + opens a new tab.
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
    _follow();
  }

  void _follow() => text.text = switch (app.focusedRoute) {
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

  // ponytail: verbs act on the focused window. Only the active tab's pages
  // are mounted and a tab has one window, so that is this one. Splits need
  // LinkNavigator verbs that take a window (reef API gap); a raw
  // PushBuffer would skip the link policy.
  void _go(LinkVerb verb, Uri url) => verb == LinkVerb.replace
      ? app.nav.replace(WebPage.of(url))
      : app.nav.push(WebPage.of(url));

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
          for (final source in [historyScript, newTabScript])
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
      _ => const _Notice('New tab', null),
    },
  );
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
