import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reef/features/responsive/_implementations/screen_type_layout.dart';

Widget _app(double width) => WidgetsApp(
      color: const Color(0xFF00695C),
      builder: (_, _) => MediaQuery(
        data: MediaQueryData(size: Size(width, 800)),
        child: ScreenTypeLayout(
          mobile: (_) => const Text('mobile'),
          tablet: (_) => const Text('tablet'),
          desktop: (_) => const Text('desktop'),
        ),
      ),
    );

Widget _bare(double width, ScreenTypeLayout layout) => WidgetsApp(
      color: const Color(0xFF00695C),
      builder: (_, _) => MediaQuery(
        data: MediaQueryData(size: Size(width, 800)),
        child: layout,
      ),
    );

void main() {
  testWidgets('width below 600 → mobile', (tester) async {
    await tester.pumpWidget(_app(500));
    expect(find.text('mobile'), findsOneWidget);
  });

  testWidgets('width 600–839 → tablet', (tester) async {
    await tester.pumpWidget(_app(700));
    expect(find.text('tablet'), findsOneWidget);
  });

  testWidgets('width 840+ → desktop', (tester) async {
    await tester.pumpWidget(_app(1000));
    expect(find.text('desktop'), findsOneWidget);
  });

  testWidgets('tablet falls back to mobile when unspecified', (tester) async {
    await tester.pumpWidget(_bare(
      700,
      ScreenTypeLayout(mobile: _text('mobile')),
    ));
    expect(find.text('mobile'), findsOneWidget);
  });

  testWidgets('desktop falls back tablet → mobile when unspecified',
      (tester) async {
    await tester.pumpWidget(_bare(
      1000,
      ScreenTypeLayout(mobile: _text('mobile')),
    ));
    expect(find.text('mobile'), findsOneWidget);

    await tester.pumpWidget(_bare(
      1000,
      ScreenTypeLayout(mobile: _text('mobile'), tablet: _text('tablet')),
    ));
    expect(find.text('tablet'), findsOneWidget);
  });
}

WidgetBuilder _text(String label) => (_) => Text(label);
