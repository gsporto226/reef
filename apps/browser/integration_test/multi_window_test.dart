// Flows 2, 5, 10, 11, 12 and 13 over real platform windows. Run with the windowing flag for
// this invocation only (ADR 0001):
//
//   $env:FLUTTER_WINDOWING='true'
//   fvm flutter test integration_test/multi_window_test.dart -d windows
//
// Without it, ShellViews draws only the focused shell and the tests skip.
// ignore_for_file: experimental_member_use
import 'dart:io';
import 'dart:ui' as ui;

import 'package:browser/main.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reef/reef.dart';
import 'package:reef_multi_window/reef_multi_window.dart';

final addressBar = find.descendant(
  of: find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.label == 'Address bar',
  ),
  matching: find.byType(EditableText),
);

const red = [255, 0, 0, 255];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final windowing = RealShellPlatform().isSupported;

  // One red page, served locally: no test touches the internet.
  late HttpServer server;
  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(
      (req) => req.response
        ..headers.contentType = ContentType.html
        ..write('<!doctype html><body style="margin:0;background:#ff0000">')
        ..close(),
    );
  });
  tearDownAll(() => server.close(force: true));

  Future<BrowserAppState> boot(WidgetTester tester) async {
    await tester.pumpWidget(
      wrapWithView: false,
      BrowserApp(
        store: InMemoryHibernationStore(),
        platform: _SideBySide(title: 'Browser'),
      ),
    );
    await tester.pumpAndSettle();
    return tester.state<BrowserAppState>(find.byType(BrowserApp));
  }

  /// Submits [text] in [bar] without the keyboard: under windowing the
  /// engine's text input can't find a shell's view ("view with view_id=1
  /// cannot be found"), so the field's own submit handler stands in.
  Future<void> type(WidgetTester tester, Finder bar, String text) async {
    tester
        .widget<TextField>(
          find.ancestor(of: bar, matching: find.byType(TextField)),
        )
        .onSubmitted!(text);
    await tester.pumpAndSettle();
  }

  String textOf(WidgetTester tester, Finder bar) =>
      tester.widget<EditableText>(bar).controller.text;

  Finder tabHandle(TabId id) => find.byWidgetPredicate(
    (w) => w is DockSource && w.dockable == TabDockable(id),
  );

  /// A second tab on /nope, popped out into its own platform window.
  Future<(ShellId, ShellId)> popOut(
    WidgetTester tester,
    BrowserAppState app,
  ) async {
    final first = app.controller.doc.value.focusedShellId;
    app.newTab();
    await tester.pumpAndSettle();
    await type(tester, addressBar, '/nope');
    final tab = app.controller.doc.value.shells[first]!.activeTabId;
    // A dock drag dropped outside the window, on no dock area, pops out.
    await tester.drag(tabHandle(tab), const Offset(0, 3000));
    await tester.pumpAndSettle();
    final doc = app.controller.doc.value;
    final popped = doc.shells.keys.firstWhere((s) => s != first);
    expect(doc.shells[popped]!.tabIds, [tab]);
    return (first, popped);
  }

  testWidgets(
    'flow 5: a dragged-out tab is a real window with its own bar and '
    'history; dragging it back across windows closes that window',
    skip: !windowing,
    (tester) async {
      final app = await boot(tester);
      final (first, popped) = await popOut(tester, app);

      final doc = app.controller.doc.value;
      final tab = doc.shells[popped]!.tabIds.single;
      expect(tester.binding.renderViews, hasLength(2));
      expect(
        doc.windows[doc.tabs[tab]!.activeWindowId]!.history.back,
        hasLength(1),
      );
      expect(addressBar, findsNWidgets(2));
      expect(textOf(tester, addressBar.at(0)), '');
      expect(textOf(tester, addressBar.at(1)), '/nope');

      // Back by a mouse drag from the popped window onto the first one's
      // strip. Windows captures the mouse for the window it was pressed in,
      // so that view keeps getting the moves, past its edge; the gesture
      // sends them the same way, and reef maps them into the first window
      // through both views' screen origins.
      final from = View.of(tester.element(tabHandle(tab)));
      final newTab = find
          .byTooltip('New tab')
          .evaluate()
          .firstWhere((e) => View.of(e) != from);
      final to = View.of(newTab);
      final platform = app.controller.platform!;
      final a = platform.viewOrigin(from)!, b = platform.viewOrigin(to)!;
      final box = newTab.renderObject! as RenderBox;
      final target = box.localToGlobal(box.size.center(Offset.zero));
      final drop =
          (b - a + target * to.devicePixelRatio) / from.devicePixelRatio;
      expect(
        (Offset.zero & from.physicalSize / from.devicePixelRatio).contains(
          drop,
        ),
        isFalse,
        reason: 'the windows overlap on screen at the drop',
      );
      final g = await tester.startGesture(
        tester.getCenter(tabHandle(tab)),
        kind: PointerDeviceKind.mouse,
        view: from,
      );
      await g.moveTo(drop);
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();

      final back = app.controller.doc.value;
      expect(back.shells.keys, [first]);
      expect(back.shells[first]!.tabIds, contains(tab));
      expect(tester.binding.renderViews, hasLength(1));
      expect(textOf(tester, addressBar), '/nope');
    },
  );

  testWidgets(
    "flow 2: each real window's bar follows its shell; typing in one leaves "
    'the other',
    skip: !windowing,
    (tester) async {
      final app = await boot(tester);
      final (first, _) = await popOut(tester, app);

      app.controller.activateShell(first);
      await tester.pumpAndSettle();
      await type(tester, addressBar.at(0), '/history');
      expect(app.controller.doc.value.focusedShellId, first);
      expect(textOf(tester, addressBar.at(0)), '/history');
      expect(textOf(tester, addressBar.at(1)), '/nope');
    },
  );

  testWidgets(
    'flow 10: closing a real window of many tabs asks first; confirming '
    'closes it',
    skip: !windowing,
    (tester) async {
      final app = await boot(tester);
      final (first, popped) = await popOut(tester, app);
      app.controller.activateShell(popped);
      app.newTab();
      await tester.pumpAndSettle();

      // What the native close button of a non-last window dispatches.
      app.controller.closeShell(popped);
      await tester.pumpAndSettle();
      expect(app.controller.doc.value.shells.keys, [first, popped]);
      expect(find.text('Close 2 tabs?'), findsOneWidget);

      // The prompt's button, through its handler (no taps across views).
      app.answerClose(confirmed: true);
      await tester.pumpAndSettle();
      expect(app.controller.doc.value.shells.keys, [first]);
      expect(tester.binding.renderViews, hasLength(1));
    },
  );

  testWidgets(
    'flow 11: open in new window is a real window on that page',
    skip: !windowing,
    (tester) async {
      final app = await boot(tester);
      app.openInNewWindow(const HistoryRoute());
      await tester.pumpAndSettle();

      expect(tester.binding.renderViews, hasLength(2));
      expect(app.controller.doc.value.shells, hasLength(2));
      expect(textOf(tester, addressBar.at(1)), '/history');
    },
  );

  testWidgets(
    'flow 12: a pane moves into another real window with its history',
    skip: !windowing,
    (tester) async {
      final app = await boot(tester);
      app.nav.go(const HistoryRoute());
      await tester.pumpAndSettle();
      final window = app.controller.doc.value.activeWindowId!;
      app.openInSplit(const BookmarksRoute());
      app.openInNewWindow(const SettingsRoute());
      await tester.pumpAndSettle();
      final other = app.controller.doc.value.focusedShellId;
      final history = app.controller.doc.value.windows[window]!.history;

      app.controller.activateWindow(window);
      app.moveToShell(other);
      await tester.pumpAndSettle();

      final doc = app.controller.doc.value;
      expect(doc.tabOf(window), doc.shells[other]!.activeTabId);
      expect(doc.windows[window]!.history, same(history));
      expect(tester.binding.renderViews, hasLength(2));
      expect(textOf(tester, addressBar.at(1)), '/history');

      app.undo.undo();
      await tester.pumpAndSettle();
      expect(
        app.controller.doc.value.tabOf(window),
        isNot(app.controller.doc.value.shells[other]!.activeTabId),
      );
    },
  );

  /// The RGBA of [window]'s page at its left edge, half way down, once it
  /// reads [rgba] (or after 5 s).
  Future<List<int>> pixel(
    WidgetTester tester,
    WindowId window,
    List<int> rgba,
  ) async {
    Future<List<int>> read() async {
      final page = find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is WindowHost && w.windowId == window,
        ),
        matching: find.byType(BrowserPage),
      );
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.descendant(of: page, matching: find.byType(RepaintBoundary)).first,
      );
      return (await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final at = (image.height ~/ 2 * image.width + 4) * 4;
        return data!.buffer.asUint8List().sublist(at, at + 4);
      }))!;
    }

    for (var i = 0; i < 50; i++) {
      if ('${await read()}' == '$rgba') break;
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    return read();
  }

  /// A red page mirrored, the mirror moved into a new real window:
  /// (app, original, mirror, its window, the mirror's window).
  Future<(BrowserAppState, WindowId, WindowId, ShellId, ShellId)> crossMirror(
    WidgetTester tester,
  ) async {
    final app = await boot(tester);
    await type(tester, addressBar, 'http://127.0.0.1:${server.port}/');
    final original = app.controller.doc.value.activeWindowId!;
    final first = app.controller.doc.value.focusedShellId;
    app.mirrorSplit();
    final mirror = app.controller.doc.value.activeWindowId!;
    app.openInNewWindow(const NewTabRoute());
    await tester.pumpAndSettle();
    final other = app.controller.doc.value.focusedShellId;
    app.controller.activateWindow(mirror);
    app.moveToShell(other);
    await tester.pumpAndSettle();
    expect(mirrorSourceOf(app.controller.doc.value, mirror), original);
    expect(app.webViews.keys, [original], reason: 'no second webview');
    // The original's texture, drawn in the other platform window.
    expect(await pixel(tester, mirror, red), red);
    return (app, original, mirror, first, other);
  }

  testWidgets(
    "flow 13: a mirror in another real window draws its original's "
    'webview; closing that window keeps the page in the original',
    skip: !windowing,
    (tester) async {
      final (app, original, _, _, other) = await crossMirror(tester);
      app.controller.closeShell(other);
      await tester.pumpAndSettle();
      expect(tester.binding.renderViews, hasLength(1));
      expect(app.webViews.keys, [original]);
      expect(await pixel(tester, original, red), red);
    },
  );

  testWidgets(
    "flow 13: closing the original's real window leaves the mirror on its "
    'own webview',
    skip: !windowing,
    (tester) async {
      final (app, _, mirror, first, _) = await crossMirror(tester);
      app.controller.closeShell(first);
      await tester.pumpAndSettle();
      expect(mirrorSourceOf(app.controller.doc.value, mirror), isNull);
      expect(app.webViews.keys, contains(mirror));
      expect(await pixel(tester, mirror, red), red);
    },
  );
}

/// Real shells whose views sit side by side on a known screen. Under
/// flutter_test's binding a shell's window is a test double with no native
/// handle, so the Win32 origin lookup can't run here.
class _SideBySide extends RealShellPlatform {
  _SideBySide({super.title});

  @override
  Offset? viewOrigin(ui.FlutterView view) => Offset(view.viewId * 4000.0, 0);
}
