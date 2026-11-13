// Flows 2 and 5 over real platform windows. Run with the windowing flag for
// this invocation only (ADR 0001):
//
//   $env:FLUTTER_WINDOWING='true'
//   fvm flutter test integration_test/multi_window_test.dart -d windows
//
// Without it, ShellViews draws only the focused shell and the tests skip.
import 'package:browser/main.dart';
import 'package:flutter/material.dart';
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final windowing = RealShellPlatform().isSupported;

  Future<BrowserAppState> boot(WidgetTester tester) async {
    await tester.pumpWidget(
      wrapWithView: false,
      BrowserApp(
        store: InMemoryHibernationStore(),
        platform: RealShellPlatform(title: 'Browser'),
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
    // A drag dropped on no strip pops out (onDraggableCanceled).
    await tester.drag(
      find.byWidgetPredicate((w) => w is Draggable).at(1),
      const Offset(0, 400),
    );
    await tester.pumpAndSettle();
    final doc = app.controller.doc.value;
    final popped = doc.shells.keys.firstWhere((s) => s != first);
    expect(doc.shells[popped]!.tabIds, [tab]);
    return (first, popped);
  }

  testWidgets(
    'flow 5: a dragged-out tab is a real window with its own bar and '
    'history; moving it back closes that window',
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

      // Draggable can't cross platform views, so "back" is the drop's
      // handler: moving the window's last tab closes its shell.
      app.moveTabTo(tab, first);
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
}
