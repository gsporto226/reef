import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reef/features/page_identity/_implementations/buffer_id.dart';
import 'package:reef_auto_route/reef_auto_route.dart';

Widget _page(BuildContext context, BufferId bufferId) =>
    Text(bufferId.id, textDirection: TextDirection.ltr);

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      Directionality(textDirection: TextDirection.ltr, child: child),
    );

void main() {
  group('WorkspaceRegistry', () {
    test('kind is the segment before the first colon', () {
      expect(BufferId.manual('task-edit:42').kind, 'task-edit');
      expect(BufferId.manual('a:b:c').kind, 'a');
      expect(BufferId.manual('plain').kind, isNull);
      expect(BufferId.generate().kind, isNull, reason: 'uuids are unroutable');
    });

    testWidgets('builds the registered page for a kind:token id', (tester) async {
      final registry = WorkspaceRegistry(kinds: {'task-edit': _page});
      await _pump(
        tester,
        Builder(
          builder: (context) =>
              registry.buildWindow(context, BufferId.manual('task-edit:42')),
        ),
      );
      expect(find.text('task-edit:42'), findsOneWidget);
    });

    testWidgets('unknown kind falls back to notFoundBuilder', (tester) async {
      final registry = WorkspaceRegistry(
        kinds: {'task-edit': _page},
        notFoundBuilder: (context) => const Text('not found'),
      );
      await _pump(
        tester,
        Builder(
          builder: (context) =>
              registry.buildWindow(context, BufferId.manual('nope:1')),
        ),
      );
      expect(find.text('not found'), findsOneWidget);
    });

    testWidgets('unroutable id falls back to notFoundBuilder', (tester) async {
      final registry = WorkspaceRegistry(
        kinds: {'task-edit': _page},
        notFoundBuilder: (context) => const Text('not found'),
      );
      await _pump(
        tester,
        Builder(
          builder: (context) => registry.buildWindow(context, BufferId.generate()),
        ),
      );
      expect(find.text('not found'), findsOneWidget);
    });

    testWidgets('without notFoundBuilder the fallback is an empty box',
        (tester) async {
      final registry = WorkspaceRegistry(kinds: {'task-edit': _page});
      await _pump(
        tester,
        Builder(
          builder: (context) => registry.buildWindow(context, BufferId.manual('x:1')),
        ),
      );
      expect(find.byType(SizedBox), findsOneWidget);
      expect(find.text('x:1'), findsNothing);
    });
  });
}

