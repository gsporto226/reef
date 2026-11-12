import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reef/reef.dart';

const _shell = ShellId.manual('s');
const _tab = TabId.manual('t');
const _a = WindowId.manual('a');
const _b = WindowId.manual('b');
const _c = WindowId.manual('c');
const _d = WindowId.manual('d');

WindowState _shows(String buffer) =>
    WindowState(history: BufferHistory(current: BufferId.manual(buffer)));

/// `a` | (`b` over `c`) | `d`, thirds; the middle one halves.
WindowingDoc _doc() => WindowingDoc(
  shells: {
    _shell: ShellState(tabIds: [_tab], activeTabId: _tab),
  },
  tabs: {
    _tab: TabState(
      activeWindowId: _a,
      root: WindowBranch(
        axis: Axis.horizontal,
        ratios: [0.25, 0.5, 0.25],
        children: [
          const WindowLeaf(_a),
          WindowBranch(
            axis: Axis.vertical,
            ratios: [0.5, 0.5],
            children: const [WindowLeaf(_b), WindowLeaf(_c)],
          ),
          const WindowLeaf(_d),
        ],
      ),
    ),
  },
  windows: {_a: _shows('A'), _b: _shows('B'), _c: _shows('C'), _d: _shows('D')},
  focusedShellId: _shell,
);

List<double> _rootRatios(WindowingController c) =>
    (c.doc.value.tabs[_tab]!.root! as WindowBranch).ratios;

List<double> _innerRatios(WindowingController c) =>
    ((c.doc.value.tabs[_tab]!.root! as WindowBranch).children[1]
            as WindowBranch)
        .ratios;

void main() {
  late UndoController undo;
  late WindowingController c;

  Future<void> pump(
    WidgetTester tester, {
    WindowingDelegate delegate = const WindowingDelegate(),
  }) async {
    await tester.binding.setSurfaceSize(const Size(808, 608));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    undo = UndoController();
    c = WindowingController(initial: () => _doc(), undo: undo);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: WindowingRoot(
          controller: c,
          bufferBuilder: (_, _) => const SizedBox.expand(),
          delegate: delegate,
        ),
      ),
    );
  }

  Finder handle(int i) => find.byType(WindowResizeHandle).at(i);

  testWidgets('flexTree places a handle between the children of every branch', (
    tester,
  ) async {
    await pump(tester);
    // Depth-first: root a|bc, inner b/c, root bc|d.
    expect(find.byType(WindowResizeHandle), findsNWidgets(3));
  });

  testWidgets('a drag shifts share between the two neighbours only, keeping '
      'a minimum share and a sum of one', (tester) async {
    await pump(tester);
    await tester.drag(handle(0), const Offset(80, 0));
    expect(_rootRatios(c)[0], closeTo(0.35, 0.01));
    expect(_rootRatios(c)[1], closeTo(0.4, 0.01));
    expect(_rootRatios(c)[2], 0.25);

    await tester.drag(handle(0), const Offset(-2000, 0));
    expect(_rootRatios(c)[0], closeTo(0.05, 1e-9));
    expect(_rootRatios(c).fold(0.0, (s, r) => s + r), 1.0);
  });

  testWidgets('updates within one frame do not stack on stale ratios', (
    tester,
  ) async {
    await pump(tester);
    final gesture = await tester.startGesture(tester.getCenter(handle(0)));
    await gesture.moveBy(const Offset(20, 0)); // past the drag slop
    await gesture.moveBy(const Offset(40, 0));
    await gesture.moveBy(const Offset(40, 0)); // no pump in between
    await gesture.up();
    await tester.pump();
    // 100px once, not each update over the last one's ratios, of the 792px
    // the windows share (808 less two 8px handles).
    expect(_rootRatios(c)[0], closeTo(0.25 + 100 / 792, 1e-9));
  });

  testWidgets('one drag is one undo step; the next drag is its own', (
    tester,
  ) async {
    await pump(tester);
    final start = c.doc.value;
    final gesture = await tester.startGesture(tester.getCenter(handle(0)));
    for (var i = 0; i < 4; i++) {
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
    }
    await gesture.up();
    final afterFirst = c.doc.value;
    await tester.drag(handle(0), const Offset(40, 0));
    undo.undo();
    expect(c.doc.value, afterFirst);
    undo.undo();
    expect(c.doc.value, start);
  });

  testWidgets('a handle on a nested branch resizes that branch', (
    tester,
  ) async {
    await pump(tester);
    await tester.drag(handle(1), const Offset(0, 120));
    expect(_innerRatios(c)[0], closeTo(0.7, 0.01));
    expect(_rootRatios(c), [0.25, 0.5, 0.25]);

    await tester.drag(handle(2), const Offset(-80, 0));
    expect(_rootRatios(c)[1], closeTo(0.4, 0.01));
    expect(_rootRatios(c)[2], closeTo(0.35, 0.01));
  });

  testWidgets('the cursor is the resize cursor for the axis', (tester) async {
    await pump(tester);
    MouseCursor cursor(int i) => tester
        .widget<MouseRegion>(
          find.descendant(of: handle(i), matching: find.byType(MouseRegion)),
        )
        .cursor;
    expect(cursor(0), SystemMouseCursors.resizeColumn);
    expect(cursor(1), SystemMouseCursors.resizeRow);
  });

  testWidgets('the splitter hook replaces the visual', (tester) async {
    await pump(
      tester,
      delegate: WindowingDelegate(
        splitter: (_, axis) => Text('split ${axis.name}'),
      ),
    );
    expect(find.text('split horizontal'), findsNWidgets(2));
    expect(find.text('split vertical'), findsOneWidget);
  });

  testWidgets('an app can place a handle in a custom arrangement', (
    tester,
  ) async {
    await pump(
      tester,
      delegate: WindowingDelegate(
        windowArrangement: WindowArrangement.custom(
          (context, _) => Row(
            children: [
              const Expanded(child: WindowHost(_a)),
              WindowResizeHandle(
                branch: c.doc.value.tabs[_tab]!.root! as WindowBranch,
                index: 1,
                extent: 808,
              ),
              const Expanded(child: WindowHost(_d)),
            ],
          ),
        ),
      ),
    );
    await tester.drag(find.byType(WindowResizeHandle), const Offset(80, 0));
    expect(_rootRatios(c)[0], closeTo(0.35, 0.01));
  });

  testWidgets('a wrapped handle measures the extent it is given', (
    tester,
  ) async {
    await pump(
      tester,
      delegate: WindowingDelegate(
        windowArrangement: WindowArrangement.custom(
          (context, _) => Row(
            children: [
              const Expanded(child: WindowHost(_a)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: WindowResizeHandle(
                  branch: c.doc.value.tabs[_tab]!.root! as WindowBranch,
                  index: 1,
                  extent: 808,
                ),
              ),
              const Expanded(child: WindowHost(_d)),
            ],
          ),
        ),
      ),
    );
    await tester.drag(find.byType(WindowResizeHandle), const Offset(80, 0));
    expect(_rootRatios(c)[0], closeTo(0.35, 0.005));
  });
}
