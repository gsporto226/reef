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

  testWidgets('split, resize, close window', (tester) async {
    final controller = WindowingController();
    controller.newTab(buffer: const BufferId.manual('b'));
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: WindowingDemo(controller: controller),
    ));
    expect(find.text('windows: 1'), findsOneWidget);

    await tester.tap(find.text('split'));
    await tester.pumpAndSettle();
    expect(find.text('windows: 2'), findsOneWidget);
    expect(find.text('ratios: 0.5 0.5'), findsOneWidget);

    await tester.tap(find.text('resize'));
    await tester.pumpAndSettle();
    expect(find.text('ratios: 0.25 0.75'), findsOneWidget);

    await tester.tap(find.text('close window'));
    await tester.pumpAndSettle();
    expect(find.text('windows: 1'), findsOneWidget);

    await tester.tap(find.text('close window'));
    await tester.pumpAndSettle();
    expect(find.textContaining('windows:'), findsNothing);
  });

  testWidgets('push, back, forward', (tester) async {
    final controller = WindowingController();
    controller.newTab(buffer: const BufferId.manual('b'));
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: WindowingDemo(controller: controller),
    ));
    expect(find.text('buffer: b'), findsOneWidget);

    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();
    expect(find.text('buffer: pushed'), findsOneWidget);

    await tester.tap(find.text('back'));
    await tester.pumpAndSettle();
    expect(find.text('buffer: b'), findsOneWidget);

    await tester.tap(find.text('forward'));
    await tester.pumpAndSettle();
    expect(find.text('buffer: pushed'), findsOneWidget);
  });

  testWidgets('attach shell, move tab, move window', (tester) async {
    final controller = WindowingController();
    controller.newTab(buffer: const BufferId.manual('b'));
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: WindowingDemo(controller: controller),
    ));
    expect(find.text('shells: 1'), findsOneWidget);

    await tester.tap(find.text('new shell'));
    await tester.pumpAndSettle();
    expect(find.text('shells: 2'), findsOneWidget);
    expect(find.textContaining('windows:'), findsNothing);

    await tester.tap(find.text('take tab'));
    await tester.pumpAndSettle();
    expect(find.text('tab 2'), findsOneWidget);
    expect(find.text('active: 2'), findsOneWidget);
    expect(find.text('windows: 1'), findsOneWidget);

    await tester.tap(find.text('window to tab 1'));
    await tester.pumpAndSettle();
    expect(find.text('active: 1'), findsOneWidget);
    expect(find.text('buffer: b'), findsOneWidget);
  });
}
