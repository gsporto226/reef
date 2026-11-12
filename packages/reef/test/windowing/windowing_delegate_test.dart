import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:formularium/features/localization/localizable_interface.dart';
import 'package:reef/reef.dart';

const _shell = ShellId.manual('s');
const _t1 = TabId.manual('t1');
const _t2 = TabId.manual('t2');
const _a = WindowId.manual('a');
const _b = WindowId.manual('b');

WindowState _shows(String buffer) =>
    WindowState(history: BufferHistory(current: HistoryEntry(BufferId.manual(buffer))));

/// Tab `t1`: `a` beside `b`, `a` active. Tab `t2`: empty.
WindowingDoc _doc() => WindowingDoc(
  shells: {
    _shell: ShellState(tabIds: [_t1, _t2], activeTabId: _t1),
  },
  tabs: {
    _t1: TabState(
      activeWindowId: _a,
      root: WindowBranch(
        axis: Axis.horizontal,
        ratios: [0.5, 0.5],
        children: const [WindowLeaf(_a), WindowLeaf(_b)],
      ),
    ),
    _t2: const TabState(),
  },
  windows: {_a: _shows('A'), _b: _shows('B')},
  focusedShellId: _shell,
);

class _Label implements ILocalizable {
  const _Label(this.text);

  final String text;

  @override
  String localize() => text;
}

Future<WindowingController> _pump(
  WidgetTester tester, {
  WindowingDelegate delegate = const WindowingDelegate(),
  BufferBuilder? bufferBuilder,
  Widget? child,
}) async {
  final controller = WindowingController(initial: () => _doc());
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: WindowingRoot(
        controller: controller,
        delegate: delegate,
        bufferBuilder:
            bufferBuilder ?? (_, buffer) => Text('page ${buffer.value}'),
        child: child,
      ),
    ),
  );
  return controller;
}

Border? _borderAround(WidgetTester tester, String page) {
  final box = tester.widget<DecoratedBox>(
    find.ancestor(of: find.text(page), matching: find.byType(DecoratedBox)),
  );
  return (box.decoration as BoxDecoration).border as Border?;
}

void main() {
  testWidgets('the default chrome borders the focused window only', (
    tester,
  ) async {
    await _pump(tester);
    expect(_borderAround(tester, 'page A'), isNotNull);
    expect(_borderAround(tester, 'page B'), isNull);
  });

  testWidgets('windowChrome replaces the default chrome', (tester) async {
    await _pump(
      tester,
      delegate: WindowingDelegate(
        windowChrome: (_, id, focused, page) => Column(
          children: [
            Text('${id.value} ${focused ? 'focused' : 'idle'}'),
            Expanded(child: page),
          ],
        ),
      ),
    );
    expect(find.text('a focused'), findsOneWidget);
    expect(find.text('b idle'), findsOneWidget);
    expect(find.byType(DecoratedBox), findsNothing);
  });

  testWidgets('emptyBuilder replaces the blank empty tab', (tester) async {
    final c = await _pump(tester);
    c.activateTab(_t2);
    await tester.pump();
    expect(find.textContaining('page'), findsNothing);

    await _pump(
      tester,
      delegate: WindowingDelegate(
        emptyBuilder: (_, tab) => Text('empty ${tab.value}'),
      ),
    );
    final c2 = WindowingScope.of(tester.element(find.byType(ShellHost)))
        .controller;
    c2.activateTab(_t2);
    await tester.pump();
    expect(find.text('empty t2'), findsOneWidget);
  });

  testWidgets('hibernatingBuilder renders a window whose page is not ready', (
    tester,
  ) async {
    Widget? notReadyB(BuildContext _, BufferId buffer) =>
        buffer.value == 'B' ? null : Text('page ${buffer.value}');
    await _pump(tester, bufferBuilder: notReadyB);
    expect(find.text('page A'), findsOneWidget);
    expect(find.text('page B'), findsNothing);

    await _pump(
      tester,
      bufferBuilder: notReadyB,
      delegate: WindowingDelegate(
        hibernatingBuilder: (_, window, buffer) =>
            Text('waking ${window.value} ${buffer.value}'),
      ),
    );
    expect(find.text('waking b B'), findsOneWidget);
  });

  testWidgets('a custom windowArrangement receives the tab id', (tester) async {
    await _pump(
      tester,
      delegate: WindowingDelegate(
        windowArrangement: WindowArrangement.custom(
          (_, tab) => Text('carousel ${tab.value}'),
        ),
      ),
    );
    expect(find.text('carousel t1'), findsOneWidget);
    expect(find.text('page A'), findsNothing);
  });

  testWidgets('the default tab strip activates and closes tabs, named by '
      'labels when given', (tester) async {
    Widget strip() => Builder(
      builder: (context) =>
          WindowingDelegateScope.of(context).tabStrip(context, _shell),
    );
    final c = await _pump(tester, child: strip());
    expect(find.text('Tab 1'), findsOneWidget);
    await tester.tap(find.text('Tab 2'));
    expect(c.doc.value.shells[_shell]!.activeTabId, _t2);
    await tester.tap(find.byKey(const ValueKey('close t2')));
    expect(c.doc.value.shells[_shell]!.tabIds, [_t1]);

    await _pump(
      tester,
      child: strip(),
      delegate: WindowingDelegate(
        labels: WindowingLabels(tab: (tab) => _Label('Doc ${tab.value}')),
      ),
    );
    expect(find.text('Doc t1'), findsOneWidget);
  });

  testWidgets('tabStrip replaces the default strip', (tester) async {
    await _pump(
      tester,
      delegate: WindowingDelegate(
        tabStrip: (_, shell) => Text('strip ${shell.value}'),
      ),
      child: Builder(
        builder: (context) =>
            WindowingDelegateScope.of(context).tabStrip(context, _shell),
      ),
    );
    expect(find.text('strip s'), findsOneWidget);
  });

  testWidgets('TabStripSlot exposes tab ids, the active tab, and reorder', (
    tester,
  ) async {
    late TabStripState strip;
    final c = await _pump(
      tester,
      child: TabStripSlot(
        _shell,
        builder: (_, state) {
          strip = state;
          return const SizedBox();
        },
      ),
    );
    expect(strip.tabIds, [_t1, _t2]);
    expect(strip.activeTabId, _t1);
    strip.reorder(_t2, 0);
    await tester.pump();
    expect(c.doc.value.shells[_shell]!.tabIds, [_t2, _t1]);
    expect(strip.tabIds, [_t2, _t1]);
  });

  test('labels default to none', () {
    const labels = WindowingLabels();
    expect(labels.shell(_shell), isNull);
    expect(labels.tab(_t1), isNull);
    expect(labels.window(_a), isNull);
    expect(labels.buffer(const BufferId.manual('A')), isNull);
  });

  testWidgets('WindowingRoot hands the interceptor to the controller', (
    tester,
  ) async {
    final controller = await _pump(
      tester,
      delegate: WindowingDelegate(
        interceptor: (_, _) =>
            const CommandDecision.veto(UndoLabel('read only')),
      ),
    );
    final before = controller.doc.value;
    controller.newTab();
    expect(controller.doc.value, same(before));
    expect(controller.vetoes.value!.reason.localize(), 'read only');
  });

  test('copyWith replaces only the given hooks', () {
    Widget chrome(BuildContext _, WindowId _, bool _, Widget page) => page;
    Widget empty(BuildContext _, TabId _) => const SizedBox();
    Widget waking(BuildContext _, WindowId _, BufferId _) => const SizedBox();
    Widget strip(BuildContext _, ShellId _) => const SizedBox();
    Widget splitter(BuildContext _, Axis _) => const SizedBox();
    Widget floating(BuildContext _, WindowId _, Rect? _, int _, Widget w) => w;
    CommandDecision interceptor(WindowingDoc _, WindowingCommand _) =>
        const CommandDecision.approve();
    WindowingProjection policy(
      BuildContext _,
      WindowingController _,
      ShellId _,
    ) =>
        (_, _, _) => const SizedBox();
    const labels = WindowingLabels();
    final arrangement = WindowArrangement.custom((_, _) => const SizedBox());
    const base = WindowingDelegate();
    expect(base.copyWith(), isNot(same(base)));
    final d = base.copyWith(
      windowChrome: chrome,
      emptyBuilder: empty,
      hibernatingBuilder: waking,
      labels: labels,
      windowArrangement: arrangement,
      tabStrip: strip,
      splitter: splitter,
      floating: floating,
      interceptor: interceptor,
      projectionPolicy: policy,
    );
    expect(
      (
        d.windowChrome,
        d.emptyBuilder,
        d.hibernatingBuilder,
        d.labels,
        d.windowArrangement,
        d.tabStrip,
        d.splitter,
        d.floating,
        d.interceptor,
        d.projectionPolicy,
      ),
      (
        chrome,
        empty,
        waking,
        labels,
        arrangement,
        strip,
        splitter,
        floating,
        interceptor,
        policy,
      ),
    );
    expect(base.copyWith().windowChrome, base.windowChrome);
  });

  testWidgets('WindowingDelegateScope overrides the delegate for a subtree '
      'only', (tester) async {
    await _pump(
      tester,
      child: Builder(
        builder: (context) => Row(
          children: [
            const Expanded(child: TabCanvas(_t2)),
            Expanded(
              child: WindowingDelegateScope(
                delegate: WindowingDelegateScope.of(
                  context,
                ).copyWith(emptyBuilder: (_, _) => const Text('scoped empty')),
                child: const TabCanvas(_t2),
              ),
            ),
          ],
        ),
      ),
    );
    expect(find.text('scoped empty'), findsOneWidget);
  });

  testWidgets('a unit outside any root uses the default delegate', (
    tester,
  ) async {
    late WindowingDelegate delegate;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          delegate = WindowingDelegateScope.of(context);
          return const SizedBox();
        },
      ),
    );
    expect(delegate.windowArrangement, isNull);
  });
}
