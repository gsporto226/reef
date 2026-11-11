import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reef/reef.dart';

const s1 = ShellId.manual('s1');
const t1 = TabId.manual('t1');
const w1 = WindowId.manual('w1');
const b0 = BufferId.manual('b0');
const b1 = BufferId.manual('b1');

/// Shell s1, tab t1, one window w1 showing b1 over b0.
final doc = WindowingDoc(
  shells: {s1: ShellState(tabIds: [t1], activeTabId: t1)},
  tabs: {t1: TabState(root: WindowLeaf(w1), activeWindowId: w1)},
  windows: {
    w1: WindowState(history: BufferHistory(back: [b0], current: b1)),
  },
  focusedShellId: s1,
);

void main() {
  late List<String> platformCalls;

  setUp(() {
    platformCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      platformCalls.add(call.method);
      return null;
    });
  });

  Future<WindowingController> pump(WidgetTester tester) async {
    final c = WindowingController(
      initial: doc,
      focusPolicy:
          const WindowingFocusPolicy(emptyBack: EmptyBackAction.unhandled),
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: WindowingRoot(
        controller: c,
        bufferBuilder: (_, _) => const SizedBox.expand(),
        child: const WindowingSystemBack(child: SizedBox()),
      ),
    ));
    return c;
  }

  testWidgets('system back pops the active window; unhandled back reaches '
      'the platform', (tester) async {
    final c = await pump(tester);

    await tester.binding.handlePopRoute();
    expect(c.doc.value.windows[w1]!.history.current, b0);
    expect(platformCalls, isNot(contains('SystemNavigator.pop')));

    await tester.binding.handlePopRoute();
    expect(c.doc.value.windows[w1]!.history.current, b0);
    expect(platformCalls, contains('SystemNavigator.pop'));
  });

  testWidgets('removed, it no longer takes system back', (tester) async {
    final c = await pump(tester);
    await tester.pumpWidget(const SizedBox());

    await tester.binding.handlePopRoute();
    expect(c.doc.value, doc);
    expect(platformCalls, contains('SystemNavigator.pop'));
  });
}
