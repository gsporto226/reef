import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reef/features/page_identity/_implementations/buffer_id.dart';
import 'package:reef_example/features/task_editor/_presentation/list/task_list_page.dart';

const testBufferId = BufferId.manual('task-list-test');

Future<void> pumpListPage(WidgetTester tester) async {
  await tester.pumpWidget(ProviderScope(
    child: WidgetsApp(
      color: const Color(0xFF00695C),
      builder: (_, _) => TaskListPage(bufferId: testBufferId),
    ),
  ));
  await tester.pump(); // loadingFirst → loader (sync-ish)
  await tester.pump(); // loaded with page 1
}

void main() {
  testWidgets('renders the first page from the fake source', (tester) async {
    await pumpListPage(tester);

    expect(find.text('Buy milk'), findsOneWidget);
    expect(find.text('Ship reef'), findsNothing,
        reason: 'page 2 not loaded yet (15 items, page size 10)');
  });

  testWidgets('typing a filter restarts the list through the sync contract',
      (tester) async {
    await pumpListPage(tester);

    await tester.enterText(find.byType(EditableText), 'reef');
    await tester.pump();
    await tester.pump();

    expect(find.text('Refactor reef'), findsOneWidget);
    expect(find.text('Buy milk'), findsNothing,
        reason: 'accumulation reset by the new filter');
  });

  testWidgets('scrolling near the end loads the next page', (tester) async {
    await pumpListPage(tester);

    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pump();
    await tester.pump();

    expect(find.text('Ship reef'), findsOneWidget,
        reason: 'page 2 accumulated');

    // Another fling reaches the empty page — end of the list, no crash.
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pump();
    await tester.pump();

    // Back to the top — the list kept everything accumulated.
    await tester.drag(find.byType(ListView), const Offset(0, 2000));
    await tester.pump();
    expect(find.text('Buy milk'), findsOneWidget);
  });
}
