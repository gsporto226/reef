import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reef/reef.dart';

const _a = BufferId.manual('A');
const _b = BufferId.manual('B');

void main() {
  late UndoController undo;
  late WindowingController c;

  setUp(() {
    undo = UndoController();
    c = WindowingController(undo: undo);
  });
  tearDown(() => c.dispose());

  TabState tab() {
    final doc = c.doc.value;
    return doc.tabs[doc.shells[doc.focusedShellId]!.activeTabId]!;
  }

  WindowId active() => tab().activeWindowId!;

  Future<void> pump(WidgetTester tester,
      {Map<ShortcutActivator, Intent>? bindings, Widget? child}) {
    return tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: WindowingRoot(
        controller: c,
        bufferBuilder: (_, buffer) => Text(buffer.value),
        child: WindowingShortcuts(
          undo: undo,
          bindings: bindings ?? WindowingShortcuts.defaultBindings,
          child: child ?? const SizedBox.expand(),
        ),
      ),
    ));
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key,
      {bool shift = false, bool alt = false}) async {
    final primary = WindowingShortcuts.primaryModifier;
    await tester.sendKeyDownEvent(primary);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    if (alt) await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(key);
    if (alt) await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(primary);
    await tester.pump();
  }

  Future<void> alt(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
  }

  testWidgets('split along each axis and close act on the active window',
      (tester) async {
    c.newTab(buffer: _a);
    await pump(tester);
    final first = active();

    await press(tester, LogicalKeyboardKey.backslash);
    expect((tab().root! as WindowBranch).axis, Axis.horizontal);
    final second = active();
    expect(second, isNot(first));

    await press(tester, LogicalKeyboardKey.backslash, shift: true);
    expect(tab().root!.windowIds, hasLength(3));
    final third = active();

    await press(tester, LogicalKeyboardKey.keyW);
    expect(tab().root!.windowIds, [first, second]);
    expect(c.doc.value.windows, isNot(contains(third)));
  });

  testWidgets('back and forward walk the active window history',
      (tester) async {
    c.newTab(buffer: _a);
    c.pushBuffer(active(), _b);
    await pump(tester);
    BufferId current() => c.doc.value.windows[active()]!.history.current;

    await alt(tester, LogicalKeyboardKey.arrowLeft);
    expect(current(), _a);
    await alt(tester, LogicalKeyboardKey.arrowRight);
    expect(current(), _b);
  });

  testWidgets('with no active window the commands do nothing',
      (tester) async {
    await pump(tester); // the fresh doc's tab is empty
    final before = c.doc.value;
    await press(tester, LogicalKeyboardKey.backslash);
    await press(tester, LogicalKeyboardKey.keyW);
    await alt(tester, LogicalKeyboardKey.arrowLeft);
    expect(c.doc.value, same(before));
  });

  testWidgets('undo and redo go to the UndoController when it can',
      (tester) async {
    c.newTab(buffer: _a);
    await pump(tester);
    await press(tester, LogicalKeyboardKey.backslash);
    final split = c.doc.value;

    await press(tester, LogicalKeyboardKey.keyZ);
    expect(tab().root, isA<WindowLeaf>());
    await press(tester, LogicalKeyboardKey.keyZ, shift: true);
    expect(c.doc.value, split);
    await press(tester, LogicalKeyboardKey.keyY);
    expect(c.doc.value, split, reason: 'nothing left to redo');
  });

  testWidgets('undo is disabled while the controller cannot undo',
      (tester) async {
    await pump(tester);
    expect(undo.$canUndo.value, isFalse);
    await press(tester, LogicalKeyboardKey.keyZ);
    expect(undo.$canUndo.value, isFalse);
  });

  testWidgets('a focused text field keeps its own undo keys', (tester) async {
    c.newTab(buffer: _a);
    final text = TextEditingController();
    final focus = FocusNode();
    addTearDown(text.dispose);
    addTearDown(focus.dispose);
    await pump(tester,
        child: EditableText(
          controller: text,
          focusNode: focus,
          style: const TextStyle(),
          cursorColor: const Color(0xFF000000),
          backgroundCursorColor: const Color(0xFF000000),
          autofocus: true,
        ));
    c.splitWindow(active(), axis: Axis.vertical); // one layout undo entry
    await tester.pump();
    final split = c.doc.value;

    for (final value in ['h', 'hi']) {
      await tester.enterText(find.byType(EditableText), value);
      await tester.pump(const Duration(milliseconds: 600));
    }
    await press(tester, LogicalKeyboardKey.keyZ);
    expect(c.doc.value, split);
    expect(text.text, 'h');
  });

  testWidgets('apps can replace or extend the bindings', (tester) async {
    c.newTab(buffer: _a);
    await pump(tester, bindings: {
      ...WindowingShortcuts.defaultBindings,
      const SingleActivator(LogicalKeyboardKey.keyQ): const CloseWindowIntent(),
    });
    await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
    await tester.pump();
    expect(tab().root, isNull);
  });
}
