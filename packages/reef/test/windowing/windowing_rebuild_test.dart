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

  testWidgets('each move rebuilds once; a refused move does not',
      (tester) async {
    final controller = WindowingController();
    addTearDown(controller.dispose);
    final first = controller.doc.value.focusedShellId;
    controller.newTab(buffer: const BufferId.manual('a'));
    final window = controller.doc.value.tabs.values.last.activeWindowId!;
    final tab = controller.doc.value.shells[first]!.activeTabId;
    var builds = 0;
    await tester.pumpWidget(ValueListenableBuilder<WindowingDoc>(
      valueListenable: controller.doc,
      builder: (_, doc, _) {
        builds++;
        return const SizedBox();
      },
    ));

    final shell = controller.attachShell();
    await tester.pump();
    controller.moveTab(tab, shellId: shell, index: 1);
    await tester.pump();
    final target = controller.doc.value.shells[shell]!.tabIds.first;
    controller.moveWindow(window, tabId: target);
    await tester.pump();
    expect(builds, 4);

    final last = controller.doc.value.shells[first]!.tabIds.single;
    controller.moveTab(last, shellId: shell, index: 0);
    await tester.pump();
    expect(builds, 4, reason: "a shell's last tab never moves out");

    controller.closeShell(first);
    await tester.pump();
    expect(builds, 5);
  });

  testWidgets('float, raise and dock each rebuild once; refused ones do not',
      (tester) async {
    final controller = WindowingController();
    addTearDown(controller.dispose);
    final tab = controller.newTab(buffer: const BufferId.manual('a'));
    final first = controller.doc.value.tabs[tab]!.activeWindowId!;
    final second = controller.splitWindow(first, axis: Axis.horizontal);
    var builds = 0;
    await tester.pumpWidget(ValueListenableBuilder<WindowingDoc>(
      valueListenable: controller.doc,
      builder: (_, doc, _) {
        builds++;
        return const SizedBox();
      },
    ));

    controller.floatWindow(first, scope: TabScope(tab));
    await tester.pump();
    controller.floatWindow(second, scope: TabScope(tab));
    await tester.pump();
    controller.raiseWindow(first);
    await tester.pump();
    controller.dockWindow(first, tabId: tab);
    await tester.pump();
    expect(builds, 5);

    controller.raiseWindow(second);
    controller.dockWindow(first, tabId: tab);
    controller.floatWindow(second, scope: TabScope(tab));
    await tester.pump();
    expect(builds, 5, reason: 'already on top, docked, or floating');
  });
}
