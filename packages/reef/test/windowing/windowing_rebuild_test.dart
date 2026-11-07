import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reef/reef.dart';

void main() {
  testWidgets('a listener rebuilds once per dispatchAll, never for an '
      'unchanged doc', (tester) async {
    final controller = WindowingController();
    addTearDown(controller.dispose);
    var builds = 0;
    await tester.pumpWidget(ValueListenableBuilder<WindowingDoc>(
      valueListenable: controller.doc,
      builder: (_, doc, _) {
        builds++;
        return const SizedBox();
      },
    ));
    expect(builds, 1);

    final shell = controller.doc.value.focusedShellId;
    controller.dispatchAll([
      NewTab(shellId: shell, tabId: TabId.generate()),
      NewTab(shellId: shell, tabId: TabId.generate()),
    ]);
    await tester.pump();
    expect(builds, 2);

    controller.dispatch(CloseTab(TabId.manual('unknown')));
    await tester.pump();
    expect(builds, 2);
  });

  testWidgets('split, resize and close rebuild; an invalid resize does not',
      (tester) async {
    final controller = WindowingController();
    addTearDown(controller.dispose);
    controller.newTab(buffer: const BufferId.manual('b'));
    final window = controller.doc.value.tabs.values.last.activeWindowId!;
    var builds = 0;
    await tester.pumpWidget(ValueListenableBuilder<WindowingDoc>(
      valueListenable: controller.doc,
      builder: (_, doc, _) {
        builds++;
        return const SizedBox();
      },
    ));

    final split = controller.splitWindow(window, axis: Axis.horizontal);
    await tester.pump();
    controller.resizeWindow(split, [0.25, 0.75]);
    await tester.pump();
    expect(builds, 3);

    controller.resizeWindow(split, [0.5, 0.6]);
    await tester.pump();
    expect(builds, 3);

    controller.closeWindow(split);
    await tester.pump();
    expect(builds, 4);
  });

  testWidgets('history moves rebuild; a move off an empty stack does not',
      (tester) async {
    final controller = WindowingController();
    addTearDown(controller.dispose);
    controller.newTab(buffer: const BufferId.manual('a'));
    final window = controller.doc.value.tabs.values.last.activeWindowId!;
    var builds = 0;
    await tester.pumpWidget(ValueListenableBuilder<WindowingDoc>(
      valueListenable: controller.doc,
      builder: (_, doc, _) {
        builds++;
        return const SizedBox();
      },
    ));

    controller.navigateForward(window);
    controller.popBuffer(window);
    await tester.pump();
    expect(builds, 1);

    controller.pushBuffer(window, const BufferId.manual('b'));
    await tester.pump();
    controller.popBuffer(window);
    await tester.pump();
    controller.navigateForward(window);
    await tester.pump();
    controller.replaceBuffer(window, const BufferId.manual('c'));
    await tester.pump();
    expect(builds, 5);
  });
}
