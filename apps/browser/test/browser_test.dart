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

  group('page identity (ADR 0008)', () {
    BufferId buffer(String url) =>
        links.linkOf(WebPage.of(Uri.parse(url))).buffer;

    test('a web page is one page per origin', () {
      final a = links.pageIdentityOf(buffer('http://a.test/one'));
      expect(a, links.pageIdentityOf(buffer('http://a.test/two/three?x=1')));
      expect(a, isNot(links.pageIdentityOf(buffer('http://b.test/one'))));
      expect(a, isNot(links.pageIdentityOf(buffer('https://a.test/one'))));
    });

    test('back and forward are one step; a push is none', () {
      HistoryEntry e(String url) => HistoryEntry(buffer(url));
      final a = e('http://a.test/a'), b = e('http://a.test/b');
      final atB = BufferHistory(back: [a], current: b);
      final atA = BufferHistory(current: a, forward: [b]);
      expect(historyStep(atB, atA), -1);
      expect(historyStep(atA, atB), 1);
      expect(
        historyStep(
          atA,
          BufferHistory(back: [a], current: e('http://a.test/b')),
        ),
        isNull,
      );
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

  group('floats', () {
    Future<BrowserAppState> boot(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(BrowserApp(store: InMemoryHibernationStore()));
      await tester.pumpAndSettle();
      return tester.state<BrowserAppState>(find.byType(BrowserApp));
    }

    Future<void> tap(WidgetTester tester, String tooltip) async {
      await tester.tap(find.byTooltip(tooltip).last);
      await tester.pumpAndSettle();
    }

    Future<void> menu(WidgetTester tester, String item) async {
      await tap(tester, 'Menu');
      await tester.tap(find.text(item).last);
      await tester.pumpAndSettle();
    }

    WindowingDoc doc(BrowserAppState app) => app.controller.doc.value;

    /// The floats of [scope], bottom to top.
    List<WindowId> floatsOf(BrowserAppState app, FloatScope scope) =>
        (doc(app).floating.entries.where((e) => e.value.scope == scope).toList()
              ..sort((a, b) => a.value.zIndex.compareTo(b.value.zIndex)))
            .map((e) => e.key)
            .toList();

    /// Taps float [id] on its title bar's left end.
    Future<void> focus(WidgetTester tester, WindowId id) async {
      final panel = find.byWidgetPredicate(
        (w) => w is FloatPanel && w.windowId == id,
      );
      await tester.tapAt(tester.getTopLeft(panel) + const Offset(6, 6));
      await tester.pumpAndSettle();
    }

    testWidgets('PiP floats the focused page over the shell', (tester) async {
      final app = await boot(tester);
      await tester.enterText(addressBar, '/history');
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pumpAndSettle();
      final page = doc(app).activeWindowId!;

      await menu(tester, 'Picture in picture');

      final [pip] = floatsOf(app, ShellScope(doc(app).focusedShellId));
      expect(app.routeOf(pip), const HistoryRoute());
      expect(find.byType(FloatPanel), findsOneWidget);
      expect(doc(app).activeWindowId, page, reason: 'the tree keeps focus');
    });

    testWidgets('find floats over the window, downloads over the tab', (
      tester,
    ) async {
      final app = await boot(tester);
      final window = doc(app).activeWindowId!;
      final tab = doc(app).shells[doc(app).focusedShellId]!.activeTabId;

      await menu(tester, 'Find in page');
      await menu(tester, 'Downloads');

      final [find_] = floatsOf(app, WindowScope(window));
      expect(app.routeOf(find_), const FindRoute());
      final [downloads] = floatsOf(app, TabScope(tab));
      expect(app.routeOf(downloads), const DownloadsRoute());
      for (final name in fakeDownloads) {
        expect(find.text(name), findsOneWidget);
      }
    });

    for (final (side, tooltip) in [(0, 'Dock left'), (1, 'Dock right')]) {
      testWidgets('flow 9: $tooltip docks PiP beside the focused window', (
        tester,
      ) async {
        final app = await boot(tester);
        final target = doc(app).activeWindowId!;
        final pip = app.pictureInPicture()!;
        await tester.pumpAndSettle();

        await tap(tester, tooltip);

        expect(doc(app).floating, isEmpty);
        final root = doc(app).activeTab.root! as WindowBranch;
        expect(root.children[side], WindowLeaf(pip));
        expect(root.children[1 - side], WindowLeaf(target));
        expect(doc(app).activeWindowId, pip);
      });
    }

    for (final scope in ['shell', 'window', 'tab']) {
      testWidgets('flow 9: focusing a $scope float raises it', (tester) async {
        final app = await boot(tester);
        final d = doc(app);
        final (open, floatScope) = switch (scope) {
          'shell' => (app.pictureInPicture, ShellScope(d.focusedShellId)),
          'window' => (app.findInPage, WindowScope(d.activeWindowId!)),
          _ => (
            app.downloads,
            TabScope(d.shells[d.focusedShellId]!.activeTabId),
          ),
        };
        // Opening a float leaves the tree window focused, so the second
        // one lands on the same scope, on top.
        final a = open()!;
        final b = open()!;
        await tester.pumpAndSettle();
        expect(floatsOf(app, floatScope), [a, b]);

        await focus(tester, a);

        expect(floatsOf(app, floatScope), [b, a]);
      });
    }
  });

  group('splits', () {
    Future<BrowserAppState> boot(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
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

    Future<void> ctrlShiftT(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    testWidgets('open in split is an independent view of the page; '
        'Ctrl+Shift+T undoes it', (tester) async {
      final app = await boot(tester);
      await menu(tester, 'History');
      final first = app.controller.doc.value.activeWindowId!;

      await menu(tester, 'Open in split');

      final split = app.controller.doc.value.activeWindowId!;
      expect(split, isNot(first));
      expect(app.routeOf(split), const HistoryRoute());
      expect(app.routeOf(first), const HistoryRoute());
      expect(find.byType(BrowserPage), findsNWidgets(2));

      await ctrlShiftT(tester);

      expect(app.controller.doc.value.windows.keys, [first]);
      expect(app.focusedRoute, const HistoryRoute());
    });

    testWidgets('flow 3: going to an open page focuses its window', (
      tester,
    ) async {
      final app = await boot(tester);
      await menu(tester, 'History');
      final history = app.controller.doc.value.activeWindowId!;
      app.nav.openInSplit(const BookmarksRoute());
      await tester.pumpAndSettle();

      await menu(tester, 'History');

      expect(app.controller.doc.value.activeWindowId, history);
      expect(app.controller.doc.value.windows, hasLength(2));
    });
  });
}
