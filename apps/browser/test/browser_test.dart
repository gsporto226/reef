import 'package:browser/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reef/reef.dart';

/// The address bar's text field, found by its semantics label.
final addressBar = find.descendant(
  of: find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.label == 'Address bar',
  ),
  matching: find.byType(EditableText),
);

void main() {
  const page = WebPage('http', Host('127.0.0.1:8080'), [
    'docs',
    'a b.html',
  ], 'x=1&y=2');

  group('link tree', () {
    test('a web page round-trips through /web/{scheme}/{host}/**', () {
      final uri = links.uriOf(page);
      expect(uri.pathSegments, [
        'web',
        'http',
        '127.0.0.1:8080',
        'docs',
        'a b.html',
      ]);
      // The site's whole query is one opaque argument (D15).
      expect(uri.queryParameters, {'q': 'x=1&y=2'});
      expect(links.routeOf(uri), page);
      final (:buffer, :arguments) = links.linkOf(page);
      expect(links.routeOfBuffer(buffer, arguments), page);
    });

    test('an empty query is left out of the URL', () {
      const bare = WebPage('https', Host('example.com'), [], '');
      expect(links.uriOf(bare).hasQuery, isFalse);
      expect(links.routeOf(links.uriOf(bare)), bare);
    });

    test('every new tab page is its own buffer', () {
      expect(
        links.linkOf(const NewTabRoute()).buffer,
        isNot(links.linkOf(const NewTabRoute()).buffer),
      );
    });

    test('an unknown internal path is not found', () {
      expect(
        links.routeOf(Uri.parse('/nope/x')),
        const NotFoundRoute(['nope', 'x']),
      );
    });
  });

  group('address bar input', () {
    test('a web URL is that page', () {
      expect(
        routeOfInput('http://127.0.0.1:8080/docs/a%20b.html?x=1&y=2'),
        page,
      );
      expect(addressOf(page), 'http://127.0.0.1:8080/docs/a%20b.html?x=1&y=2');
    });

    test('a path is an internal page', () {
      expect(routeOfInput('/nope'), const NotFoundRoute(['nope']));
      expect(addressOf(const NotFoundRoute(['nope'])), '/nope');
    });

    test('a bare host is https', () {
      expect(
        routeOfInput('example.com/a'),
        const WebPage('https', Host('example.com'), ['a'], ''),
      );
    });
  });

  group('webview navigation', () {
    final url = Uri.parse('http://127.0.0.1:8080/docs/a%20b.html?x=1&y=2');
    final other = Uri.parse('http://127.0.0.1:8080/other.html');

    test('the entry itself loads in the webview', () {
      expect(verbOfNavigation(page, url, redirect: false), isNull);
    });

    test('anything else is cancelled and pushed through reef', () {
      expect(verbOfNavigation(page, other, redirect: false), LinkVerb.push);
      expect(
        verbOfNavigation(const NewTabRoute(), url, redirect: false),
        LinkVerb.push,
      );
    });

    test('a server redirect replaces', () {
      expect(verbOfNavigation(page, other, redirect: true), LinkVerb.replace);
    });
  });

  testWidgets('boots on a new tab; an unknown internal path shows not-found', (
    tester,
  ) async {
    await tester.pumpWidget(BrowserApp(store: InMemoryHibernationStore()));
    await tester.pumpAndSettle();
    expect(find.text('New tab'), findsWidgets);

    await tester.enterText(addressBar, '/nope');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();

    expect(find.text('Page not found'), findsOneWidget);
    final c = tester.state<BrowserAppState>(find.byType(BrowserApp)).controller;
    final doc = c.doc.value;
    expect(
      links.routeOfBuffer(
        doc.windows[doc.activeWindowId]!.history.current.buffer,
      ),
      const NotFoundRoute(['nope']),
    );
  });
  group('tabs', () {
    Future<BrowserAppState> boot(WidgetTester tester) async {
      await tester.pumpWidget(BrowserApp(store: InMemoryHibernationStore()));
      await tester.pumpAndSettle();
      return tester.state<BrowserAppState>(find.byType(BrowserApp));
    }

    Future<void> ctrl(WidgetTester tester, {bool shift = false}) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    List<TabId> tabs(BrowserAppState app) {
      final doc = app.controller.doc.value;
      return doc.shells[doc.focusedShellId]!.tabIds;
    }

    BufferHistory historyOf(BrowserAppState app, TabId tab) {
      final doc = app.controller.doc.value;
      return doc.windows[doc.tabs[tab]!.activeWindowId]!.history;
    }

    testWidgets('two Ctrl+T give two distinct new tab pages', (tester) async {
      final app = await boot(tester);

      await ctrl(tester);
      await ctrl(tester);

      expect(tabs(app), hasLength(3));
      final buffers = {
        for (final t in tabs(app)) historyOf(app, t).current.buffer,
      };
      expect(buffers, hasLength(3));
      expect(app.focusedRoute, isA<NewTabRoute>());
      expect(find.byTooltip('Close tab'), findsNWidgets(3));
    });

    testWidgets('the + button opens a new tab; a tab tap activates it', (
      tester,
    ) async {
      final app = await boot(tester);
      final first = tabs(app).single;

      await tester.tap(find.byTooltip('New tab'));
      await tester.pumpAndSettle();
      expect(tabs(app), hasLength(2));

      await tester.tap(find.text('New tab').first);
      await tester.pumpAndSettle();
      expect(
        app.controller.doc.value.activeTab,
        app.controller.doc.value.tabs[first],
      );
    });

    testWidgets('Ctrl+Shift+T reopens a closed tab with its history', (
      tester,
    ) async {
      final app = await boot(tester);
      await ctrl(tester);
      await tester.enterText(addressBar, '/nope');
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pumpAndSettle();
      final closed = tabs(app).last;
      final history = historyOf(app, closed);
      expect(history.back, hasLength(1));

      await tester.tap(find.byTooltip('Close tab').last);
      await tester.pumpAndSettle();
      expect(tabs(app), isNot(contains(closed)));

      expect(app.undo.$canUndo.value, isTrue);
      await ctrl(tester, shift: true);

      expect(tabs(app), contains(closed));
      expect(historyOf(app, closed), history);
      expect(find.text('Page not found'), findsOneWidget);
    });
  });

  group('history and bookmarks', () {
    final w = WindowId.generate();
    const a = WebPage('http', Host('h'), ['a'], '');
    const b = WebPage('http', Host('h'), ['b'], '');

    WindowingDoc docOf(List<(Object, bool)> visits) {
      final d = WindowingDoc.initial();
      var doc = NewTab(
        shellId: d.focusedShellId,
        tabId: TabId.generate(),
        buffer: (w, links.linkOf(const NewTabRoute()).buffer),
      ).apply(d);
      for (final (route, marked) in visits) {
        final (:buffer, :arguments) = links.linkOf(route);
        doc = PushBuffer(
          w,
          buffer,
          arguments: {...arguments, if (marked) bookmarkKey: ''},
        ).apply(doc);
      }
      return doc;
    }

    test('history is every web page in the doc, once each', () {
      final doc = docOf([
        (a, false),
        (const NotFoundRoute(['x']), false),
        (b, false),
        (a, false),
      ]);
      expect(historyOf(doc), unorderedEquals([a, b]));
    });

    test('bookmarks are the pages whose entry is marked', () {
      expect(bookmarksOf(docOf([(a, true), (b, false)])), [a]);
    });
  });

  group('settings guard', () {
    Future<BrowserAppState> boot(WidgetTester tester) async {
      await tester.pumpWidget(BrowserApp(store: InMemoryHibernationStore()));
      await tester.pumpAndSettle();
      return tester.state<BrowserAppState>(find.byType(BrowserApp));
    }

    Future<void> menu(WidgetTester tester, String item) async {
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item).last);
      await tester.pumpAndSettle();
    }

    BufferHistory history(BrowserAppState app) {
      final doc = app.controller.doc.value;
      return doc.windows[doc.activeWindowId]!.history;
    }

    testWidgets('the menu opens history, bookmarks and settings', (
      tester,
    ) async {
      final app = await boot(tester);
      await menu(tester, 'History');
      expect(app.focusedRoute, const HistoryRoute());
      await menu(tester, 'Bookmarks');
      expect(app.focusedRoute, const BookmarksRoute());
      await menu(tester, 'Settings');
      expect(app.focusedRoute, const SettingsRoute());
    });

    testWidgets('flow 7: locking on settings redirects with no navigation', (
      tester,
    ) async {
      final app = await boot(tester);
      await menu(tester, 'Settings');
      final back = history(app).back;

      await menu(tester, 'Lock settings');

      expect(app.settingsLocked.value, isTrue);
      expect(app.focusedRoute, isA<NewTabRoute>());
      expect(history(app).back, back, reason: 'the entry is replaced');
    });

    testWidgets('locked settings redirects; back skips it; unlock opens it', (
      tester,
    ) async {
      final app = await boot(tester);
      await menu(tester, 'Lock settings');
      await menu(tester, 'History');

      await menu(tester, 'Settings');
      expect(app.focusedRoute, isA<NewTabRoute>());

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(app.focusedRoute, const HistoryRoute());

      await menu(tester, 'Lock settings');
      await menu(tester, 'Settings');
      expect(app.focusedRoute, const SettingsRoute());
    });

    testWidgets('Bookmark marks the current entry', (tester) async {
      final app = await boot(tester);
      await menu(tester, 'History');
      await tester.tap(find.byTooltip('Bookmark'));
      await tester.pumpAndSettle();
      expect(history(app).current.arguments, contains(bookmarkKey));
      await tester.tap(find.byTooltip('Bookmark'));
      await tester.pumpAndSettle();
      expect(history(app).current.arguments, isNot(contains(bookmarkKey)));
    });
  });
}
