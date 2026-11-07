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
}
