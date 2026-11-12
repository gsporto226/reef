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

final links = LinkTable({
  'tasks': '/tasks',
  'task-edit': '/tasks/:taskId/edit',
  'task-draft': '/tasks/new',
  'pair': '/a/:x/b/:y',
}, drafts: {'task-draft'});

BufferPath path(String uri) => BufferPath.fromUri(Uri.parse(uri));

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
  group('BufferPath', () {
    test('parses segments and query arguments from a URI', () {
      final p = path('/tasks/42/edit?mode=full');
      expect(p.segments, ['tasks', '42', 'edit']);
      expect(p.arguments, {'mode': 'full'});
    });

    test('prints back to the URI, escaping what needs it', () {
      expect(path('/tasks/42/edit?mode=full').toString(),
          '/tasks/42/edit?mode=full');
      expect(const BufferPath(['a b', 'c/d']).toString(), '/a%20b/c%2Fd');
      expect(const BufferPath([]).toString(), '/');
    });

    test('is a value', () {
      expect(path('/tasks?a=1'), path('/tasks/?a=1'));
      expect(path('/tasks?a=1').hashCode, path('/tasks/?a=1').hashCode);
      expect(path('/tasks?a=1'), isNot(path('/tasks?a=2')));
    });
  });

  group('LinkTable', () {
    test('template parameters form the token; query becomes arguments', () {
      final link = links.resolve(path('/tasks/42/edit?mode=full'))!;
      expect(link.buffer, edit42);
      expect(link.arguments, {'mode': 'full'});
      expect(links.resolve(path('/a/1/b/2'))!.buffer,
          const BufferId.manual('pair:1/2'));
    });

    test('a buffer prints to its path, with arguments as the query', () {
      expect(links.pathOf(edit42), path('/tasks/42/edit'));
      expect(links.pathOf(edit42, {'mode': 'full'}),
          path('/tasks/42/edit?mode=full'));
      expect(links.pathOf(const BufferId.manual('pair:1/2')),
          path('/a/1/b/2'));
    });

    test('a template without parameters gives a fresh draft each time', () {
      final a = links.resolve(path('/tasks/new'))!.buffer;
      final b = links.resolve(path('/tasks/new'))!.buffer;
      expect(a.id, startsWith('task-draft:'));
      expect(a, isNot(b));
      expect(links.pathOf(a), path('/tasks/new'));
    });

    test('a template without parameters is one stable buffer by default', () {
      expect(links.resolve(path('/tasks'))!.buffer, list);
      expect(links.resolve(path('/tasks'))!.buffer, list);
      expect(links.pathOf(list), path('/tasks'));
    });

    test('pathOf inverts resolve for tokens with reserved characters', () {
      for (final uri in ['/a/x%2Fy/b/%3F%23%25', '/tasks/a%20b%3Ac/edit']) {
        final buffer = links.resolve(path(uri))!.buffer;
        expect(links.pathOf(buffer), path(uri));
        expect(links.pathOf(buffer).toString(), uri);
      }
      expect(links.resolve(path('/a/x%2Fy/b/a%20b'))!.buffer,
          const BufferId.manual('pair:x%2Fy/a b'));
    });

    test('an unmatched path resolves to nothing', () {
      expect(links.resolve(path('/nope')), isNull);
      expect(links.resolve(path('/tasks/42')), isNull);
      expect(const LinkTable({}).resolve(path('/tasks')), isNull);
    });

    test('a buffer without a matching template has no path', () {
      expect(links.pathOf(const BufferId.manual('other:1')), isNull);
      expect(links.pathOf(const BufferId.manual('no-kind')), isNull);
      expect(links.pathOf(const BufferId.manual('pair:1')), isNull);
    });
  });

  group('openLink', () {
    late List<List<WindowingCommand>> batches;

    WindowingController controller(WindowingDoc? initial,
        {ShellPlatform? platform}) {
      final c = WindowingController(
        initial: () => initial,
        links: links,
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

    test('an unmatched path returns false and changes nothing', () async {
      final c = controller(twoShells());
      final before = c.doc.value;
      expect(await c.openLink(path('/nope')), isFalse);
      expect(c.doc.value, same(before));
    });

    test('a shown buffer is focused, the focused shell first', () async {
      final c = controller(twoShells());
      expect(await c.openLink(path('/tasks/42/edit')), isTrue);
      expect(c.doc.value.focusedShellId, s1);
      expect(active(c.doc.value), w2);
    });

    test('a buffer shown only in another shell focuses that shell', () async {
      final c = controller(twoShells(s2Shows: edit43));
      expect(await c.openLink(path('/tasks/43/edit')), isTrue);
      expect(c.doc.value.focusedShellId, s2);
      expect(active(c.doc.value), w3);
    });

    test("a buffer shown in a floating window focuses that window's shell",
        () async {
      final floated = const FloatWindow(w3, scope: TabScope(t2))
          .apply(twoShells(s2Shows: edit43));
      final c = controller(floated);
      expect(await c.openLink(path('/tasks/43/edit')), isTrue);
      final d = c.doc.value;
      expect(d.focusedShellId, s2);
      expect(d.floating.keys, [w3]);
      expect(d.windows.length, 3, reason: 'no new window opened');
    });

        test('a buffer not shown opens through the open policy, in one batch',
        () async {
      final c = controller(twoShells())..openPolicy = newTabOpenPolicy;
      expect(await c.openLink(path('/tasks/43/edit')), isTrue);
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
      await c.openLink(path('/tasks/42/edit?mode=full'));
      expect(seen!.$1, edit42);
      expect(seen!.$2, {'mode': 'full'});
      expect(c.doc.value.focusedShellId, s2);
    });

    test('arguments live in each history entry; back and forward restore '
        'them', () async {
      final c = controller(twoShells())
        ..openPolicy = pushOpenPolicy
        ..linkPolicy = (_, _, _) => null;
      await c.openLink(path('/tasks/43/edit?mode=a'));
      await c.openLink(path('/tasks/43/edit?mode=b'));
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
      await c.openLink(path('/tasks/42/edit?mode=full'));
      expect(active(c.doc.value), w2);
      expect(c.doc.value.windowsShowing(edit42), [w2, w3]);
    });

    test('on a fresh doc it builds shell, tab and window', () async {
      final c = controller(null);
      expect(await c.openLink(path('/tasks/42/edit')), isTrue);
      final d = c.doc.value;
      expect(d.shells, hasLength(1));
      expect(d.windows.values.single.history.current.buffer, edit42);
    });

    test('newShell with pop-out support opens a shell showing the buffer',
        () async {
      final platform = FakeShellPlatform();
      final c = controller(twoShells(), platform: platform);
      expect(await c.openLink(path('/tasks/42/edit'), newShell: true), isTrue);
      final d = c.doc.value;
      expect(platform.opened, [d.focusedShellId]);
      expect(d.windows[active(d)]!.history.current.buffer, edit42);
      expect(d.shells, hasLength(3));
    });

    test('newShell without support goes through the link policy', () async {
      final c = controller(twoShells(),
          platform: FakeShellPlatform(isSupported: false));
      expect(await c.openLink(path('/tasks/43/edit'), newShell: true), isTrue);
      final d = c.doc.value;
      expect(d.shells, hasLength(2));
      expect(d.windows[w1]!.history.current.buffer, edit43);
    });

    test('newShell whose shell fails to open falls back too', () async {
      final platform = FakeShellPlatform()
        ..failNextOpen(const ShellError(ShellErrorKind.unsupported));
      final c = controller(twoShells(), platform: platform);
      expect(await c.openLink(path('/tasks/42/edit'), newShell: true), isTrue);
      expect(c.doc.value.shells, hasLength(2));
      expect(active(c.doc.value), w2);
    });
  });
}
