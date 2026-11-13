// The browser's acceptance flows (docs/integration-apps.md), against an
// in-test localhost server: no test touches the internet.
import 'dart:io';

import 'package:browser/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reef/reef.dart';

const fixtures = {
  '/links.html':
      '<!doctype html><title>Links fixture</title>'
      '<h1>Links fixture</h1><a href="/two.html">Go to page two</a>',
  '/two.html':
      '<!doctype html><title>Page two</title>'
      '<a href="/redirect">Redirect to page three</a>',
  '/three.html': '<!doctype html><title>Page three</title><h1>SPA</h1>',
};

final addressBar = find.descendant(
  of: find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.label == 'Address bar',
  ),
  matching: find.byType(EditableText),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;
  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) {
      if (req.uri.path == '/redirect') {
        req.response.redirect(Uri.parse('/three.html'));
        return;
      }
      final body = fixtures[req.uri.path];
      req.response
        ..statusCode = body == null ? 404 : 200
        ..headers.contentType = ContentType.html
        ..write(body ?? 'missing')
        ..close();
    });
  });
  tearDownAll(() => server.close(force: true));

  Future<BrowserAppState> boot(WidgetTester tester) async {
    await tester.pumpWidget(BrowserApp(store: InMemoryHibernationStore()));
    await tester.pumpAndSettle();
    return tester.state<BrowserAppState>(find.byType(BrowserApp));
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(addressBar, text);
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
  }

  /// [js] in the focused window's page, once it gives a non-null result.
  Future<Object?> evaluate(
    WidgetTester tester,
    BrowserAppState app,
    String js,
  ) async {
    for (var i = 0; i < 100; i++) {
      final web = app.webViews[app.controller.doc.value.activeWindowId];
      final result = await web?.evaluateJavascript(source: js);
      if (result != null) return result;
      await tester.pump(const Duration(milliseconds: 100));
    }
    fail('No result for $js');
  }

  testWidgets('typing a fixture URL shows it in the focused window', (
    tester,
  ) async {
    final app = await boot(tester);
    final url = 'http://127.0.0.1:${server.port}/links.html';

    await type(tester, url);

    expect(app.focusedRoute, WebPage.of(Uri.parse(url)));
    expect(
      await evaluate(
        tester,
        app,
        "document.readyState == 'complete' ? document.title : null",
      ),
      'Links fixture',
    );
    expect(await evaluate(tester, app, 'location.href'), url);
  });

  testWidgets('an unknown internal path shows not-found', (tester) async {
    final app = await boot(tester);

    await type(tester, '/nope');

    expect(app.focusedRoute, const NotFoundRoute(['nope']));
    expect(find.text('Page not found'), findsOneWidget);
    expect(find.text('/nope'), findsWidgets);
  });

  testWidgets('flow 1: link push, 302 replace, pushState; back and forward', (
    tester,
  ) async {
    final app = await boot(tester);
    String at(String path) => 'http://127.0.0.1:${server.port}$path';
    WebPage page(String path) => WebPage.of(Uri.parse(at(path)));

    /// The focused window's history as (back, current, forward) routes; back
    /// leaves out the boot new-tab entry the typed URL was pushed onto.
    (List<Object>, Object, List<Object>) history() {
      final doc = app.controller.doc.value;
      final h = doc.windows[doc.activeWindowId]!.history;
      Object r(HistoryEntry e) => links.routeOfBuffer(e.buffer, e.arguments);
      return (
        h.back.map(r).whereType<WebPage>().toList(),
        r(h.current),
        h.forward.map(r).toList(),
      );
    }

    /// Waits until the page's title is [title] and it finished loading.
    Future<void> showing(String title) async => expect(
      await evaluate(
        tester,
        app,
        "document.readyState == 'complete' && document.title == '$title'"
        ' ? location.href : null',
      ),
      isA<String>(),
    );

    /// Waits until reef's focused route is [route].
    Future<void> routeIs(Object route) async {
      for (var i = 0; i < 100 && app.focusedRoute != route; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(app.focusedRoute, route);
    }

    await type(tester, at('/links.html'));
    await showing('Links fixture');

    // A link click pushes.
    await evaluate(tester, app, "document.querySelector('a').click(); 1");
    await routeIs(page('/two.html'));
    await showing('Page two');

    // A link to a 302: the click pushes /redirect, the redirect replaces it.
    await evaluate(tester, app, "document.querySelector('a').click(); 1");
    await routeIs(page('/three.html'));
    await showing('Page three');
    expect(history().$1, [page('/links.html'), page('/two.html')]);

    // pushState pushes, replaceState replaces, neither reloads.
    await evaluate(tester, app, "window.marker = 'kept'; 1");
    await evaluate(tester, app, "history.pushState({}, '', '?step=2'); 1");
    await routeIs(page('/three.html?step=2'));
    await evaluate(tester, app, "history.replaceState({}, '', '?step=3'); 1");
    await routeIs(page('/three.html?step=3'));
    expect(history().$1, [
      page('/links.html'),
      page('/two.html'),
      page('/three.html'),
    ]);
    expect(await evaluate(tester, app, 'window.marker'), 'kept');

    // Back and forward move reef's history and reload the entry.
    Future<void> press(String button, String path, String title) async {
      await tester.tap(find.byTooltip(button));
      await tester.pumpAndSettle();
      await routeIs(page(path));
      await showing(title);
      // The webview shows the entry once it has loaded it.
      expect(
        await evaluate(
          tester,
          app,
          "location.href == '${at(path)}' && document.readyState == 'complete'"
          ' && window.marker === undefined ? 1 : null',
        ),
        1,
      );
      expect(find.text(at(path)), findsWidgets);
    }

    // Each reloads the entry, so the pushState page's marker is gone.
    await press('Back', '/three.html', 'Page three');
    await press('Back', '/two.html', 'Page two');
    await press('Back', '/links.html', 'Links fixture');
    await press('Forward', '/two.html', 'Page two');
    await press('Forward', '/three.html', 'Page three');
    await press('Forward', '/three.html?step=3', 'Page three');
    expect(history().$3, isEmpty);
  });
}
