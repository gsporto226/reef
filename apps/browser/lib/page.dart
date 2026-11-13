// A window's page: the webview for a web page, the internal pages, and the
// scripts that hand the page's navigations to reef.
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:reef/reef.dart';

import 'main.dart';
import 'src/tokens.g.dart';

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

/// Sends links with a target other than this frame (`_blank` or a name)
/// and `window.open` to reef as new tabs. The plugin's onCreateWindow hangs
/// the page when the app opens the tab itself (its WebView2 deferral is
/// never completed), so the page asks instead.
// ponytail: a named target opens a new tab each time; reuse the tab of the
// same name if a site relies on it.
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
  } else if (a.target && !['_self', '_top', '_parent'].includes(a.target)) {
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

/// The page [buffer] shows in its window. It stays mounted across the
/// entries of one origin (ADR 0008), so it reads its entry from the window.
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
  late BufferHistory? _history = _windowHistory;
  InAppWebViewController? web;

  BufferHistory? get _windowHistory =>
      app.controller.doc.value.windows[window]?.history;

  // flutter_inappwebview_windows 0.6.0 never sets isRedirect (it reads
  // Fetch.requestPaused's redirectedRequestId from inside `request`, where
  // CDP doesn't put it). So a main-frame request that arrives while the
  // entry's own load is still running counts as a server redirect.
  // ponytail: a script navigating before load stop also replaces; drop this
  // once the plugin reports isRedirect.
  bool _loading = false;

  /// This window's current entry as a route, read from the doc: the builder
  /// only gets the buffer. While another page's entry is current (this page
  /// animating out), it stays on [BrowserPage.buffer].
  Object _entryRoute() {
    final entry = _windowHistory?.current;
    return entry != null &&
            links.pageIdentityOf(entry.buffer) ==
                links.pageIdentityOf(widget.buffer)
        ? links.routeOfBuffer(entry.buffer, entry.arguments)
        : links.routeOfBuffer(widget.buffer);
  }

  @override
  void initState() {
    super.initState();
    app.controller.doc.addListener(_follow);
  }

  /// The entry changed within this page (back/forward, pushState, a
  /// replace): render it. Back and forward step the webview's own history,
  /// same-document for pushState entries; anything else loads the entry
  /// unless the webview already shows it (pushState).
  Future<void> _follow() async {
    final before = _history, after = _history = _windowHistory;
    if (before == null || after == null) return;
    final next = _entryRoute();
    if (next == route) return;
    setState(() => route = next);
    final w = web;
    if (next is! WebPage || w == null || next == _shown) return;
    // The webview's history can drift from the window's (a replace loads a
    // new webview entry): step only when the step lands on the entry.
    final step = historyStep(before, after);
    if (step != null) {
      final list = await w.getCopyBackForwardList();
      final target = list?.list?.elementAtOrNull(
        (list.currentIndex ?? -1) + step,
      );
      if (target?.url case final url? when WebPage.of(url) == next) {
        _shown = next;
        await w.goBackOrForward(steps: step);
        return;
      }
    }
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
    // A new page on this window may have registered its webview already.
    if (app.webViews[window] == web) app.webViews.remove(window);
    super.dispose();
  }

  /// A mirror (`view: shared`) draws its original's webview texture; only
  /// the original takes input. Both carry the Mirror badge.
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([app.controller.doc, app.webViewsChanged]),
    child: _own(),
    builder: (_, own) {
      final doc = app.controller.doc.value;
      final source = mirrorSourceOf(doc, window);
      final mirrored =
          source != null ||
          doc.windows.keys.any((w) => mirrorSourceOf(doc, w) == window);
      final web = app.webViews[source];
      return RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (source == null || route is! WebPage)
              own!
            else if (web != null)
              ColoredBox(
                color: T.surfacePage,
                child: IgnorePointer(
                  child: Texture(textureId: web.getViewId() as int),
                ),
              )
            else
              const ColoredBox(color: T.surfacePage),
            if (mirrored)
              const Positioned(
                top: T.space8,
                right: T.space8,
                child: MirrorBadge(),
              ),
          ],
        ),
      );
    },
  );

  Widget _own() => ColoredBox(
    color: T.surfacePage,
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
          app.webViewsChanged.value++;
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
          if (verb == LinkVerb.replace) {
            // Let the redirect finish here: a load issued now would be
            // aborted with the cancelled request.
            _shown = WebPage.of(url);
            _go(verb, url);
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
      HistoryRoute() => _PageList(
        'History',
        (app) => historyOf(app.controller.doc.value),
      ),
      BookmarksRoute() => _PageList('Bookmarks', (app) => app.bookmarks.value),
      SettingsRoute() => const _Settings(),
      _ => const _Notice('New tab', null),
    },
  );
}

/// Marks a mirror split: shown on the mirror and on its original.
class MirrorBadge extends StatelessWidget {
  const MirrorBadge({super.key});

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: ShapeDecoration(
      color: T.surfaceSelected,
      shape: StadiumBorder(),
    ),
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: T.space8, vertical: 2),
      child: Text(
        'Mirror',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: T.accentDefault,
        ),
      ),
    ),
  );
}

/// `/settings`: the restore toggle and the guard's note.
class _Settings extends StatelessWidget {
  const _Settings();

  @override
  Widget build(BuildContext context) {
    final restore = BrowserApp.of(context).restoreSession;
    return Material(
      color: T.surfacePage,
      child: ListView(
        padding: const EdgeInsets.all(T.space40),
        children: [
          const Text(
            'Settings',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: T.textPrimary,
            ),
          ),
          const SizedBox(height: T.space16),
          ValueListenableBuilder(
            valueListenable: restore,
            builder: (_, on, _) => SwitchListTile(
              title: const Text('Restore session on start'),
              value: on,
              activeThumbColor: T.accentDefault,
              onChanged: (v) => restore.value = v,
            ),
          ),
          const SizedBox(height: T.space16),
          const Text(
            'Settings is guarded: while it is locked from the menu, opening it '
            'redirects to the new tab page.',
            style: TextStyle(fontSize: 14, color: T.textMuted),
          ),
        ],
      ),
    );
  }
}

/// An internal page listing the web pages [pagesOf] reads from the doc.
class _PageList extends StatelessWidget {
  const _PageList(this.heading, this.pagesOf);

  final String heading;
  final List<Object> Function(BrowserAppState app) pagesOf;

  @override
  Widget build(BuildContext context) {
    final app = BrowserApp.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([app.controller.doc, app.bookmarks]),
      builder: (_, _) => Material(
        color: T.surfacePage,
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
            for (final page in pagesOf(app))
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
