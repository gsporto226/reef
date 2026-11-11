// The mail client's acceptance flows (docs/integration-apps.md).
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mail_client/main.dart' as app;
import 'package:mail_client/main.dart';
import 'package:reef/reef.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  void size(WidgetTester tester, double width) {
    tester.view
      ..physicalSize = Size(width, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<WindowingController> boot(
    WidgetTester tester,
    HibernationStore store, {
    Uri? launchLink,
  }) async {
    await tester.pumpWidget(const SizedBox()); // tears the last run down
    await tester.pumpWidget(MailApp(store: store, launchLink: launchLink));
    await tester.pumpAndSettle();
    return tester.state<MailAppState>(find.byType(MailApp)).controller;
  }

  Future<void> tap(WidgetTester tester, String text) async {
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  WindowState showing(WindowingController c, BufferId buffer) => c
      .doc
      .value
      .windows
      .values
      .singleWhere((w) => w.history.current == buffer);

  testWidgets('the entrypoint boots on the folder list beside the inbox', (
    tester,
  ) async {
    size(tester, 1200);
    app.main();
    await tester.pumpAndSettle();
    expect(find.text('Archive'), findsOneWidget);
    expect(find.text('Lunch on Friday?'), findsOneWidget);
  });

  testWidgets('1. expanded to compact switches projection, not the doc', (
    tester,
  ) async {
    size(tester, 1200);
    final c = await boot(tester, InMemoryHibernationStore());
    final doc = c.doc.value;
    expect(find.text('Archive'), findsOneWidget);
    expect(find.text('Lunch on Friday?'), findsOneWidget);

    size(tester, 400);
    await tester.pumpAndSettle();

    expect(c.doc.value, same(doc));
    expect(find.text('Archive'), findsNothing);
    expect(find.text('Lunch on Friday?'), findsOneWidget);
  });

  testWidgets('2. on compact, system back pops the window history; an empty '
      'history goes to focusPolicy', (tester) async {
    final platform = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        platform.add(call.method);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    size(tester, 400);
    final c = await boot(tester, InMemoryHibernationStore());

    await tap(tester, 'Lunch on Friday?');
    expect(find.text('Noon works.'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Lunch on Friday?'), findsOneWidget);
    expect(platform, isNot(contains('SystemNavigator.pop')));

    // The inbox's history is empty: EmptyBackAction.unhandled.
    await tester.binding.handlePopRoute();
    expect(platform, contains('SystemNavigator.pop'));

    // The folder list is one tap away on compact.
    await tester.tap(find.byTooltip('Folders'));
    await tester.pumpAndSettle();
    expect(find.text('Archive'), findsOneWidget);
    expect(showing(c, folderList).history.back, isEmpty);
  });

  testWidgets('3. a notification on a fresh install builds shell, tab and a '
      'window showing the thread', (tester) async {
    size(tester, 1200);
    final c = await boot(
      tester,
      InMemoryHibernationStore(),
      launchLink: Uri.parse('/threads/42'),
    );

    final doc = c.doc.value;
    expect(doc.shells, hasLength(1));
    expect(doc.tabs, hasLength(1));
    expect(doc.windows.values.single.history.current, thread('42'));
    expect(find.text('Noon works.'), findsOneWidget);
  });

  testWidgets('4. a notification on a restored doc pushes or focuses per '
      'linkPolicy and keeps the layout', (tester) async {
    size(tester, 1200);
    final store = InMemoryHibernationStore();
    var c = await boot(tester, store);
    await tap(tester, 'Archive');

    // Not shown anywhere: the open policy pushes it on the detail window.
    c = await boot(tester, store, launchLink: Uri.parse('/threads/42'));
    expect(c.doc.value.windows, hasLength(2));
    expect(showing(c, thread('42')).history.back, [folder('archive')]);
    expect(find.text('Archive'), findsOneWidget);
    expect(find.text('Noon works.'), findsOneWidget);

    // Shown already: focused, nothing pushed.
    final list = c.doc.value.windows.entries
        .singleWhere((e) => e.value.history.current == folderList)
        .key;
    c.activateWindow(list);
    final before = c.doc.value.windows;
    c = await boot(tester, store, launchLink: Uri.parse('/threads/42'));
    final tab = c.doc.value.tabs.values.single;
    expect(c.doc.value.windows, before);
    expect(
      c.doc.value.windows[tab.activeWindowId]!.history.current,
      thread('42'),
    );
  });
}
