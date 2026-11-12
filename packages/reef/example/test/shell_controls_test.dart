import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reef/reef.dart';
import 'package:reef_example/main.dart';
import 'package:reef_example/main_windowing.dart' show startingLayout;

const _list = BufferId.manual('/:');
const _edit = BufferId.of('/tasks/*/edit', 'Buy milk');

/// One shell with two tabs, the task list and the editor (active), drawn by
/// the example's shell chrome over [platform].
Future<WindowingController> _pump(
    WidgetTester tester, FakeShellPlatform platform,
    {VoidCallback? onResetLayout}) async {
  tester.view
    ..physicalSize = const Size(1200, 800)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controller =
      WindowingController(initial: () => startingLayout(_list), platform: platform)
        ..newTab(buffer: _edit);
  addTearDown(controller.dispose);
  final shell = controller.doc.value.focusedShellId;
  await tester.pumpWidget(ProviderScope(
    child: WindowingRoot(
      controller: controller,
      bufferBuilder: bufferPageFor,
      child: ExampleShell(shell, onResetLayout: onResetLayout ?? () {}),
    ),
  ));
  await tester.pump();
  return controller;
}

Iterable<BufferId> _buffers(WindowingDoc doc, ShellId shell) => [
      for (final tab in doc.shells[shell]!.tabIds)
        for (final window in doc.tabs[tab]!.root!.windowIds)
          doc.windows[window]!.history.current.buffer,
    ];

void main() {
  testWidgets('with pop-out support the shell controls open, pop out and '
      'close shells', (tester) async {
    final platform = FakeShellPlatform();
    final controller = await _pump(tester, platform);
    final first = controller.doc.value.focusedShellId;

    await tester.tap(find.text('Open in window'));
    await tester.pump();
    var doc = controller.doc.value;
    expect(platform.opened, hasLength(1));
    expect(_buffers(doc, platform.opened.last), [_edit]);

    await tester.tap(find.text('New shell'));
    await tester.pump();
    expect(platform.opened, hasLength(2));
    expect(controller.doc.value.shells, hasLength(3));

    await tester.tap(find.text('Pop out tab'));
    await tester.pump();
    doc = controller.doc.value;
    expect(platform.opened, hasLength(3));
    expect(_buffers(doc, platform.opened.last), [_edit]);
    expect(_buffers(doc, first), [_list]);

    await tester.tap(find.text('Close shell'));
    await tester.pump();
    expect(platform.closed, [first]);
    expect(controller.doc.value.shells.containsKey(first), isFalse);
  });

  testWidgets('without pop-out support no shell control shows',
      (tester) async {
    await _pump(tester, FakeShellPlatform(isSupported: false));

    expect(find.byType(EditableText), findsWidgets,
        reason: 'the editor is drawn');
    for (final label in [
      'Open in window',
      'New shell',
      'Pop out tab',
      'Close shell',
    ]) {
      expect(find.text(label), findsNothing, reason: label);
    }
  });

  testWidgets('"Reset layout" shows with or without pop-out support',
      (tester) async {
    var resets = 0;
    await _pump(tester, FakeShellPlatform(isSupported: false),
        onResetLayout: () => resets++);

    await tester.tap(find.text('Reset layout'));
    expect(resets, 1);
  });
}
