import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mail_client/main.dart';
import 'package:reef/reef.dart';

void main() {
  test(
    'the open policy pushes threads on the detail window and focuses it',
    () {
      final doc = defaultLayout();
      final [list, detail] = doc.tabs.values.single.root!.windowIds.toList();
      final focused = ActivateWindow(list).apply(doc);

      expect(mailOpenPolicy(focused, thread('7')), [
        isA<PushBuffer>().having((c) => c.windowId, 'window', detail),
        isA<ActivateWindow>().having((c) => c.windowId, 'window', detail),
      ]);
      expect(
        mailOpenPolicy(focused, folder('archive')).first,
        isA<AttachBuffer>().having((c) => c.windowId, 'window', detail),
      );
      expect(mailOpenPolicy(doc, folderList), [
        isA<ActivateWindow>().having((c) => c.windowId, 'window', list),
      ]);
      expect(
        mailOpenPolicy(WindowingDoc.initial(), thread('7')),
        hasLength(3),
      ); // reef's first-window batch for an empty tab
    },
  );

  testWidgets('tapping a thread opens it beside the folder list', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1200, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MailApp(store: InMemoryHibernationStore()));

    await tester.tap(find.text('Build is green'));
    await tester.pumpAndSettle();
    expect(find.text('Ship it.'), findsOneWidget);
    expect(find.text('Archive'), findsOneWidget);
  });

  testWidgets('compose opens a draft; unknown buffers say so', (tester) async {
    tester.view
      ..physicalSize = const Size(1200, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MailApp(store: InMemoryHibernationStore()));

    await tester.tap(find.byTooltip('Compose'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Draft'), findsOneWidget);

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: MailPage(BufferId.manual('spam:1')),
      ),
    );
    expect(find.text('Unknown buffer spam:1'), findsOneWidget);
  });
}
