// The browser's acceptance flows (docs/integration-apps.md), against an
// in-test localhost server: no test touches the internet.
import 'dart:io';

import 'package:browser/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  '/blank.html':
      '<!doctype html><title>Blank fixture</title>'
      '<a target="_blank" href="/two.html">Open page two in a new tab</a>',
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

  testWidgets("a page's history actions target its own window, not the "
      'focused one', (tester) async {
    final app = await boot(tester);
    String at(String path) => 'http://127.0.0.1:${server.port}$path';
    WebPage page(String path) => WebPage.of(Uri.parse(at(path)));

    /// [js] in [window]'s page, once it gives a non-null result.
    Future<Object?> evaluateIn(WindowId window, String js) async {
      for (var i = 0; i < 100; i++) {
        final result = await app.webViews[window]?.evaluateJavascript(
          source: js,
        );
        if (result != null) return result;
        await tester.pump(const Duration(milliseconds: 100));
      }
      fail('No result for $js');
    }

    Future<void> routeIs(WindowId window, Object route) async {
      for (var i = 0; i < 100 && app.routeOf(window) != route; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(app.routeOf(window), route);
    }

    await type(tester, at('/links.html'));
    final left = app.controller.doc.value.activeWindowId!;
    await evaluateIn(
      left,
      "document.readyState == 'complete' ? document.title : null",
    );
    app.nav.openInSplit(page('/three.html'));
    await tester.pumpAndSettle();
    final right = app.controller.doc.value.activeWindowId!;
    expect(right, isNot(left));
    final rightHistory = app.controller.doc.value.windows[right]!.history;

    // pushState and a link click in the unfocused page navigate its window.
    await evaluateIn(left, "history.pushState({}, '', '/links/step2'); 1");
    await routeIs(left, page('/links/step2'));
    await evaluateIn(left, "document.querySelector('a').click(); 1");
    await routeIs(left, page('/two.html'));

    expect(app.controller.doc.value.activeWindowId, right);
    expect(app.routeOf(right), page('/three.html'));
    expect(app.controller.doc.value.windows[right]!.history, rightHistory);
    // Let the plugin's async position reports land before teardown
    // detaches the webviews.
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('flow 3: Ctrl+click splits; an open URL focuses its window; '
      'Ctrl+T and Ctrl+Shift+T work from inside the page', (tester) async {
    final app = await boot(tester);
    String at(String path) => 'http://127.0.0.1:${server.port}$path';
    WebPage page(String path) => WebPage.of(Uri.parse(at(path)));
    WindowingDoc doc() => app.controller.doc.value;

    Future<Object?> evaluateIn(WindowId window, String js) async {
      for (var i = 0; i < 100; i++) {
        final result = await app.webViews[window]?.evaluateJavascript(
          source: js,
        );
        if (result != null) return result;
        await tester.pump(const Duration(milliseconds: 100));
      }
      fail('No result for $js');
    }

    Future<void> until(bool Function() done) async {
      for (var i = 0; i < 100 && !done(); i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(done(), isTrue);
    }

    const ready = "document.readyState == 'complete' ? document.title : null";
    const ctrlClick =
        "document.querySelector('a').dispatchEvent(new MouseEvent('click', "
        '{ctrlKey: true, bubbles: true, cancelable: true})); 1';
    String key({required bool shift}) =>
        "document.dispatchEvent(new KeyboardEvent('keydown', {key: "
        "'${shift ? 'T' : 't'}', ctrlKey: true, shiftKey: $shift, "
        'bubbles: true})); 1';

    await type(tester, at('/links.html'));
    final left = doc().activeWindowId!;
    await evaluateIn(left, ready);

    // Ctrl+click opens the link in a split with its own webview; the page
    // stays where it is.
    await evaluateIn(left, ctrlClick);
    await until(() => doc().windows.length == 2);
    final right = doc().activeWindowId!;
    expect(right, isNot(left));
    expect(app.routeOf(right), page('/two.html'));
    expect(app.routeOf(left), page('/links.html'));
    expect(await evaluateIn(right, ready), 'Page two');

    // Ctrl+Shift+T inside the page undoes the split.
    await evaluateIn(left, key(shift: true));
    await until(() => doc().windows.length == 1);
    expect(doc().windows.keys, [left]);

    // Typing a URL that is already open focuses its window.
    await evaluateIn(left, ctrlClick);
    await until(() => doc().windows.length == 2);
    // The split rebuilt the toolbar, so the field needs focus again.
    await tester.tap(addressBar);
    await tester.pumpAndSettle();
    await type(tester, at('/links.html'));
    expect(
      doc().activeWindowId,
      left,
      reason: '${{for (final w in doc().windows.keys) w: app.routeOf(w)}}',
    );
    expect(doc().windows, hasLength(2));

    // Ctrl+T inside the page opens a new tab.
    await evaluateIn(left, key(shift: false));
    await until(() => doc().shells[doc().focusedShellId]!.tabIds.length == 2);
    expect(app.focusedRoute, isA<NewTabRoute>());
    // Let the plugin's async position reports land before teardown.
    await tester.pump(const Duration(seconds: 1));
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

    // pushState pushes, replaceState replaces, neither reloads, even when
    // they change the path (ADR 0008).
    await evaluate(tester, app, "window.marker = 'kept'; 1");
    await evaluate(tester, app, "history.pushState({}, '', '/three/step2'); 1");
    await routeIs(page('/three/step2'));
    await evaluate(
      tester,
      app,
      "history.replaceState({}, '', '/three/step3'); 1",
    );
    await routeIs(page('/three/step3'));
    expect(history().$1, [
      page('/links.html'),
      page('/two.html'),
      page('/three.html'),
    ]);
    expect(await evaluate(tester, app, 'window.marker'), 'kept');

    // Back and forward move reef's history and step the webview's: within
    // one document (pushState) the page is [kept], else the entry loads.
    Future<void> press(
      String button,
      String path,
      String title, {
      bool kept = false,
    }) async {
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
          ' && window.marker ${kept ? "== 'kept'" : '=== undefined'} ? 1 : null',
        ),
        1,
      );
      expect(find.text(at(path)), findsWidgets);
    }

    // Back to the entry pushState left keeps the document; the rest load.
    await press('Back', '/three.html', 'Page three', kept: true);
    await press('Back', '/two.html', 'Page two');
    await press('Back', '/links.html', 'Links fixture');
    await press('Forward', '/two.html', 'Page two');
    await press('Forward', '/three.html', 'Page three');
    await press('Forward', '/three/step3', 'Page three');
    expect(history().$3, isEmpty);
  });

  group('tabs', () {
    String at(String path) => 'http://127.0.0.1:${server.port}$path';
    WebPage page(String path) => WebPage.of(Uri.parse(at(path)));

    List<TabId> tabs(BrowserAppState app) {
      final doc = app.controller.doc.value;
      return doc.shells[doc.focusedShellId]!.tabIds;
    }

    Future<void> routeIs(
      WidgetTester tester,
      BrowserAppState app,
      Object route,
    ) async {
      for (var i = 0; i < 100 && app.focusedRoute != route; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(app.focusedRoute, route);
    }

    Future<void> showing(
      WidgetTester tester,
      BrowserAppState app,
      String title,
    ) async => expect(
      await evaluate(
        tester,
        app,
        "document.readyState == 'complete' && document.title == '$title'"
        ' ? location.href : null',
      ),
      isA<String>(),
    );

    testWidgets('target=_blank and window.open open a new tab', (tester) async {
      final app = await boot(tester);
      await type(tester, at('/blank.html'));
      await showing(tester, app, 'Blank fixture');
      final opener = tabs(app).single;

      await evaluate(tester, app, "document.querySelector('a').click(); 1");
      await routeIs(tester, app, page('/two.html'));
      await showing(tester, app, 'Page two');
      expect(tabs(app), hasLength(2));
      expect(tabs(app).first, opener);
      // The opener keeps its page.
      final doc = app.controller.doc.value;
      expect(
        app.routeOf(doc.tabs[opener]!.activeWindowId),
        page('/blank.html'),
      );

      await evaluate(tester, app, "window.open('/three.html'); 1");
      await routeIs(tester, app, page('/three.html'));
      await showing(tester, app, 'Page three');
      expect(tabs(app), hasLength(3));
    });

    testWidgets('flow 6: Ctrl+Shift+T reopens a closed tab with its history', (
      tester,
    ) async {
      final app = await boot(tester);
      Future<void> ctrlT({bool shift = false}) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
        if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
      }

      await type(tester, at('/links.html'));
      await showing(tester, app, 'Links fixture');
      await evaluate(tester, app, "document.querySelector('a').click(); 1");
      await routeIs(tester, app, page('/two.html'));
      await showing(tester, app, 'Page two');
      final closed = tabs(app).single;
      final doc = app.controller.doc.value;
      final history = doc.windows[doc.activeWindowId]!.history;

      await ctrlT();
      expect(tabs(app), hasLength(2));
      expect(app.focusedRoute, isA<NewTabRoute>());

      // Back to the page's tab, then close it.
      await tester.tap(find.text('127.0.0.1:${server.port}/two.html'));
      await tester.pumpAndSettle();
      await routeIs(tester, app, page('/two.html'));
      await tester.tap(find.byTooltip('Close tab').first);
      await tester.pumpAndSettle();
      expect(tabs(app), isNot(contains(closed)));
      expect(app.focusedRoute, isA<NewTabRoute>());

      // Browse in the other tab before reopening (ADR 0009). Closing the tab
      // rebuilt the chrome, so focus its address bar first.
      final other = tabs(app).single;
      await tester.tap(addressBar);
      await tester.pumpAndSettle();
      await type(tester, at('/three.html'));
      await routeIs(tester, app, page('/three.html'));
      await showing(tester, app, 'Page three');

      await ctrlT(shift: true);

      // The other tab keeps its navigation.
      final kept = app.controller.doc.value;
      expect(
        app.routeOf(kept.tabs[other]!.activeWindowId),
        page('/three.html'),
      );

      expect(tabs(app), contains(closed));
      await routeIs(tester, app, page('/two.html'));
      final reopened = app.controller.doc.value;
      expect(reopened.windows[reopened.activeWindowId]!.history, history);
      await showing(tester, app, 'Page two');

      // Its history came back with it.
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await routeIs(tester, app, page('/links.html'));
      await showing(tester, app, 'Links fixture');
    });
  });

  group('internal pages', () {
    Future<void> menu(WidgetTester tester, String item) async {
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item).last);
      await tester.pumpAndSettle();
    }

    testWidgets('a bookmarked page shows in history and bookmarks', (
      tester,
    ) async {
      final app = await boot(tester);
      final url = 'http://127.0.0.1:${server.port}/links.html';
      await type(tester, url);
      await evaluate(tester, app, "document.readyState == 'complete' || null");
      await tester.tap(find.byTooltip('Bookmark'));
      await tester.pumpAndSettle();

      await menu(tester, 'Bookmarks');
      expect(find.text(url), findsOneWidget);
      await menu(tester, 'History');
      expect(find.text(url), findsOneWidget);

      await tester.tap(find.text(url));
      await tester.pumpAndSettle();
      expect(app.focusedRoute, WebPage.of(Uri.parse(url)));
      // Let the webview finish starting before teardown (plugin throws).
      await evaluate(tester, app, "document.readyState == 'complete' || null");
    });

    testWidgets('flow 7: the settings guard redirects and re-checks', (
      tester,
    ) async {
      final app = await boot(tester);
      BufferHistory history() {
        final doc = app.controller.doc.value;
        return doc.windows[doc.activeWindowId]!.history;
      }

      // Locking while on settings redirects, with no navigation (D8).
      await menu(tester, 'Settings');
      expect(app.focusedRoute, const SettingsRoute());
      final back = history().back;
      await menu(tester, 'Lock settings');
      expect(app.focusedRoute, isA<NewTabRoute>());
      expect(history().back, back);

      // Opening it while locked redirects; back skips it (D7).
      await menu(tester, 'History');
      await menu(tester, 'Settings');
      expect(app.focusedRoute, isA<NewTabRoute>());
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(app.focusedRoute, const HistoryRoute());

      // Unlocked, it opens.
      await menu(tester, 'Lock settings');
      await menu(tester, 'Settings');
      expect(app.focusedRoute, const SettingsRoute());
      expect(find.text('Settings'), findsWidgets);
    });
  });

  testWidgets('flow 9: PiP docks left and right; focus raises every scope', (
    tester,
  ) async {
    final app = await boot(tester);
    final url = 'http://127.0.0.1:${server.port}/links.html';
    await type(tester, url);
    WindowingDoc doc() => app.controller.doc.value;
    final page = doc().activeWindowId!;
    final shell = doc().focusedShellId;
    final tab = doc().shells[shell]!.activeTabId;

    List<WindowId> floatsOf(FloatScope scope) =>
        (doc().floating.entries.where((e) => e.value.scope == scope).toList()
              ..sort((a, b) => a.value.zIndex.compareTo(b.value.zIndex)))
            .map((e) => e.key)
            .toList();

    Future<void> focus(WindowId id) async {
      final panel = find.byWidgetPredicate(
        (w) => w is FloatPanel && w.windowId == id,
      );
      await tester.tapAt(tester.getTopLeft(panel) + const Offset(6, 6));
      await tester.pumpAndSettle();
    }

    // PiP floats a live copy of the page over the shell.
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Picture in picture'));
    await tester.pumpAndSettle();
    final [pip] = floatsOf(ShellScope(shell));
    expect(app.routeOf(pip), WebPage.of(Uri.parse(url)));
    for (var i = 0; i < 100 && app.webViews[pip] == null; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      await app.webViews[pip]!.evaluateJavascript(source: 'location.href'),
      url,
    );

    // Dock left, float again, dock right.
    await tester.tap(find.byTooltip('Dock left'));
    await tester.pumpAndSettle();
    var root = doc().activeTab.root! as WindowBranch;
    expect(root.children, [WindowLeaf(pip), WindowLeaf(page)]);
    app.controller.floatWindow(pip, scope: ShellScope(shell));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Dock right'));
    await tester.pumpAndSettle();
    root = doc().activeTab.root! as WindowBranch;
    expect(root.children, [WindowLeaf(page), WindowLeaf(pip)]);
    app.controller.closeWindow(pip);
    app.controller.activateWindow(page);
    await tester.pumpAndSettle();

    // At each scope, the float focused last is on top.
    for (final (open, scope) in <(WindowId? Function(), FloatScope)>[
      (app.downloads, TabScope(tab)),
      (app.findInPage, WindowScope(page)),
      (app.pictureInPicture, ShellScope(shell)),
    ]) {
      final a = open()!;
      final b = open()!;
      await tester.pumpAndSettle();
      expect(floatsOf(scope), [a, b]);
      await focus(a);
      expect(floatsOf(scope), [b, a], reason: '$scope');
      // Out of the way of the next scope's floats.
      app.controller.closeWindow(a);
      app.controller.closeWindow(b);
      await tester.pumpAndSettle();
    }
  });
}
