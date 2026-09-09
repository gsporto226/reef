import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reef_auto_route/reef_auto_route.dart';
import 'package:reef_example/main.dart';

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

void main() {
  testWidgets('the routed app opens the task list, tapping a task splits in '
      'an editor pane and the URL follows', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: WidgetsApp.router(
          color: const Color(0xFF00695C),
          routerConfig: appRouter.config(),
        ),
      ),
    );
    await _settle(tester);

    expect(find.byType(ListView), findsOneWidget,
        reason: 'the default URL deep-links the task-list buffer');
    expect(find.text('Buy milk'), findsOneWidget);

    await tester.tap(find.text('Buy milk'));
    await _settle(tester);

    expect(find.byType(ListView), findsOneWidget,
        reason: 'the list pane survives the split');
    expect(find.byType(EditableText), findsNWidgets(2),
        reason: 'list filter + the new editor pane');

    final data =
        RouteData.of(tester.element(find.byType(WorkspaceShell)));
    expect(data.queryParams.optString('b'), 'task-edit:Buy milk',
        reason: 'the split focused the new buffer — URL follows');
  });
}
