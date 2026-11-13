import 'dart:convert';
import 'dart:io';

import 'package:browser/file_store.dart';
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

    WindowingDoc docOf(List<Object> visits) {
      final d = WindowingDoc.initial();
      var doc = NewTab(
        shellId: d.focusedShellId,
        tabId: TabId.generate(),
        buffer: (w, links.linkOf(const NewTabRoute()).buffer),
      ).apply(d);
      for (final route in visits) {
        final (:buffer, :arguments) = links.linkOf(route);
        doc = PushBuffer(w, buffer, arguments: arguments).apply(doc);
      }
      return doc;
    }

    test('history is every web page in the doc, once each', () {
      final doc = docOf([
        a,
        const NotFoundRoute(['x']),
        b,
        a,
      ]);
      expect(historyOf(doc), unorderedEquals([a, b]));
    });

    test('bookmarks round-trip through their codec', () {
      final routes = [a, const HistoryRoute()];
      expect(
        bookmarksCodec.decode(
          jsonDecode(jsonEncode(bookmarksCodec.encode(routes))),
        ),
        routes,
      );
    });
  });

  group('settings guard', () {
    Future<BrowserAppState> boot(
      WidgetTester tester, [
      HibernationStore? store,
    ]) async {
      await tester.pumpWidget(
        BrowserApp(store: store ?? InMemoryHibernationStore()),
      );
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

    testWidgets('Bookmark toggles the current page, not its entry', (
      tester,
    ) async {
      final app = await boot(tester);
      await menu(tester, 'History');
      final arguments = history(app).current.arguments;
      await tester.tap(find.byTooltip('Bookmark'));
      await tester.pumpAndSettle();
      expect(app.bookmarks.value, [const HistoryRoute()]);
      expect(find.byIcon(Icons.star), findsOneWidget);
      expect(history(app).current.arguments, arguments);
      await tester.tap(find.byTooltip('Bookmark'));
      await tester.pumpAndSettle();
      expect(app.bookmarks.value, isEmpty);
    });

    testWidgets('bookmarks survive a restart and outlive their tab', (
      tester,
    ) async {
      final store = InMemoryHibernationStore();
      final first = await boot(tester, store);
      await menu(tester, 'History');
      await tester.tap(find.byTooltip('Bookmark'));
      await tester.pumpAndSettle();
      expect(first.bookmarked, isTrue);

      await tester.pumpWidget(const SizedBox());
      final second = await boot(tester, store);
      expect(second, isNot(same(first)));
      expect(second.bookmarks.value, [const HistoryRoute()]);
      await menu(tester, 'Bookmarks');
      expect(find.text('/history'), findsWidgets);
    });
  });

  test('the session file store survives a reload; a bad file is empty', () {
    final dir = Directory.systemTemp.createTempSync('browser_store');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/sub/session.json');
    const key = BufferId.manual('k');
    JsonFileHibernationStore(file).save(key, {'a': 1});
    expect(JsonFileHibernationStore(file).load(key), {'a': 1});
    file.writeAsStringSync('not json');
    expect(JsonFileHibernationStore(file).load(key), isNull);
  });

  group('session restore (#84)', () {
    Future<BrowserAppState> boot(
      WidgetTester tester,
      HibernationStore store, {
      String? launch,
    }) async {
      // A new key: a restart is a new app, not an update of the old one.
      await tester.pumpWidget(
        BrowserApp(key: UniqueKey(), store: store, launchArg: launch),
      );
      await tester.pumpAndSettle();
      return tester.state<BrowserAppState>(find.byType(BrowserApp));
    }

    Future<void> restart(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    }

    /// A session with two tabs, a split, a float, history and a bookmark.
    Future<BrowserAppState> browse(
      WidgetTester tester,
      HibernationStore s,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final app = await boot(tester, s);
      app.nav.go(const HistoryRoute());
      await tester.pumpAndSettle();
      app.toggleBookmark();
      app.newTab();
      await tester.pumpAndSettle();
      app.nav.go(const BookmarksRoute());
      await tester.pumpAndSettle();
      app.openInSplit(const HistoryRoute());
      await tester.pumpAndSettle();
      app.downloads();
      await tester.pumpAndSettle();
      return app;
    }

    testWidgets('flow 8: shells, tabs, splits, floats, histories and '
        'bookmarks survive a restart', (tester) async {
      final store = InMemoryHibernationStore();
      final before = (await browse(tester, store)).controller.doc.value;
      expect(before.floating, hasLength(1));
      expect(before.tabs, hasLength(2));

      await restart(tester);
      final app = await boot(tester, store);

      expect(app.controller.doc.value.toRecord(), before.toRecord());
      expect(app.bookmarks.value, [const HistoryRoute()]);
    });

    testWidgets('flow 8: a launch URL opens in a new tab on top', (
      tester,
    ) async {
      final store = InMemoryHibernationStore();
      final before = (await browse(tester, store)).controller.doc.value;
      await restart(tester);

      final app = await boot(tester, store, launch: '/settings');

      final doc = app.controller.doc.value;
      expect(doc.tabs.keys, containsAll(before.tabs.keys));
      expect(doc.tabs, hasLength(3));
      expect(app.focusedRoute, const SettingsRoute());
    });

    testWidgets('a launch URL on a fresh install is the only tab', (
      tester,
    ) async {
      final app = await boot(
        tester,
        InMemoryHibernationStore(),
        launch: '/history',
      );
      expect(app.controller.doc.value.tabs, hasLength(1));
      expect(app.focusedRoute, const HistoryRoute());
    });

    testWidgets('a restored buffer whose route no longer resolves shows '
        'not-found (D4)', (tester) async {
      final store = InMemoryHibernationStore()
        ..save(
          WindowingController.hibernationKey,
          WindowingDoc.initial(buffer: BufferId.of('/old/*', '5')).toRecord(),
        );
      final app = await boot(tester, store);
      expect(app.focusedRoute, const NotFoundRoute(['old', '5']));
      expect(find.text('Page not found'), findsOneWidget);
    });

    testWidgets('with "Restore session on start" off, a restart starts fresh', (
      tester,
    ) async {
      final store = InMemoryHibernationStore();
      final first = await browse(tester, store);
      first.nav.go(const SettingsRoute());
      await tester.pumpAndSettle();
      expect(first.restoreSession.value, isTrue);
      await tester.tap(find.text('Restore session on start'));
      await tester.pumpAndSettle();
      expect(first.restoreSession.value, isFalse);
      await restart(tester);

      final app = await boot(tester, store);
      expect(app.restoreSession.value, isFalse, reason: 'the setting is kept');
      expect(app.controller.doc.value.tabs, hasLength(1));
      expect(app.controller.doc.value.floating, isEmpty);
      expect(app.focusedRoute, isA<NewTabRoute>());
      expect(app.bookmarks.value, [const HistoryRoute()]);
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

  group('mirror split (#85)', () {
    Future<BrowserAppState> boot(
      WidgetTester tester,
      HibernationStore store,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(BrowserApp(key: UniqueKey(), store: store));
      await tester.pumpAndSettle();
      return tester.state<BrowserAppState>(find.byType(BrowserApp));
    }

    Future<void> menu(WidgetTester tester, String item) async {
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item).last);
      await tester.pumpAndSettle();
    }

    final badge = find.byType(MirrorBadge);

    /// History open, then mirrored: (original, mirror).
    Future<(WindowId, WindowId)> mirror(
      WidgetTester tester,
      BrowserAppState app,
    ) async {
      await menu(tester, 'History');
      final original = app.controller.doc.value.activeWindowId!;
      await menu(tester, 'Mirror split');
      return (original, app.controller.doc.value.activeWindowId!);
    }

    testWidgets('Mirror split shares the original view; both show the badge', (
      tester,
    ) async {
      final app = await boot(tester, InMemoryHibernationStore());
      final (original, split) = await mirror(tester, app);

      final doc = app.controller.doc.value;
      expect(split, isNot(original));
      final entry = doc.windows[split]!.history.current;
      expect(entry.buffer, doc.windows[original]!.history.current.buffer);
      expect(entry.arguments[viewKey], 'shared');
      expect(app.routeOf(split), const HistoryRoute());
      expect(mirrorSourceOf(doc, split), original);
      expect(mirrorSourceOf(doc, original), isNull);
      expect(badge, findsNWidgets(2));
    });

    testWidgets('shared survives a restart; without its original a mirror '
        'falls back to its own view', (tester) async {
      final store = InMemoryHibernationStore();
      final (original, split) = await mirror(tester, await boot(tester, store));
      await tester.pumpWidget(const SizedBox());

      var app = await boot(tester, store);
      expect(mirrorSourceOf(app.controller.doc.value, split), original);
      expect(badge, findsNWidgets(2));

      app.controller.closeWindow(original);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      app = await boot(tester, store);

      final doc = app.controller.doc.value;
      expect(doc.windows[split]!.history.current.arguments[viewKey], 'shared');
      expect(mirrorSourceOf(doc, split), isNull);
      expect(badge, findsNothing);
    });
  });

  group('pop-out (#83)', () {
    late FakeShellPlatform platform;
    // The second tab on screen: the /nope tab before and after pop-out.
    final nopeTab = find.byWidgetPredicate((w) => w is Draggable).at(1);

    Future<BrowserAppState> boot(WidgetTester tester) async {
      tester.view.physicalSize = const Size(2000, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      platform = FakeShellPlatform();
      await tester.pumpWidget(
        BrowserApp(store: InMemoryHibernationStore(), platform: platform),
      );
      await tester.pumpAndSettle();
      return tester.state<BrowserAppState>(find.byType(BrowserApp));
    }

    Future<void> type(WidgetTester tester, Finder bar, String text) async {
      await tester.enterText(bar, text);
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pumpAndSettle();
    }

    String textOf(WidgetTester tester, Finder bar) =>
        tester.widget<EditableText>(bar).controller.text;

    /// A second tab on /nope, dragged out of the strip: its own shell.
    Future<(ShellId, ShellId)> popOut(
      WidgetTester tester,
      BrowserAppState app,
    ) async {
      final first = app.controller.doc.value.focusedShellId;
      app.newTab();
      await tester.pumpAndSettle();
      await type(tester, addressBar, '/nope');
      await tester.drag(nopeTab, const Offset(0, 400));
      await tester.pumpAndSettle();
      final doc = app.controller.doc.value;
      return (first, doc.shells.keys.firstWhere((s) => s != first));
    }

    testWidgets('flow 5: drag out makes a shell with its own bar and history; '
        'drag back restores it', (tester) async {
      final app = await boot(tester);
      final (first, popped) = await popOut(tester, app);

      final doc = app.controller.doc.value;
      expect(platform.opened, [popped]);
      final tab = doc.shells[popped]!.tabIds.single;
      expect(doc.shells[first]!.tabIds, hasLength(1));
      expect(
        doc.windows[doc.tabs[tab]!.activeWindowId]!.history.back,
        hasLength(1),
      );
      expect(addressBar, findsNWidgets(2));
      expect(textOf(tester, addressBar.at(0)), '');
      expect(textOf(tester, addressBar.at(1)), '/nope');

      // Back onto the first shell's strip: the popped shell closes.
      await tester.drag(
        nopeTab,
        tester.getCenter(find.byTooltip('New tab').first) -
            tester.getCenter(nopeTab),
      );
      await tester.pumpAndSettle();

      final back = app.controller.doc.value;
      expect(back.shells.keys, [first]);
      expect(back.shells[first]!.tabIds, contains(tab));
      expect(platform.closed, [popped]);
      expect(addressBar, findsOneWidget);
      expect(textOf(tester, addressBar), '/nope');
    });

    testWidgets('flow 2: each bar follows its shell; typing in one leaves the '
        'other; the star follows its own shell', (tester) async {
      final app = await boot(tester);
      final (first, popped) = await popOut(tester, app);

      await type(tester, addressBar.at(0), '/history');
      expect(app.controller.doc.value.focusedShellId, first);
      expect(textOf(tester, addressBar.at(0)), '/history');
      expect(textOf(tester, addressBar.at(1)), '/nope');

      // The popped shell's star bookmarks its own page, not the focused one.
      await tester.tap(find.byTooltip('Bookmark').at(1));
      await tester.pumpAndSettle();
      expect(app.bookmarks.value, [
        const NotFoundRoute(['nope']),
      ]);
      expect(find.byIcon(Icons.star), findsOneWidget);
      expect(
        tester.getCenter(find.byIcon(Icons.star)).dx,
        greaterThan(tester.getCenter(find.byIcon(Icons.star_border)).dx),
      );
      expect(app.controller.doc.value.shells.keys, [first, popped]);
    });
  });
}
