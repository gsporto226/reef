import 'dart:convert';
import 'dart:io';

import 'package:browser/file_store.dart';
import 'package:browser/main.dart';
import 'package:flutter/gestures.dart';
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

  testWidgets('a tab title follows its page; a second address navigates', (
    tester,
  ) async {
    await tester.pumpWidget(BrowserApp(store: InMemoryHibernationStore()));
    await tester.pumpAndSettle();
    Finder tabTitle(String t) =>
        find.descendant(of: find.byType(TabStrip), matching: find.text(t));
    expect(tabTitle('New tab'), findsOneWidget);
    for (final path in ['/history', '/bookmarks']) {
      await tester.enterText(addressBar, path);
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pumpAndSettle();
      expect(tabTitle(path), findsOneWidget);
    }
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

    testWidgets('submitting find with no live webview is a no-op', (
      tester,
    ) async {
      final app = await boot(tester);
      await menu(tester, 'Find in page');
      final field = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Find in page',
      );
      await tester.enterText(field, 'needle');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(app.webViews, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the memory saver switch toggles the setting', (tester) async {
      final app = await boot(tester);
      app.nav.go(const SettingsRoute());
      await tester.pumpAndSettle();
      expect(app.memorySaver.value, isTrue);
      await tester.tap(find.text('Memory saver'));
      await tester.pumpAndSettle();
      expect(app.memorySaver.value, isFalse);
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

  group('policies', () {
    Future<BrowserAppState> boot(
      WidgetTester tester, {
      HibernationStore? store,
      double width = 1400,
    }) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        BrowserApp(
          key: UniqueKey(),
          store: store ?? InMemoryHibernationStore(),
        ),
      );
      await tester.pumpAndSettle();
      return tester.state<BrowserAppState>(find.byType(BrowserApp));
    }

    List<TabId> tabs(BrowserAppState app) {
      final doc = app.controller.doc.value;
      return doc.shells[doc.focusedShellId]!.tabIds;
    }

    testWidgets('flow 14: closing the last pane of a tab closes the tab; the '
        'last tab of a shell stays', (tester) async {
      final app = await boot(tester);
      app.newTab();
      await tester.pumpAndSettle();
      final first = tabs(app).first;

      app.controller.closeWindow(app.controller.doc.value.activeWindowId!);
      await tester.pumpAndSettle();
      expect(tabs(app), [first]);

      app.controller.closeWindow(app.controller.doc.value.activeWindowId!);
      await tester.pumpAndSettle();
      expect(tabs(app), [first]);
      expect(app.controller.doc.value.tabs[first]!.root, isNull);
    });

    testWidgets('flow 14: back with no history closes a page-opened tab, '
        'and does nothing elsewhere', (tester) async {
      final app = await boot(tester);
      final opener = tabs(app).single;

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(tabs(app), [opener]);

      app.openFromPage(const HistoryRoute());
      await tester.pumpAndSettle();
      expect(tabs(app), hasLength(2));

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(tabs(app), [opener]);
      expect(app.focusedRoute, isA<NewTabRoute>());
    });

    testWidgets('flow 15: a new tab past the limit is vetoed with its '
        'reason; doc and undo stay', (tester) async {
      final app = await boot(tester);
      while (tabs(app).length < BrowserAppState.maxTabs) {
        app.newTab();
      }
      await tester.pumpAndSettle();
      final doc = app.controller.doc.value;

      app.newTab();
      await tester.pumpAndSettle();

      expect(app.controller.doc.value, same(doc));
      expect(find.text('A window holds at most 10 tabs'), findsOneWidget);
      app.undo.undo(); // the last entry is still the 10th tab
      expect(tabs(app), hasLength(BrowserAppState.maxTabs - 1));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('A window holds at most 10 tabs'), findsNothing);
    });

    testWidgets('flow 15: a split in a narrow window stacks', (tester) async {
      Axis splitAxis(BrowserAppState app) =>
          (app.controller.doc.value.activeTab.root! as WindowBranch).axis;

      var app = await boot(tester);
      app.openInSplit(const HistoryRoute());
      await tester.pumpAndSettle();
      expect(splitAxis(app), Axis.horizontal);

      app = await boot(tester, width: 500);
      app.openInSplit(const HistoryRoute());
      await tester.pumpAndSettle();
      expect(splitAxis(app), Axis.vertical);
    });

    testWidgets("flow 15: the split window's own shell decides, not the "
        'focused one', (tester) async {
      final app = await boot(tester);
      final wide = app.controller.doc.value.activeWindowId!;
      final narrow = app.controller.attachShell();
      app.controller.newTab(
        shellId: narrow,
        buffer: links.linkOf(const HistoryRoute()).buffer,
      );
      await tester.pumpAndSettle();
      final target = app.controller.doc.value.activeWindowId!;
      app.controller.activateWindow(wide);
      app.shellWidths[narrow] = BrowserAppState.narrowShell - 100;
      app.controller.splitWindow(target, axis: Axis.horizontal);
      final doc = app.controller.doc.value;
      final root = doc.tabs[doc.tabOf(target)]!.root! as WindowBranch;
      expect(root.axis, Axis.vertical);
    });

    testWidgets("flow 17: memory saver releases a background tab's page; a "
        'pinned tab and memory saver off keep it', (tester) async {
      final app = await boot(tester);
      app.nav.go(const SettingsRoute());
      await tester.pumpAndSettle();
      expect(app.memorySaver.value, isTrue);
      final settings = find.text('Settings', skipOffstage: false);
      expect(settings, findsOneWidget);

      app.newTab();
      await tester.pumpAndSettle();
      expect(settings, findsNothing, reason: 'released');

      app.controller.activateTab(tabs(app).first);
      await tester.pumpAndSettle();
      app.togglePin();
      app.newTab();
      await tester.pumpAndSettle();
      expect(settings, findsOneWidget, reason: 'pinned: kept, offstage');
      expect(find.text('Settings'), findsNothing);

      app.controller.activateTab(tabs(app).first);
      app.togglePin();
      app.newTab();
      await tester.pumpAndSettle();
      expect(settings, findsNothing);

      app.memorySaver.value = false;
      await tester.pumpAndSettle();
      expect(settings, findsOneWidget, reason: 'memory saver off');
    });

    testWidgets('flow 18: the saved session drops PiP and fresh new tabs; '
        'Clear session starts the next launch fresh', (tester) async {
      final store = InMemoryHibernationStore();
      var app = await boot(tester, store: store);
      app.nav.go(const SettingsRoute());
      await tester.pumpAndSettle();
      app.pictureInPicture();
      app.newTab();
      await tester.pumpAndSettle();
      expect(app.controller.doc.value.floating, hasLength(1));
      expect(tabs(app), hasLength(2));

      app = await boot(tester, store: store);
      expect(app.controller.doc.value.floating, isEmpty);
      expect(tabs(app), hasLength(1));
      expect(app.focusedRoute, const SettingsRoute());

      await tester.tap(find.text('Clear session'));
      await tester.pumpWidget(const SizedBox());
      app = await boot(tester, store: store);
      expect(app.focusedRoute, isA<NewTabRoute>());
    });

    test("flow 18: the saved session keeps a shell's last tab", () {
      final doc = WindowingDoc.initial(
        buffer: links.linkOf(const NewTabRoute()).buffer,
      );
      expect(persistedSession(doc), same(doc));
    });

    testWidgets('flow 19: labels title tabs; an emptied tab shows the empty '
        'state', (tester) async {
      final app = await boot(tester);
      app.nav.go(const HistoryRoute());
      await tester.pumpAndSettle();
      final tab = tabs(app).single;
      final delegate = tester
          .widget<WindowingRoot>(find.byType(WindowingRoot))
          .delegate;
      expect(
        delegate.labels.tab(tab)!.localize(),
        titleOf(const HistoryRoute()),
      );
      expect(find.text('/history'), findsWidgets);
      app.controller.closeWindow(app.controller.doc.value.activeWindowId!);
      await tester.pumpAndSettle();
      expect(find.byType(EmptyTab), findsOneWidget);
    });

    testWidgets('flow 16: "Open links in" sets how a go opens a page, keeps '
        'focusing an open one and survives a restart', (tester) async {
      final store = InMemoryHibernationStore();
      var app = await boot(tester, store: store);
      app.nav.go(const SettingsRoute());
      await tester.pumpAndSettle();
      await tester.tap(find.text('New tab'));
      await tester.pumpAndSettle();
      expect(app.openIn.value, BrowserAppState.tab);

      app.nav.go(const HistoryRoute());
      await tester.pumpAndSettle();
      expect(tabs(app), hasLength(2));
      app.nav.go(const SettingsRoute());
      await tester.pumpAndSettle();
      expect(tabs(app), hasLength(2));
      expect(app.focusedRoute, const SettingsRoute());

      await tester.pumpWidget(const SizedBox());
      app = await boot(tester, store: store);
      expect(app.openIn.value, BrowserAppState.tab);
      app.nav.go(const BookmarksRoute());
      await tester.pumpAndSettle();
      expect(tabs(app), hasLength(3));
    });
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
    final nopeTab = find
        .byWidgetPredicate((w) => w is DockSource && w.dockable is TabDockable)
        .at(1);

    Future<BrowserAppState> boot(
      WidgetTester tester, {
      bool supported = true,
    }) async {
      tester.view.physicalSize = const Size(2000, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      platform = FakeShellPlatform(isSupported: supported);
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
      // Past the bottom of the view, on no dock area: a pop-out.
      await tester.drag(nopeTab, const Offset(0, 1000));
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

    testWidgets('flow 10: closing a shell of many tabs asks first; cancel '
        'keeps it, confirm closes it', (tester) async {
      final app = await boot(tester);
      final (first, popped) = await popOut(tester, app);
      app.controller.activateShell(popped);
      app.newTab();
      await tester.pumpAndSettle();
      final before = app.controller.doc.value;

      // The native close button of a non-last shell dispatches this.
      app.controller.closeShell(popped);
      await tester.pumpAndSettle();
      expect(app.controller.doc.value, same(before));
      expect(find.text('Close 2 tabs?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Close 2 tabs?'), findsNothing);
      expect(app.controller.doc.value, same(before));

      app.controller.closeShell(popped);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(app.controller.doc.value.shells.keys, [first]);
      expect(platform.closed, [popped]);
    });

    Future<void> openInNewWindow(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open in new window'));
      await tester.pumpAndSettle();
    }

    testWidgets('flow 11: open in new window opens the page in a new shell', (
      tester,
    ) async {
      final app = await boot(tester);
      app.nav.go(const HistoryRoute());
      await tester.pumpAndSettle();
      final first = app.controller.doc.value.focusedShellId;

      await openInNewWindow(tester);

      final doc = app.controller.doc.value;
      final shell = doc.shells.keys.singleWhere((s) => s != first);
      expect(platform.opened, [shell]);
      final tab = doc.tabs[doc.shells[shell]!.tabIds.single]!;
      expect(app.routeOf(tab.activeWindowId), const HistoryRoute());
      expect(addressBar, findsNWidgets(2));
    });

    testWidgets('flow 11: without pop-out the menu hides open in new window; '
        'a page asking for one gets a new tab', (tester) async {
      final app = await boot(tester, supported: false);
      app.nav.go(const HistoryRoute());
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      expect(find.text('Open in new window'), findsNothing);
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      app.openInNewWindow();
      await tester.pumpAndSettle();

      final doc = app.controller.doc.value;
      expect(platform.opened, isEmpty);
      expect(doc.shells.values.single.tabIds, hasLength(2));
      expect(app.focusedRoute, const HistoryRoute());
    });
    Future<void> menu(WidgetTester tester, String item) async {
      await tester.tap(find.byTooltip('Menu').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(item).last);
      await tester.pumpAndSettle();
    }

    /// History, then Bookmarks in one window (new tab and History back), split by
    /// Settings: (that window, its tab).
    Future<(WindowId, TabId)> paned(
      WidgetTester tester,
      BrowserAppState app,
    ) async {
      app.nav.go(const HistoryRoute());
      await tester.pumpAndSettle();
      app.nav.push(const BookmarksRoute());
      await tester.pumpAndSettle();
      final doc = app.controller.doc.value;
      final window = doc.activeWindowId!;
      app.openInSplit(const SettingsRoute());
      await tester.pumpAndSettle();
      app.controller.activateWindow(window);
      await tester.pumpAndSettle();
      return (window, doc.tabOf(window)!);
    }

    testWidgets('flow 12: move a pane to a new tab; one undo puts it back', (
      tester,
    ) async {
      final app = await boot(tester);
      final (window, tab) = await paned(tester, app);
      final before = app.controller.doc.value;
      expect(before.windows[window]!.history.back, hasLength(2));

      await menu(tester, 'Move to new tab');

      final doc = app.controller.doc.value;
      final moved = doc.tabOf(window)!;
      expect(moved, isNot(tab));
      expect(doc.tabs[moved]!.root!.windowIds, [window]);
      expect(doc.tabs[tab]!.root!.windowIds, hasLength(1));
      expect(doc.windows[window]!.history.back, hasLength(2));
      expect(app.routeOf(window), const BookmarksRoute());

      app.undo.undo();
      await tester.pumpAndSettle();
      final undone = app.controller.doc.value;
      expect(undone.shells, before.shells);
      expect(undone.tabOf(window), tab);
      expect(undone.tabs[tab]!.root!.windowIds, hasLength(2));
    });

    testWidgets('flow 12: move a pane to another shell; one undo puts it '
        'back', (tester) async {
      final app = await boot(tester);
      final (window, tab) = await paned(tester, app);
      app.openInNewWindow(const NewTabRoute());
      await tester.pumpAndSettle();
      final other = app.controller.doc.value.shells.keys.last;
      app.controller.activateWindow(window);
      await tester.pumpAndSettle();
      expect(app.controller.doc.value.focusedShellId, isNot(other));

      await menu(tester, 'Move to window 2');

      final doc = app.controller.doc.value;
      expect(doc.shells[other]!.tabIds, [doc.tabOf(window)]);
      expect(doc.tabs[doc.tabOf(window)]!.root!.windowIds, hasLength(2));
      expect(doc.windows[window]!.history.back, hasLength(2));

      app.undo.undo();
      await tester.pumpAndSettle();
      expect(app.controller.doc.value.tabOf(window), tab);
      expect(app.controller.doc.value.tabs[tab]!.root!.windowIds, hasLength(2));
    });

    /// History mirrored, the mirror moved to a new shell:
    /// (original, mirror, its shell, the mirror's shell).
    Future<(WindowId, WindowId, ShellId, ShellId)> crossMirror(
      WidgetTester tester,
      BrowserAppState app,
    ) async {
      app.nav.go(const HistoryRoute());
      await tester.pumpAndSettle();
      final original = app.controller.doc.value.activeWindowId!;
      app.mirrorSplit();
      await tester.pumpAndSettle();
      final mirror = app.controller.doc.value.activeWindowId!;
      final first = app.controller.doc.value.focusedShellId;
      app.openInNewWindow(const NewTabRoute());
      await tester.pumpAndSettle();
      final other = app.controller.doc.value.focusedShellId;
      app.controller.activateWindow(mirror);
      app.moveToShell(other);
      await tester.pumpAndSettle();
      final doc = app.controller.doc.value;
      expect(doc.shells[other]!.tabIds, [doc.tabOf(mirror)]);
      expect(mirrorSourceOf(doc, mirror), original);
      expect(find.byType(MirrorBadge), findsNWidgets(2));
      return (original, mirror, first, other);
    }

    testWidgets("flow 13: closing a cross-shell mirror's shell keeps the "
        'page in the original', (tester) async {
      final app = await boot(tester);
      final (original, _, _, other) = await crossMirror(tester, app);
      final buffer =
          app.controller.doc.value.windows[original]!.history.current.buffer;

      app.controller.closeShell(other);
      await tester.pumpAndSettle();

      final doc = app.controller.doc.value;
      expect(doc.windows[original]!.history.current.buffer, buffer);
      expect(app.routeOf(original), const HistoryRoute());
      expect(find.byType(MirrorBadge), findsNothing);
    });

    testWidgets("flow 13: closing the original's shell leaves the mirror on "
        'its own view', (tester) async {
      final app = await boot(tester);
      final (_, mirror, first, other) = await crossMirror(tester, app);

      app.controller.closeShell(first);
      await tester.pumpAndSettle();

      final doc = app.controller.doc.value;
      expect(doc.shells.keys, [other]);
      expect(mirrorSourceOf(doc, mirror), isNull);
      expect(app.routeOf(mirror), const HistoryRoute());
      expect(find.byType(MirrorBadge), findsNothing);
    });

    Finder tabHandle(TabId id) => find.byWidgetPredicate(
      (w) =>
          w is DockSource &&
          w.dockable is TabDockable &&
          (w.dockable as TabDockable).tabId == id,
    );
    Finder grip(WindowId id) => find.descendant(
      of: find.byWidgetPredicate((w) => w is PaneBar && w.windowId == id),
      matching: find.byTooltip('Drag pane'),
    );
    Finder pane(WindowId id) =>
        find.byWidgetPredicate((w) => w is WindowHost && w.windowId == id);
    final vetoTint = find.byWidgetPredicate(
      (w) => w is ColoredBox && w.color == const Color(0x44F44336),
    );

    /// A mouse drag from [from] to [to], [hover] run before the drop.
    Future<void> dragTo(
      WidgetTester tester,
      Finder from,
      Offset to, {
      void Function()? hover,
    }) async {
      final g = await tester.startGesture(
        tester.getCenter(from),
        kind: PointerDeviceKind.mouse,
      );
      await g.moveTo(to);
      await tester.pump();
      hover?.call();
      await g.up();
      await tester.pumpAndSettle();
    }

    /// Two shells side by side: a new tab page, and History in a new window.
    /// (first shell, its window, second shell, its window).
    Future<(ShellId, WindowId, ShellId, WindowId)> twoShells(
      WidgetTester tester,
      BrowserAppState app,
    ) async {
      final first = app.controller.doc.value.focusedShellId;
      final w1 = app.controller.doc.value.activeWindowId!;
      app.openInNewWindow(const HistoryRoute());
      await tester.pumpAndSettle();
      final doc = app.controller.doc.value;
      return (first, w1, doc.focusedShellId, doc.activeWindowId!);
    }

    testWidgets("a tab dropped on another shell's tab lands beside it", (
      tester,
    ) async {
      final app = await boot(tester);
      app.newTab();
      await tester.pumpAndSettle();
      final (first, _, second, _) = await twoShells(tester, app);
      final moved = app.controller.doc.value.shells[first]!.tabIds.last;
      final there = app.controller.doc.value.shells[second]!.tabIds.single;

      await dragTo(
        tester,
        tabHandle(moved),
        tester.getTopLeft(tabHandle(there)) + const Offset(8, 8),
      );

      final doc = app.controller.doc.value;
      expect(doc.shells[second]!.tabIds, [moved, there]);
      expect(doc.shells[first]!.tabIds, hasLength(1));
    });

    testWidgets("a pane dropped on another pane's edge splits it there", (
      tester,
    ) async {
      final app = await boot(tester);
      final (_, w1, second, w2) = await twoShells(tester, app);

      await dragTo(
        tester,
        grip(w1),
        tester.getBottomRight(pane(w2)) - const Offset(10, 300),
      );

      final doc = app.controller.doc.value;
      final tab = doc.shells[second]!.activeTabId;
      expect(doc.tabOf(w1), tab);
      expect(doc.tabs[tab]!.root!.windowIds, [w2, w1]);
      expect((doc.tabs[tab]!.root! as WindowBranch).axis, Axis.horizontal);
    });

    testWidgets("a pane dropped on another pane's centre opens its page "
        'there and closes, its emptied shell with it', (tester) async {
      final app = await boot(tester);
      final (_, w1, second, w2) = await twoShells(tester, app);

      await dragTo(tester, grip(w1), tester.getCenter(pane(w2)));

      final doc = app.controller.doc.value;
      expect(doc.windows, isNot(contains(w1)));
      expect(app.routeOf(w2), isA<NewTabRoute>());
      expect(doc.windows[w2]!.history.back, hasLength(1));
      expect(doc.shells.keys, [second]);
      expect(platform.closed, hasLength(1));
    });

    testWidgets('a pane dropped on a tab strip becomes a new tab there', (
      tester,
    ) async {
      final app = await boot(tester);
      final (first, _, _, w2) = await twoShells(tester, app);

      await dragTo(
        tester,
        grip(w2),
        tester.getCenter(find.byTooltip('New tab').first),
      );

      final doc = app.controller.doc.value;
      expect(doc.shells[first]!.tabIds, hasLength(2));
      expect(doc.tabOf(w2), doc.shells[first]!.tabIds.last);
      expect(doc.shells[first]!.activeTabId, doc.tabOf(w2));
    });

    testWidgets('a drop the interceptor vetoes shows red and changes nothing', (
      tester,
    ) async {
      final app = await boot(tester);
      tester.view.physicalSize = const Size(3200, 900); // room for 10 tabs
      app.newTab();
      await tester.pumpAndSettle();
      final (first, _, second, _) = await twoShells(tester, app);
      while (app.controller.doc.value.shells[second]!.tabIds.length <
          BrowserAppState.maxTabs) {
        app.newTab();
      }
      await tester.pumpAndSettle();
      final before = app.controller.doc.value;

      await dragTo(
        tester,
        tabHandle(before.shells[first]!.tabIds.last),
        tester.getCenter(find.byTooltip('New tab').last),
        hover: () => expect(vetoTint, findsOneWidget),
      );

      expect(app.controller.doc.value, same(before));
      expect(vetoTint, findsNothing);
    });

    testWidgets('panes, tabs and windows close from the UI; a last tab '
        'closes its window, or empties in the last one', (tester) async {
      final app = await boot(tester);
      final (first, _, second, w2) = await twoShells(tester, app);
      app.openInSplit(const BookmarksRoute());
      await tester.pumpAndSettle();
      final split = app.controller.doc.value.activeWindowId!;

      await tester.tap(
        find.descendant(
          of: find.byWidgetPredicate(
            (w) => w is PaneBar && w.windowId == split,
          ),
          matching: find.byTooltip('Close'),
        ),
      );
      await tester.pumpAndSettle();
      expect(app.controller.doc.value.windows, isNot(contains(split)));
      expect(app.controller.doc.value.windows, contains(w2));

      // The second shell's last tab: its window closes, no prompt.
      await tester.tap(find.byTooltip('Close tab').last);
      await tester.pumpAndSettle();
      expect(app.controller.doc.value.shells.keys, [first]);
      expect(platform.closed, [second]);
      expect(find.textContaining('tabs?'), findsNothing);

      // The last shell's last tab empties in place.
      await tester.tap(find.byTooltip('Close tab'));
      await tester.pumpAndSettle();
      expect(app.controller.doc.value.shells[first]!.tabIds, hasLength(1));
      expect(find.byType(EmptyTab), findsOneWidget);
    });
  });
}
