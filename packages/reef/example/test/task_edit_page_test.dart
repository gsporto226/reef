import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reef/features/page_identity/_implementations/buffer_id.dart';
import 'package:reef_example/features/task_editor/_presentation/edit/task_edit_model.dart';
import 'package:reef_example/features/task_editor/_presentation/edit/task_edit_page.dart';
import 'package:reef_example/features/task_editor/_presentation/edit/task_edit_provider.dart';
import 'package:reef_example/undo_providers.dart';

/// Fixed buffer id so tests read the same viewmodel the page renders.
const testBufferId = BufferId.manual('test');

Future<TaskEditViewModel> pumpPage(WidgetTester tester) async {
  await tester.pumpWidget(ProviderScope(
    child: WidgetsApp(
      color: const Color(0xFF00695C),
      builder: (_, _) => TaskEditPage(bufferId: testBufferId),
    ),
  ));
  final context = tester.element(find.byType(EditableText));
  final container = ProviderScope.containerOf(context, listen: false);
  return container.read(taskEditViewModelProvider(bufferId: testBufferId));
}

void main() {
  testWidgets('renders the page from model state', (tester) async {
    await pumpPage(tester);

    expect(find.text('Not saved yet'), findsOneWidget);
    expect(find.text('Pick a due date'), findsOneWidget);
  });

  testWidgets('live style: picking a past date surfaces the field error and never publishes',
      (tester) async {
    final vm = await pumpPage(tester);
    final before = vm.model;

    vm.onDueDatePicked(DateTime(2020, 1, 1));
    await tester.pump();

    expect(vm.model, before, reason: 'invalid input never publishes');
    expect(find.text('The due date cannot be in the past.'), findsOneWidget);
  });

  testWidgets('live style: picking a valid date applies the model method and publishes',
      (tester) async {
    final vm = await pumpPage(tester);
    final future = DateTime.now().add(const Duration(days: 30));

    vm.onDueDatePicked(future);
    await tester.pump();

    expect(vm.model.dueDate, future);
    expect(find.textContaining('Due:'), findsOneWidget);
  });

  testWidgets('live style: clearing the due date publishes null', (tester) async {
    final vm = await pumpPage(tester);

    vm.onDueDatePicked(DateTime.now().add(const Duration(days: 10)));
    await tester.pump();
    expect(vm.model.dueDate, isNotNull);

    vm.onDueDatePicked(null);
    await tester.pump();

    expect(vm.model.dueDate, isNull);
    expect(find.text('Pick a due date'), findsOneWidget);
  });

  testWidgets('quick picks: Today, +1 week and Clear set the due date',
      (tester) async {
    final vm = await pumpPage(tester);

    await tester.tap(find.text('+1 week'));
    await tester.pump();
    expect(vm.model.dueDate, isNotNull);

    await tester.tap(find.text('Clear'));
    await tester.pump();
    expect(vm.model.dueDate, isNull);

    await tester.tap(find.text('Today'));
    await tester.pump();
    expect(find.text('Pick a due date'), findsNothing);
  });

  testWidgets('route seed reaches the one viewmodel the scope resolves',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: WidgetsApp(
        color: const Color(0xFF00695C),
        builder: (_, _) => const TaskEditPage(
          bufferId: testBufferId,
          initial: TaskEditModel(title: 'Seeded'),
        ),
      ),
    ));
    final container = ProviderScope.containerOf(
        tester.element(find.byType(EditableText)),
        listen: false);

    expect(
        container.read(taskEditViewModelProvider(bufferId: testBufferId))
            .model
            .title,
        'Seeded');
    expect(container.read(taskEditSeedsProvider), isEmpty,
        reason: 'the seed is consumed on first materialization');
  });

  testWidgets('in-channel: typing into the field mutates the model through the viewmodel',
      (tester) async {
    final vm = await pumpPage(tester);

    await tester.enterText(find.byType(EditableText), 'Buy milk');
    await tester.pump();

    expect(vm.model.title, 'Buy milk');
  });

  testWidgets('typing a run into the title is one undo step', (tester) async {
    final vm = await pumpPage(tester);
    final undo = ProviderScope.containerOf(tester.element(find.byType(EditableText)))
        .read(undoControllerProvider);

    for (final text in ['B', 'Bu', 'Buy']) {
      await tester.enterText(find.byType(EditableText), text);
    }
    undo.undo();
    await tester.pump();

    expect(vm.model.title, '');
    expect(undo.$canUndo.value, isFalse);
  });

  testWidgets('submit style: save runs full validation, applies and reports the operation',
      (tester) async {
    final vm = await pumpPage(tester);

    await tester.enterText(find.byType(EditableText), 'Buy milk');
    vm.onDueDatePicked(DateTime.now().add(const Duration(days: 10)));
    await tester.pump();

    // Pump while the save runs: the second pump advances the fake clock past
    // the save's Future.delayed and renders the final state.
    final done = vm.onSubmit();
    await tester.pump(); // render Saving…
    await tester.pump(const Duration(milliseconds: 500)); // fire timer → Saved!
    await done;

    expect(find.text('Saved!'), findsOneWidget);
    expect(vm.model.title, 'Buy milk');
  });

  testWidgets('submit style: save failure surfaces through the operation', (tester) async {
    final vm = await pumpPage(tester);

    vm.onDueDatePicked(DateTime.now().add(const Duration(days: 10)));
    await tester.pump();

    final done = vm.onSubmit(); // title empty → fake service fails
    await tester.pump(); // render Saving…
    await tester.pump(const Duration(milliseconds: 500)); // fire timer → error
    await done;

    expect(find.text('Could not save the task. Try again.'), findsOneWidget);
  });

  testWidgets('hibernation: restore re-seeds the UI objects from the model', (tester) async {
    final vm = await pumpPage(tester);

    await tester.enterText(find.byType(EditableText), 'Before hibernation');
    await tester.pump();

    final json = vm.model.toJson();
    expect(json['title'], 'Before hibernation');

    vm.restore({'title': 'Restored', 'dueDate': null});
    await tester.pump();

    expect(vm.model.title, 'Restored');
    final controller =
        tester.widget<EditableText>(find.byType(EditableText)).controller;
    expect(
      controller.text,
      'Restored',
      reason: 'out-channel re-seeded the controller from the published model',
    );
  });

  testWidgets('hibernate bar: snapshot, edit, restore', (tester) async {
    final vm = await pumpPage(tester);
    expect(find.text('No snapshot'), findsOneWidget);

    await tester.enterText(find.byType(EditableText), 'Kept');
    await tester.tap(find.text('Hibernate'));
    await tester.pump();
    expect(find.text('Snapshot stored'), findsOneWidget);

    await tester.enterText(find.byType(EditableText), 'Changed');
    await tester.tap(find.text('Restore'));
    await tester.pump();
    expect(vm.model.title, 'Kept');
  });

  testWidgets(
      'closing the window auto-hibernates; reopening the buffer id '
      'rematerializes the state', (tester) async {
    await pumpPage(tester);

    await tester.enterText(find.byType(EditableText), 'Buy milk');
    await tester.pump();

    // Close the buffer's only window — the provider disposes and the
    // dispose hook hibernates the model JSON.
    await tester.pumpWidget(ProviderScope(
      child: WidgetsApp(
        color: const Color(0xFF00695C),
        builder: (_, _) => const SizedBox(),
      ),
    ));
    await tester.pump();

    // Reopen the SAME buffer id — the provider re-runs, reads the hibernated
    // seed and rebuilds the viewmodel from it.
    final vm = await pumpPage(tester);

    expect(vm.model.title, 'Buy milk',
        reason: 'state came back from the hibernation store');
    expect(find.text('Buy milk'), findsOneWidget,
        reason: 'the fresh controller was seeded from the model');
  });
}
