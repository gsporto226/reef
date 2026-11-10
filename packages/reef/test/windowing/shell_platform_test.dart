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
