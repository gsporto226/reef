// The browser's routes, its link tree and the pure functions over them.
import 'package:flutter/foundation.dart';
import 'package:reef/reef.dart';
import 'package:reef_router/reef_router.dart';

/// A site's host with its port: `127.0.0.1:8080`.
extension type const Host(String value) {}

/// A web page: `/web/{scheme}/{host}/**`. The site's whole query string is
/// one opaque argument; its keys never enter reef's query bag. One origin
/// is one page (ADR 0008): its webview survives a path-changing pushState.
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
      .build(WebPage.new)
      .identity((r) => (r.scheme, r.host));

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

/// Bookmarks saved as link URIs: a restorable value in the `browser`
/// bucket (ADR 0010), so they outlive their history entries.
final bookmarksCodec = RestorableCodec<List<Object>>(
  encode: (routes) => [for (final r in routes) links.uriOf(r).toString()],
  decode: (json) => [
    for (final s in json! as List) links.routeOf(Uri.parse(s as String)),
  ],
);

/// Every history entry in [doc], back, current and forward, as routes.
Iterable<Object> _entries(WindowingDoc doc) => [
  for (final w in doc.windows.values)
    for (final e in [
      ...w.history.back,
      w.history.current,
      ...w.history.forward,
    ])
      links.routeOfBuffer(e.buffer, e.arguments),
];

/// Every web page in [doc]'s histories, once each.
List<WebPage> historyOf(WindowingDoc doc) => {
  for (final r in _entries(doc))
    if (r is WebPage) r,
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

/// -1 when [after] is [before] gone back one entry, 1 when gone forward one,
/// else null (a push, a replace or anything else).
int? historyStep(BufferHistory before, BufferHistory after) {
  if (after.current.id == before.back.lastOrNull?.id &&
      after.forward.lastOrNull?.id == before.current.id) {
    return -1;
  }
  if (after.current.id == before.forward.lastOrNull?.id &&
      after.back.lastOrNull?.id == before.current.id) {
    return 1;
  }
  return null;
}

/// The entry argument that says how a window draws its page: `shared` draws
/// another window's webview (a mirror split), anything else its own.
const viewKey = 'view';

/// The window whose webview mirror [window] draws: another window on the
/// same page (ADR 0008 identity) with its own view. Null when [window] is
/// not a mirror, or its original is gone: it then draws its own view.
WindowId? mirrorSourceOf(WindowingDoc doc, WindowId window) {
  final entry = doc.windows[window]?.history.current;
  if (entry == null || entry.arguments[viewKey] != 'shared') return null;
  final page = links.pageIdentityOf(entry.buffer);
  for (final MapEntry(:key, :value) in doc.windows.entries) {
    final other = value.history.current;
    if (key != window &&
        other.arguments[viewKey] != 'shared' &&
        links.pageIdentityOf(other.buffer) == page) {
      return key;
    }
  }
  return null;
}

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
