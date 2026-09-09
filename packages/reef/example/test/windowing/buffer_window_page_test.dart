import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reef/features/page_identity/_implementations/buffer_id.dart';
import 'package:reef_example/features/task_editor/_presentation/edit/task_edit_model.dart';
import 'package:reef_example/features/task_editor/_presentation/edit/task_edit_page.dart';
import 'package:reef_example/features/windowing/buffer_window_page.dart';

void main() {
  testWidgets('renders the header and the buffer content', (tester) async {
    final bufferId = BufferId.manual('task-edit:Buy milk');

    await tester.pumpWidget(
      ProviderScope(
        child: WidgetsApp(
          color: const Color(0xFF00695C),
          builder: (_, _) => BufferWindowPage(
            bufferId: bufferId,
            title: 'task-edit:Buy milk',
            contentBuilder: (_, id) => TaskEditPage(
              bufferId: id,
              initial: const TaskEditModel(title: 'Buy milk'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('task-edit:Buy milk'), findsOneWidget);
    final field = tester.widget<EditableText>(find.byType(EditableText));
    expect(field.controller.text, 'Buy milk');
  });
}
