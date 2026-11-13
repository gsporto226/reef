import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reef/reef.dart';

void main() {
  late UndoController undo;
  late WindowingController c;

  setUp(() {
    undo = UndoController();
    c = WindowingController(undo: undo);
  });
  tearDown(() => c.dispose());

  ShellId shell() => c.doc.value.focusedShellId;

  test('without an UndoController, dispatch behaves as before', () {
    final plain = WindowingController();
    addTearDown(plain.dispose);
    final tab = plain.newTab();
    expect(plain.doc.value.tabs, contains(tab));
  });

  test('one entry per changing batch; undo and redo republish it', () {
    final initial = c.doc.value;
    c.dispatchAll([
      NewTab(shellId: shell(), tabId: TabId.generate()),
      NewTab(shellId: shell(), tabId: TabId.generate()),
    ]);
    final after = c.doc.value;
    expect(undo.$canUndo.value, isTrue);

    undo.undo();
    expect(c.doc.value, initial);
    expect(undo.$canUndo.value, isFalse);
    expect(undo.$canRedo.value, isTrue, reason: 'undo records nothing');

    undo.redo();
    expect(c.doc.value, after);
    expect(undo.$canRedo.value, isFalse);
  });

  test('entries carry a layout label', () {
    c.newTab();
    expect(undo.labels.single.localize(), 'Change layout');
  });

  test('a shell-set change keeps buffer entries on the timeline', () {
    final host = BufferUndoHost(undo);
    final vm = _Vm(host);
    c.newTab();
    vm.set('x');
    c.attachShell();
    undo.undo();
    expect(vm.model, '');
    expect(undo.$canUndo.value, isFalse, reason: 'layout entry dropped');
  });

  test('resizeWindow coalesces under its key until the run is sealed', () {
    final tab = c.newTab(buffer: const BufferId.manual('a'));
    final window = c.doc.value.tabs[tab]!.activeWindowId!;
    final split = c.splitWindow(window, axis: Axis.horizontal);
    final before = c.doc.value;
    c.resizeWindow(split, [0.4, 0.6], coalesceKey: (#resize, split));
    c.resizeWindow(split, [0.3, 0.7], coalesceKey: (#resize, split));
    undo.sealCoalescing();
    c.resizeWindow(split, [0.2, 0.8], coalesceKey: (#resize, split));
    undo
      ..undo()
      ..undo();
    expect(c.doc.value, before);
  });

  test('undo of a close keeps navigation done since in another tab '
      '(ADR 0009)', () {
    final first = c.newTab(buffer: const BufferId.manual('a'));
    final w1 = c.doc.value.tabs[first]!.activeWindowId!;
    c.pushBuffer(w1, const BufferId.manual('a2'));
    final second = c.newTab(buffer: const BufferId.manual('b'));
    final w2 = c.doc.value.tabs[second]!.activeWindowId!;
    final history = c.doc.value.windows[w1]!.history;

    c.closeTab(first);
    c.pushBuffer(w2, const BufferId.manual('b2'));
    undo.undo();

    final doc = c.doc.value;
    expect(doc.windows[w1]!.history, history);
    expect(doc.shells[shell()]!.tabIds, contains(first));
    expect(doc.windows[w2]!.history.current.buffer,
        const BufferId.manual('b2'));
    expect(doc.isValid, isTrue);
  });

  test('unchanged batches record nothing', () {
    c.dispatch(CloseTab(TabId.manual('unknown')));
    expect(undo.$canUndo.value, isFalse);
  });

  test('focus-only batches update the doc without recording', () {
    final first = c.doc.value.shells[shell()]!.activeTabId;
    final second = c.newTab(buffer: const BufferId.manual('a'));
    final window = c.doc.value.tabs[second]!.activeWindowId!;
    c.splitWindow(window, axis: Axis.horizontal);
    undo.clearHost<WindowingDoc>();

    c.activateTab(first);
    c.activateWindow(window);
    expect(c.doc.value.tabs[second]!.activeWindowId, window);
    expect(undo.$canUndo.value, isFalse);
  });

  test('shell focus alone records nothing', () {
    final other = c.attachShell();
    final first = c.doc.value.shells.keys.first;
    c.newTab(shellId: other);
    undo.clearHost<WindowingDoc>();
    c.activateShell(first);
    expect(c.doc.value.focusedShellId, first);
    expect(undo.$canUndo.value, isFalse);
  });

  test('a batch changing the shell set clears the timeline', () {
    c.newTab();
    expect(undo.$canUndo.value, isTrue);
    final other = c.attachShell();
    expect(undo.$canUndo.value, isFalse);
    c.newTab();
    c.closeShell(other);
    expect(undo.$canUndo.value, isFalse);
  });

  test('coalesceKey merges consecutive batches into one entry', () {
    final tab = c.newTab(buffer: const BufferId.manual('a'));
    final window = c.doc.value.tabs[tab]!.activeWindowId!;
    final split = c.splitWindow(window, axis: Axis.horizontal);
    final before = c.doc.value;
    c.dispatchAll([ResizeWindow(split, [0.4, 0.6])], coalesceKey: 'drag');
    c.dispatchAll([ResizeWindow(split, [0.3, 0.7])], coalesceKey: 'drag');
    undo.undo();
    expect(c.doc.value, before);
  });

  testWidgets('undo and redo each rebuild a listener once', (tester) async {
    c.newTab();
    var builds = 0;
    await tester.pumpWidget(ValueListenableBuilder<WindowingDoc>(
      valueListenable: c.doc,
      builder: (_, _, _) {
        builds++;
        return const SizedBox();
      },
    ));
    undo.undo();
    await tester.pump();
    expect(builds, 2);
    undo.redo();
    await tester.pump();
    expect(builds, 3);
  });
}

class _Vm extends ViewModel<String> with UndoableModel<String> {
  _Vm(BufferUndoHost host) : super('') {
    attachUndo(host, const BufferId.manual('b'));
  }

  void set(String v) => publish(v);
}
