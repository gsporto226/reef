// Renders every SPEC.md screen at its breakpoint frame size into
// test/goldens/, the frames to hold against FigCraft screenshots.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mail_client/main.dart';
import 'package:reef/reef.dart';

Future<void> _loadFonts() async {
  for (final (family, files) in [
    ('Source Serif 4', ['source-serif-4-600.ttf']),
    ('Source Sans 3', ['source-sans-3-400.ttf', 'source-sans-3-600.ttf']),
  ]) {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(
        Future.value(ByteData.sublistView(File('fonts/$f').readAsBytesSync())),
      );
    }
    await loader.load();
  }
}

void main() {
  setUpAll(_loadFonts);

  Future<MailAppState> boot(WidgetTester tester, Size size) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MailApp(store: InMemoryHibernationStore()));
    await tester.pumpAndSettle();
    return tester.state<MailAppState>(find.byType(MailApp));
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.tap(find.bySemanticsLabel(label).last);
    await tester.pumpAndSettle();
  }

  Future<void> shot(WidgetTester tester, String name) =>
      expectLater(find.byType(MailApp), matchesGoldenFile('goldens/$name.png'));

  const desktop = Size(1280, 800), tablet = Size(768, 1024);
  const mobile = Size(412, 915);

  testWidgets('Desktop', (tester) async {
    await boot(tester, desktop);
    await shot(tester, 'desktop_inbox');
    await tap(tester, 'Compose');
    await shot(tester, 'desktop_compose');
    await tap(tester, 'Send');
    await tap(tester, 'Collapse sidebar');
    await shot(tester, 'desktop_inbox_collapsed');
  });

  testWidgets('Tablet', (tester) async {
    await boot(tester, tablet);
    await shot(tester, 'tablet_inbox');
    await tap(tester, 'Lunch on Friday?');
    await shot(tester, 'tablet_thread');
    await tap(tester, 'Inbox');
    await shot(tester, 'tablet_thread_overlay');
    await tap(tester, 'Inbox');
    await tap(tester, 'Compose');
    await shot(tester, 'tablet_compose');
    await tap(tester, 'Inbox');
    await shot(tester, 'tablet_compose_overlay');
  });

  testWidgets('Mobile', (tester) async {
    await boot(tester, mobile);
    await shot(tester, 'mobile_inbox');
    await tap(tester, 'Lunch on Friday?');
    await shot(tester, 'mobile_thread');
    await tap(tester, 'Folders');
    await shot(tester, 'mobile_sidebar_open');
    await tap(tester, 'Compose');
    await shot(tester, 'mobile_compose');
  });
}
