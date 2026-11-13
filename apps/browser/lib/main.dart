// The browser integration app (docs/integration-apps.md): real web pages in
// reef windows. reef owns every navigation; the webview only renders the
// current history entry. This is the tracer: one shell, an address bar, the
// link tree.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
  static const page = Color(0xFFFFFFFF);
  static const textPrimary = Color(0xFF1F1B16);
  static const textMuted = Color(0xFF7A7064);
  static const toolbarHeight = 56.0;
  static const addressBarHeight = 44.0;
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

/// The address bar text for [route].
String addressOf(Object route) => switch (route) {
  WebPage() => route.uri.toString(),
  NewTabRoute() => '',
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
  late final controller = WindowingController(
    initial: () =>
        WindowingDoc.initial(buffer: links.linkOf(const NewTabRoute()).buffer),
    store: widget.store,
  );
  late final nav = LinkNavigator(links, controller);

  /// Each web page window's webview, for tests to read the page through.
  final webViews = <WindowId, InAppWebViewController>{};

  /// The route the focused window shows; null without one.
  Object? get focusedRoute {
    final doc = controller.doc.value;
    final entry = doc.windows[doc.activeWindowId]?.history.current;
    return entry == null
        ? null
        : links.routeOfBuffer(entry.buffer, entry.arguments);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Toolbar(),
            Expanded(
              child: WindowingRoot(
                controller: controller,
                bufferBuilder: (_, buffer) => BrowserPage(buffer),
                delegate: WindowingDelegate(
                  windowChrome: (_, _, _, page) => page,
                  projectionPolicy: (_, _, _) =>
                      (_, _, shellId) =>
                          DesktopProjection(shellId, showTabStrip: false),
                ),
              ),
            ),
          ],
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

  // ponytail: read once; an entry replaced with new arguments on the same
  // buffer (replaceState) will need to listen to the doc.
  late final Object route = () {
    final entry = app.controller.doc.value.windows[window]!.history.current;
    return links.routeOfBuffer(
      widget.buffer,
      entry.buffer == widget.buffer ? entry.arguments : const {},
    );
  }();

  @override
  void dispose() {
    app.webViews.remove(window);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: T.page,
    child: switch (route) {
      final WebPage page => InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri.uri(page.uri)),
        onWebViewCreated: (c) => app.webViews[window] = c,
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
