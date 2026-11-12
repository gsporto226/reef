import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reef/reef.dart';

const s1 = ShellId.manual('s1');
const s2 = ShellId.manual('s2');
const t1 = TabId.manual('t1');
const t2 = TabId.manual('t2');
const w1 = WindowId.manual('w1');
const w2 = WindowId.manual('w2');
const w3 = WindowId.manual('w3');
const list = BufferId.manual('tasks:');
const edit42 = BufferId.manual('task-edit:42');
const edit43 = BufferId.manual('task-edit:43');

WindowState showing(BufferId buffer) =>
    WindowState(history: BufferHistory(current: HistoryEntry(buffer)));

/// s1 (focused) holds t1: w1 (list) beside w2 (42), w1 active. s2 holds t2:
/// w3 (42 or [s2Shows]).
WindowingDoc twoShells({BufferId s2Shows = edit42}) => WindowingDoc(
  shells: {
    s1: ShellState(tabIds: [t1], activeTabId: t1),
    s2: ShellState(tabIds: [t2], activeTabId: t2),
  },
  tabs: {
    t1: TabState(
      root: WindowBranch(
        axis: Axis.horizontal,
        children: [WindowLeaf(w1), WindowLeaf(w2)],
        ratios: [0.5, 0.5],
      ),
      activeWindowId: w1,
    ),
    t2: TabState(root: WindowLeaf(w3), activeWindowId: w3),
  },
  windows: {w1: showing(list), w2: showing(edit42), w3: showing(s2Shows)},
  focusedShellId: s1,
);

void main() {
  group('openLink', () {
    late List<List<WindowingCommand>> batches;

    WindowingController controller(WindowingDoc? initial,
        {ShellPlatform? platform}) {
      final c = WindowingController(
        initial: () => initial,
        platform: platform,
        interceptor: (_, command) => const CommandDecision.approve(),
      );
      c.doc.addListener(() => batches.add(const []));
      addTearDown(c.dispose);
      return c;
    }

    setUp(() => batches = []);

    WindowId active(WindowingDoc d) =>
        d.tabs[d.shells[d.focusedShellId]!.activeTabId]!.activeWindowId!;

    test('a shown buffer is focused, the focused shell first', () async {
      final c = controller(twoShells());
      await c.openLink(edit42);
      expect(c.doc.value.focusedShellId, s1);
      expect(active(c.doc.value), w2);
    });

    test('a buffer shown only in another shell focuses that shell', () async {
      final c = controller(twoShells(s2Shows: edit43));
      await c.openLink(edit43);
      expect(c.doc.value.focusedShellId, s2);
      expect(active(c.doc.value), w3);
    });

    test("a buffer shown in a floating window focuses that window's shell",
        () async {
      final floated = const FloatWindow(w3, scope: TabScope(t2))
          .apply(twoShells(s2Shows: edit43));
      final c = controller(floated);
      await c.openLink(edit43);
      final d = c.doc.value;
      expect(d.focusedShellId, s2);
      expect(d.floating.keys, [w3]);
      expect(d.windows.length, 3, reason: 'no new window opened');
    });

        test('a buffer not shown opens through the open policy, in one batch',
        () async {
      final c = controller(twoShells())..openPolicy = newTabOpenPolicy;
      await c.openLink(edit43);
      expect(batches, hasLength(1));
      final d = c.doc.value;
      expect(d.shells[s1]!.tabIds, hasLength(2));
      expect(d.windows[active(d)]!.history.current.buffer, edit43);
    });

    test('the link policy gets the buffer and the arguments', () async {
      final c = controller(twoShells());
      (BufferId, Map<String, String>)? seen;
      c.linkPolicy = (doc, buffer, arguments) {
        seen = (buffer, arguments);
        return [ActivateShell(s2)];
      };
      await c.openLink(edit42, arguments: {'mode': 'full'});
      expect(seen!.$1, edit42);
      expect(seen!.$2, {'mode': 'full'});
      expect(c.doc.value.focusedShellId, s2);
    });

    test('arguments live in each history entry; back and forward restore '
        'them', () async {
      final c = controller(twoShells())
        ..openPolicy = pushOpenPolicy
        ..linkPolicy = (_, _, _) => null;
      await c.openLink(edit43, arguments: {'mode': 'a'});
      await c.openLink(edit43, arguments: {'mode': 'b'});
      HistoryEntry current() => c.doc.value.windows[w1]!.history.current;
      expect(current().buffer, edit43);
      expect(current().arguments, {'mode': 'b'});
      c.popBuffer(w1);
      expect(current().arguments, {'mode': 'a'});
      c.navigateForward(w1);
      expect(current().arguments, {'mode': 'b'});
    });

    test('matching an open window compares the buffer, not its arguments',
        () async {
      final c = controller(twoShells());
      await c.openLink(edit42, arguments: {'mode': 'full'});
      expect(active(c.doc.value), w2);
      expect(c.doc.value.windowsShowing(edit42), [w2, w3]);
    });

    test('on a fresh doc it builds shell, tab and window', () async {
      final c = controller(null);
      await c.openLink(edit42);
      final d = c.doc.value;
      expect(d.shells, hasLength(1));
      expect(d.windows.values.single.history.current.buffer, edit42);
    });

    test('newShell with pop-out support opens a shell showing the buffer',
        () async {
      final platform = FakeShellPlatform();
      final c = controller(twoShells(), platform: platform);
      await c.openLink(edit42, newShell: true);
      final d = c.doc.value;
      expect(platform.opened, [d.focusedShellId]);
      expect(d.windows[active(d)]!.history.current.buffer, edit42);
      expect(d.shells, hasLength(3));
    });

    test('newShell without support goes through the link policy', () async {
      final c = controller(twoShells(),
          platform: FakeShellPlatform(isSupported: false));
      await c.openLink(edit43, newShell: true);
      final d = c.doc.value;
      expect(d.shells, hasLength(2));
      expect(d.windows[w1]!.history.current.buffer, edit43);
    });

    test('newShell whose shell fails to open falls back too', () async {
      final platform = FakeShellPlatform()
        ..failNextOpen(const ShellError(ShellErrorKind.unsupported));
      final c = controller(twoShells(), platform: platform);
      await c.openLink(edit42, newShell: true);
      expect(c.doc.value.shells, hasLength(2));
      expect(active(c.doc.value), w2);
    });
  });
}
