import 'package:flutter/painting.dart' show Axis;
import 'package:flutter_test/flutter_test.dart';
import 'package:reef/reef.dart';

void main() {
  late FakeShellPlatform platform;
  late WindowingController c;

  setUp(() {
    platform = FakeShellPlatform();
    c = WindowingController(platform: platform);
  });
  tearDown(() => c.dispose());

  group('capabilities.canPopOut', () {
    test('false with no platform', () {
      final bare = WindowingController();
      expect(bare.capabilities.canPopOut, isFalse);
      bare.dispose();
    });

    test('false with an unsupported platform', () {
      platform.isSupported = false;
      expect(c.capabilities.canPopOut, isFalse);
    });

    test('true with a supported platform', () {
      expect(c.capabilities.canPopOut, isTrue);
    });
  });

  group('openShell', () {
    test('returns the new shell, with one empty tab, focused', () async {
      final result = await c.openShell();
      final id = result.getOrNull()!;
      final doc = c.doc.value;
      expect(doc.focusedShellId, id);
      final shell = doc.shells[id]!;
      expect(shell.tabIds, hasLength(1));
      expect(shell.activeTabId, shell.tabIds.single);
      expect(doc.tabs[shell.tabIds.single], const TabState());
      expect(platform.opened, [id]);
    });

    test(
      'with a buffer, the one tab shows it and there is no placeholder',
      () async {
        final buffer = BufferId.manual('page-1');
        final id = (await c.openShell(buffer: buffer)).getOrNull()!;
        final doc = c.doc.value;
        final tab = doc.tabs[doc.shells[id]!.tabIds.single]!;
        expect(doc.windows[tab.activeWindowId]!.history.current, buffer);
        expect(tab.root, WindowLeaf(tab.activeWindowId!));
      },
    );

    test(
      'opens the platform before the doc changes, and publishes once',
      () async {
        final seen = <List<ShellId>>[];
        c.doc.addListener(() => seen.add([...platform.opened]));
        final id = (await c.openShell()).getOrNull()!;
        expect(seen, [
          [id],
        ]);
      },
    );

    test('a failed open returns the failure and leaves the doc', () async {
      final before = c.doc.value;
      const failure = ShellError(ShellErrorKind.platformFailure, cause: 'boom');
      platform.failNextOpen(failure);
      final result = await c.openShell();
      expect(result.getErrOrNull(), failure);
      expect(c.doc.value, same(before));
      // Only the next open fails.
      expect((await c.openShell()).isOk, isTrue);
    });

    test('no platform returns unsupported', () async {
      final bare = WindowingController();
      final result = await bare.openShell();
      expect(result.getErrOrNull()!.kind, ShellErrorKind.unsupported);
      bare.dispose();
    });

    test(
      'an unsupported platform returns unsupported and never opens',
      () async {
        platform.isSupported = false;
        final before = c.doc.value;
        final result = await c.openShell();
        expect(
          result.getErrOrNull(),
          const ShellError(ShellErrorKind.unsupported),
        );
        expect(platform.opened, isEmpty);
        expect(c.doc.value, same(before));
      },
    );

    test(
      'a vetoed attach closes the opened shell and returns refused',
      () async {
        c.interceptor = (doc, command) => command is AttachShell
            ? const CommandDecision.veto(UndoLabel('No'))
            : const CommandDecision.approve();
        final before = c.doc.value;
        final result = await c.openShell(buffer: BufferId.manual('page'));
        expect(result.getErrOrNull()!.kind, ShellErrorKind.refused);
        expect(platform.closed, platform.opened);
        expect(platform.opened, hasLength(1));
        expect(c.doc.value, same(before));
      },
    );
  });

  group('popOutTab', () {
    // A source shell with tabs [a, b, third], b active and holding a split,
    // a floating window and a history.
    late ShellId source;
    late TabId a, b, third;
    late WindowId w1, w2;

    setUp(() {
      source = c.doc.value.focusedShellId;
      a = c.doc.value.shells[source]!.tabIds.single;
      b = c.newTab(buffer: BufferId.manual('one'));
      w1 = c.doc.value.tabs[b]!.activeWindowId!;
      c.pushBuffer(w1, BufferId.manual('two'));
      w2 = c.splitWindow(w1, axis: Axis.horizontal);
      c.resizeWindow(w1, [0.3, 0.7]);
      final w3 = c.splitWindow(w2, axis: Axis.vertical);
      c.floatWindow(w3, scope: TabScope(b));
      third = c.newTab();
      c.activateTab(b);
    });

    test("moves the tab, intact, as the new shell's only tab", () async {
      final tabBefore = c.doc.value.tabs[b]!;
      final windowsBefore = {...c.doc.value.windows};
      final id = (await c.popOutTab(b)).getOrNull()!;
      final doc = c.doc.value;
      expect(doc.shells[id]!.tabIds, [b]);
      expect(doc.shells[id]!.activeTabId, b);
      expect(doc.tabs[b], tabBefore);
      expect(doc.windows, windowsBefore);
      expect(doc.focusedShellId, id);
      expect(platform.opened, [id]);
    });

    test('the source shell activates a neighbour tab', () async {
      await c.popOutTab(b);
      final shell = c.doc.value.shells[source]!;
      expect(shell.tabIds, [a, third]);
      expect(shell.activeTabId, a);
    });

    test('publishes once and clears the undo timeline', () async {
      final undo = UndoController();
      final u = WindowingController(undo: undo, platform: platform);
      final t = u.newTab(buffer: BufferId.manual('x'));
      expect(undo.$canUndo.value, isTrue);
      var publishes = 0;
      u.doc.addListener(() => publishes++);
      await u.popOutTab(t);
      expect(publishes, 1);
      expect(undo.$canUndo.value, isFalse);
      u.dispose();
    });

    test("a shell's last tab is refused without the platform", () async {
      final only = (await c.openShell()).getOrNull()!;
      platform.opened.clear();
      final before = c.doc.value;
      final result =
          await c.popOutTab(c.doc.value.shells[only]!.tabIds.single);
      expect(result.getErrOrNull(), const ShellError(ShellErrorKind.refused));
      expect(platform.opened, isEmpty);
      expect(c.doc.value, same(before));
    });

    test('an unknown tab is refused without the platform', () async {
      final before = c.doc.value;
      final result = await c.popOutTab(TabId.generate());
      expect(result.getErrOrNull()!.kind, ShellErrorKind.refused);
      expect(platform.opened, isEmpty);
      expect(c.doc.value, same(before));
    });

    test('an unsupported platform returns unsupported', () async {
      platform.isSupported = false;
      final result = await c.popOutTab(b);
      expect(result.getErrOrNull()!.kind, ShellErrorKind.unsupported);
      expect(platform.opened, isEmpty);
    });

    test('a failed open leaves the doc the same instance', () async {
      const failure = ShellError(ShellErrorKind.platformFailure);
      platform.failNextOpen(failure);
      final before = c.doc.value;
      expect((await c.popOutTab(b)).getErrOrNull(), failure);
      expect(c.doc.value, same(before));
    });

    test('a veto closes the opened shell and returns refused', () async {
      c.interceptor = (doc, command) => command is AttachShell
          ? const CommandDecision.veto(UndoLabel('No'))
          : const CommandDecision.approve();
      final before = c.doc.value;
      final result = await c.popOutTab(b);
      expect(result.getErrOrNull()!.kind, ShellErrorKind.refused);
      expect(platform.opened, hasLength(1));
      expect(platform.closed, platform.opened);
      expect(c.doc.value, same(before));
    });
  });

  test('FakeShellPlatform records closes', () {
    final id = ShellId.generate();
    platform.close(id);
    expect(platform.closed, [id]);
  });

  test('ShellError equality and toString', () {
    const a = ShellError(ShellErrorKind.refused, cause: 1);
    expect(a, const ShellError(ShellErrorKind.refused, cause: 1));
    expect(
      a.hashCode,
      const ShellError(ShellErrorKind.refused, cause: 1).hashCode,
    );
    expect(a == const ShellError(ShellErrorKind.refused), isFalse);
    expect(a.toString(), contains('refused'));
  });
}
