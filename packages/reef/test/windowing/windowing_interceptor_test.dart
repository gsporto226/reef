import 'package:flutter_test/flutter_test.dart';
import 'package:reef/reef.dart';

void main() {
  const reason = UndoLabel('No more tabs');

  late UndoController undo;
  late List<WindowingCommand> seen;
  late WindowingController c;

  /// Vetoes every [NewTab] once the focused shell already holds two tabs.
  CommandDecision maxTwoTabs(WindowingDoc doc, WindowingCommand command) {
    seen.add(command);
    final shell = doc.shells[doc.focusedShellId]!;
    return command is NewTab && shell.tabIds.length >= 2
        ? const CommandDecision.veto(reason)
        : const CommandDecision.approve();
  }

  setUp(() {
    undo = UndoController();
    seen = [];
    c = WindowingController(undo: undo, interceptor: maxTwoTabs);
  });
  tearDown(() => c.dispose());

  ShellId shell() => c.doc.value.focusedShellId;
  NewTab newTab() => NewTab(shellId: shell(), tabId: TabId.generate());
  int tabCount() => c.doc.value.shells[shell()]!.tabIds.length;

  test('approve applies the command', () {
    c.dispatch(newTab());
    expect(tabCount(), 2);
    expect(c.vetoes.value, isNull);
  });

  test('a vetoed dispatch keeps the doc instance, records no undo entry and '
      'publishes the veto', () {
    c.dispatch(newTab());
    undo.clearHost<WindowingDoc>();
    final before = c.doc.value;
    final vetoed = newTab();
    c.dispatch(vetoed);
    expect(c.doc.value, same(before));
    expect(undo.$canUndo.value, isFalse);
    expect(c.vetoes.value!.command, same(vetoed));
    expect(c.vetoes.value!.reason, reason);
  });

  test('in a batch, each command sees the doc folded so far; a veto skips '
      'only that command; one publish and one undo entry', () {
    var publishes = 0;
    c.doc.addListener(() => publishes++);
    final tab = TabId.generate();
    c.dispatchAll([newTab(), newTab(), CloseTab(tab), newTab()]);
    expect(seen.length, 4);
    expect(tabCount(), 2, reason: 'second and fourth NewTab vetoed');
    expect(publishes, 1);
    expect(undo.labels.length, 1);
  });

  test('a replacement is applied and not intercepted again', () {
    final closing = TabId.generate();
    c.dispatch(NewTab(shellId: shell(), tabId: closing));
    seen.clear();
    final replacing = WindowingController(
      initial: () => c.doc.value,
      interceptor: (doc, command) {
        seen.add(command);
        return command is NewTab
            ? CommandDecision.replace(CloseTab(closing))
            : const CommandDecision.approve();
      },
    );
    addTearDown(replacing.dispose);
    replacing.dispatch(newTab());
    expect(seen.length, 1);
    expect(replacing.doc.value.tabs, isNot(contains(closing)));
  });

  test('undo and redo bypass the interceptor', () {
    c.dispatch(newTab());
    final after = c.doc.value;
    seen.clear();
    undo.undo();
    undo.redo();
    expect(c.doc.value, after);
    expect(seen, isEmpty);
  });

  test('the interceptor can be swapped and removed', () {
    c.interceptor = null;
    c.dispatchAll([newTab(), newTab(), newTab()]);
    expect(tabCount(), 4);
    expect(seen, isEmpty);
  });

  test('a vetoes listener reads the post-batch doc', () {
    final seenTabs = <int>[];
    c.vetoes.addListener(() => seenTabs.add(tabCount()));
    c.dispatchAll([newTab(), newTab()]);
    expect(seenTabs, [2]);
  });
}
