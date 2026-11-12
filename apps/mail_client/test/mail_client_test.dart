import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mail_client/main.dart';
import 'package:reef/reef.dart';

void main() {
  test('the default layout is nav | inbox | the first thread', () {
    final doc = defaultLayout();
    final (:nav, :list, :detail) = mailWindows(doc);
    expect(doc.windows[nav]!.history.current.buffer, folderList);
    expect(doc.windows[list]!.history.current.buffer, folder('inbox'));
    expect(doc.windows[detail]!.history.current.buffer, thread('42'));
    expect(doc.windows[detail]!.history.back, [HistoryEntry(noThread)]);
  });

  test('the open policy routes folders to the list and threads to the '
      'detail', () {
    final doc = defaultLayout();
    final (:nav, :list, :detail) = mailWindows(doc);

    expect(mailOpenPolicy(doc, thread('7')), [
      isA<PushBuffer>().having((c) => c.windowId, 'window', detail),
      isA<ActivateWindow>().having((c) => c.windowId, 'window', detail),
    ]);
    // Already shown: focus only.
    expect(mailOpenPolicy(doc, thread('42')), [isA<ActivateWindow>()]);
    expect(mailOpenPolicy(doc, folder('archive')), [
      isA<AttachBuffer>().having((c) => c.windowId, 'window', list),
      isA<AttachBuffer>()
          .having((c) => c.windowId, 'window', detail)
          .having((c) => c.buffer, 'buffer', noThread),
      isA<ActivateWindow>().having((c) => c.windowId, 'window', list),
    ]);
    expect(mailOpenPolicy(doc, folderList), [
      isA<ActivateWindow>().having((c) => c.windowId, 'window', nav),
    ]);
    expect(
      mailOpenPolicy(WindowingDoc.initial(), thread('7')),
      hasLength(3),
    ); // reef's first-window batch for an empty tab
  });

  Future<MailAppState> boot(WidgetTester tester, double width) async {
    tester.view
      ..physicalSize = Size(width, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MailApp(store: InMemoryHibernationStore()));
    await tester.pumpAndSettle();
    return tester.state<MailAppState>(find.byType(MailApp));
  }

  /// Types [text], then lets go of the field: a focused field's cursor
  /// blinks forever, and pumpAndSettle would never return.
  Future<void> type(WidgetTester tester, Finder field, String text) async {
    await tester.enterText(field, text);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.tap(find.bySemanticsLabel(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('desktop: a row opens beside the list; Compose and Send come '
      'back; Inbox leaves a draft; the sidebar collapses', (tester) async {
    final app = await boot(tester, 1280);
    await tap(tester, 'Build is green');
    expect(
      find.text('Ship it. All 214 checks passed on main.'),
      findsNWidgets(2),
    );

    await tap(tester, 'Compose');
    expect(find.text('New message'), findsOneWidget);
    await tap(tester, 'Send');
    expect(find.text('New message'), findsNothing);
    expect(find.text('Reply to CI…'), findsOneWidget);

    await tap(tester, 'Compose');
    await tap(tester, 'Inbox');
    expect(find.text('New message'), findsNothing);

    await tap(tester, 'Collapse sidebar');
    expect(app.collapsed.value, isTrue);
    expect(find.text('FOLDERS'), findsNothing);
    await tap(tester, 'Expand sidebar');
    expect(find.text('FOLDERS'), findsOneWidget);

    await tap(tester, 'Archive');
    expect(find.text('Old receipts'), findsOneWidget);
    expect(app.hasDetail, isFalse);
  });

  testWidgets('tablet: Inbox toggles the overlay over a thread; a tap on the '
      'reading pane, Escape or back close it', (tester) async {
    final app = await boot(tester, 768);
    expect(find.text('Reply to Maya…'), findsNothing); // Tablet / Inbox
    await tap(tester, 'Lunch on Friday?');
    expect(find.text('Reply to Maya…'), findsOneWidget);

    await tap(tester, 'Inbox');
    expect(app.overlay.value, isTrue);
    await tap(tester, 'Inbox');
    expect(app.overlay.value, isFalse);

    await tap(tester, 'Inbox');
    await tester.tapAt(const Offset(700, 600)); // the reading pane
    await tester.pumpAndSettle();
    expect(app.overlay.value, isFalse);

    await tap(tester, 'Inbox');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(app.overlay.value, isFalse);

    await tap(tester, 'Inbox');
    expect(await tester.binding.handlePopRoute(), isTrue);
    expect(app.overlay.value, isFalse);

    // A row in the overlay opens its thread and closes it.
    await tap(tester, 'Inbox');
    await tap(tester, 'Build is green');
    expect(app.overlay.value, isFalse);
    expect(find.text('Reply to CI…'), findsOneWidget);

    await tap(tester, 'Back to Inbox');
    expect(app.hasDetail, isFalse);

    // The expand control does nothing on tablet.
    await tap(tester, 'Expand sidebar');
    expect(app.collapsed.value, isFalse);
  });

  testWidgets('mobile: the nav pill opens over the inbox and every control '
      'closes it', (tester) async {
    final app = await boot(tester, 412);
    for (final close in ['Close', 'Inbox', 'Archive']) {
      await tap(tester, 'Folders');
      expect(find.text('Compose'), findsOneWidget);
      await tap(tester, close);
      expect(find.text('Compose'), findsNothing, reason: close);
    }
    expect(find.text('Old receipts'), findsOneWidget);

    // The labels beside the pill act like its icons.
    for (final label in ['Sent', 'Inbox', 'Archive']) {
      await tap(tester, 'Folders');
      await tester.tap(find.bySemanticsLabel(label).first);
      await tester.pumpAndSettle();
      expect(find.text('Compose'), findsNothing);
    }

    await tap(tester, 'Folders');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Compose'), findsNothing);

    await tap(tester, 'Folders');
    await tap(tester, 'Compose');
    expect(find.text('New message'), findsOneWidget);
    await tap(tester, 'Send');
    expect(app.hasDetail, isFalse);
  });

  testWidgets('search pushes results on the list; typing replaces them; '
      'back or clearing returns to the folder', (tester) async {
    final app = await boot(tester, 1280);
    final bar = find.byType(TextField).first;

    await type(tester, bar, 'rua');
    expect(find.text('1 results for “rua”'), findsOneWidget);
    await type(tester, bar, 'RE');
    // Sender, subject or body, any case: you're, green, receipts.
    expect(find.text('3 results for “RE”'), findsOneWidget);
    expect(app.listFolder, isNull);
    expect(find.text('Inbox'), findsOneWidget); // no folder selected

    final list = app.windows.list!;
    expect(app.controller.doc.value.windows[list]!.history.back, [
      HistoryEntry(folder('inbox')),
    ]); // one entry for the whole query

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(app.listFolder, 'inbox');
    expect(tester.widget<TextField>(bar).controller!.text, isEmpty);

    await type(tester, bar, 'build');
    await type(tester, bar, '');
    expect(app.listFolder, 'inbox');
    await tester.enterText(bar, ''); // nothing to leave
    await tester.pumpAndSettle();
    expect(app.listFolder, 'inbox');

    // A folder tap leaves the search.
    await type(tester, bar, 'build');
    await tap(tester, 'Archive');
    expect(app.listFolder, 'archive');
    expect(app.query, isEmpty);
  });

  testWidgets('tablet: a thread opened from search backs to "Search"', (
    tester,
  ) async {
    await boot(tester, 768);
    await type(tester, find.byType(TextField).first, 'lunch');
    await tap(tester, 'Lunch on Friday?');
    expect(find.bySemanticsLabel('Back to Search'), findsOneWidget);
  });

  testWidgets('Send files the draft in Sent and needs a recipient', (
    tester,
  ) async {
    final app = await boot(tester, 1280);
    await tap(tester, 'Compose');
    final [to, subject, body] = [
      for (final f in find.byType(TextField).evaluate().skip(1))
        (f.widget as TextField).controller!,
    ];
    to.clear();
    await tester.pump();
    await tap(tester, 'Send');
    expect(find.text('New message'), findsOneWidget); // disabled

    to.text = 'ana@example.com';
    subject.clear();
    body.text = 'First line\nSecond line';
    await tester.pump();
    await tap(tester, 'Send');
    expect(find.text('New message'), findsNothing);

    await tap(tester, 'Sent');
    expect(find.text('ana@example.com'), findsOneWidget);
    expect(find.text('(no subject)'), findsOneWidget);
    expect(find.text('First line'), findsOneWidget);
    expect(app.mailbox.unread('sent'), 0);
    expect(find.text('1 conversations · 0 unread'), findsOneWidget);
  });

  testWidgets('unknown buffers and missing threads say so', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: MailPage(BufferId.manual('spam:1')),
      ),
    );
    expect(find.text('Unknown buffer spam:1'), findsOneWidget);

    final app = await boot(tester, 1280);
    app.openThread('99');
    await tester.pumpAndSettle();
    expect(find.text('Missing thread 99'), findsOneWidget);
  });
}
