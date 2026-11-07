import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reef/reef.dart';
import 'package:reef_example/features/windowing/windowing_demo.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('new tab, activate, close', (tester) async {
    final controller = WindowingController();
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: WindowingDemo(controller: controller),
    ));
    expect(find.text('active: 1'), findsOneWidget);

    await tester.tap(find.text('+'));
    await tester.pumpAndSettle();
    expect(find.text('tab 2'), findsOneWidget);
    expect(find.text('active: 2'), findsOneWidget);

    await tester.tap(find.text('tab 1'));
    await tester.pumpAndSettle();
    expect(find.text('active: 1'), findsOneWidget);

    await tester.tap(find.text('x 2'));
    await tester.pumpAndSettle();
    expect(find.text('tab 2'), findsNothing);
    expect(find.text('active: 1'), findsOneWidget);
  });
}
