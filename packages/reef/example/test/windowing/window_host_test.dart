import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reef/features/page_identity/_implementations/buffer_id.dart';
import 'package:reef_example/features/task_editor/_presentation/edit/task_edit_model.dart';
import 'package:reef_example/features/task_editor/_presentation/edit/task_edit_page.dart';
import 'package:reef_example/features/windowing/window_host.dart';

void main() {
  testWidgets('Open in window — tap opens the scoped buffer through the host',
      (tester) async {
    final host = FakeWindowHost();
    final bufferId = BufferId.manual('task-edit:Buy milk');

    await tester.pumpWidget(
      ProviderScope(
        child: WidgetsApp(
          color: const Color(0xFF00695C),
          builder: (_, _) => TaskEditPage(
            bufferId: bufferId,
            initial: const TaskEditModel(title: 'Buy milk'),
            windowHost: host,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Open in window'));
    await tester.pump();

    expect(host.requests.single.bufferId, bufferId);
    expect(host.requests.single.title, 'task-edit:Buy milk');
  });

  testWidgets('no window host — the affordance is absent', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: WidgetsApp(
          color: const Color(0xFF00695C),
          builder: (_, _) => TaskEditPage(
            bufferId: BufferId.manual('task-edit:Buy milk'),
            initial: const TaskEditModel(title: 'Buy milk'),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Open in window'), findsNothing);
  });
}
