import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reef/reef.dart';
import 'package:reef_example/main.dart';

void main() {
  testWidgets('the app opens the task list through WindowingRoot; tapping a '
      'task splits an editor window beside it', (tester) async {
    // Desktop width: the default projection lays windows side by side.
    tester.view
      ..physicalSize = const Size(1200, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrapWithView: false, const ReefExampleApp());
    await tester.pumpAndSettle();

    expect(find.byType(WindowingRoot), findsOneWidget);
    expect(find.byType(ListView), findsOneWidget);
    expect(find.text('Buy milk'), findsOneWidget);
    expect(find.text('New shell'), findsNothing,
        reason: 'windowing is off: no pop-out controls');

    await tester.tap(find.text('Buy milk'));
    await tester.pumpAndSettle();

    expect(find.byType(ListView), findsOneWidget,
        reason: 'the list window survives the split');
    expect(find.byType(WindowHost), findsNWidgets(2));
    expect(find.byType(EditableText), findsNWidgets(2),
        reason: 'list filter + the new editor window');
  });
}
