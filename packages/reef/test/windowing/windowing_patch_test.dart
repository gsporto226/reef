import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Axis, Rect;
import 'package:flutter_test/flutter_test.dart';
import 'package:reef/reef.dart';

const _a = BufferId.manual('a');
const _b = BufferId.manual('b');

WindowState _w(BufferId buffer, [List<BufferId> back = const []]) =>
    WindowState(
      history: BufferHistory(
        current: HistoryEntry(buffer),
        back: [for (final b in back) HistoryEntry(b)],
      ),
    );

UndoEntry<WindowingDoc> _entry(WindowingDoc before, WindowingDoc after) =>
    UndoEntry(
      label: const UndoLabel('t'),
      snapshotBefore: before,
      snapshotAfter: after,
    );

void main() {
  final s1 = ShellId.manual('s1'), s2 = ShellId.manual('s2');
  final t1 = TabId.manual('t1'), t2 = TabId.manual('t2');
  final w1 = WindowId.manual('w1'), w2 = WindowId.manual('w2');
  final w3 = WindowId.manual('w3'), f = WindowId.manual('f');

  // s1 holds t1 (w1, with history) and t2 (w2 | w3); f floats in t2.
  final base = WindowingDoc(
    shells: {
      s1: ShellState(tabIds: [t1, t2], activeTabId: t1),
    },
    tabs: {
      t1: TabState(root: WindowLeaf(w1), activeWindowId: w1),
      t2: TabState(
        root: WindowBranch(
          axis: Axis.horizontal,
          children: [WindowLeaf(w2), WindowLeaf(w3)],
          ratios: const [0.5, 0.5],
        ),
        activeWindowId: w2,
      ),
    },
    windows: {
      w1: _w(_a, [_b]),
      w2: _w(_a),
      w3: _w(_b),
      f: _w(_a),
    },
    floating: {f: FloatingState(scope: TabScope(t2), zIndex: 0)},
    focusedShellId: s1,
  );
  // Closing t1: the tab and its window go, t2 becomes active.
  final closed = base.copyWith(
    shells: {
      s1: ShellState(tabIds: [t2], activeTabId: t2),
    },
    tabs: {t2: base.tabs[t2]!},
    windows: {...base.windows}..remove(w1),
  );
  WindowingDoc navigated(WindowingDoc doc, WindowId w) => doc.copyWith(
    windows: {
      ...doc.windows,
      w: _w(_b, [_a, _a]),
    },
  );

  test('the docs are valid', () {
    expect(base.isValid, isTrue);
    expect(closed.isValid, isTrue);
  });

  test('diff then apply turns before into after, reversed back', () {
    final p = WindowingPatch.diff(base, closed);
    expect(p.apply(base), closed);
    expect(p.reversed.apply(closed), base);
  });

  test('an empty patch changes nothing', () {
    expect(WindowingPatch.diff(base, base).apply(closed), closed);
  });

  test('undo of a close restores the tab with its history and keeps '
      'navigation done since in other windows', () {
    final now = navigated(closed, w2);
    final undone = WindowingPatch.diff(base, closed).reversed.apply(now)!;
    expect(undone.windows[w1], base.windows[w1]);
    expect(undone.shells[s1], base.shells[s1]);
    expect(undone.windows[w2], now.windows[w2]);
    expect(undone.isValid, isTrue);
  });

  test('redo applies the forward patch, keeping later navigation', () {
    final now = navigated(base, w2);
    final redone = WindowingPatch.diff(base, closed).apply(now)!;
    expect(redone.tabs.containsKey(t1), isFalse);
    expect(redone.windows[w2], now.windows[w2]);
  });

  test('floating entries and focus are units', () {
    final moved = base.copyWith(
      floating: {
        f: base.floating[f]!.copyWith(
          geometry: const Rect.fromLTWH(1, 2, 3, 4),
        ),
      },
    );
    final now = navigated(moved, w3);
    final undone = WindowingPatch.diff(base, moved).reversed.apply(now)!;
    expect(undone.floating, base.floating);
    expect(undone.windows[w3], now.windows[w3]);
  });

  test('a touched focused shell comes back', () {
    final two = base.copyWith(
      shells: {
        ...base.shells,
        s2: ShellState(tabIds: [t1], activeTabId: t1),
        s1: ShellState(tabIds: [t2], activeTabId: t2),
      },
    );
    final focused = two.copyWith(focusedShellId: s2);
    expect(focused.isValid, isTrue);
    final p = WindowingPatch.diff(two, focused);
    expect(p.reversed.apply(focused)!.focusedShellId, s1);
  });

  group('conflict', () {
    test('a shell removed since: apply yields null', () {
      final t3 = TabId.manual('t3'), w4 = WindowId.manual('w4');
      final two = base.copyWith(
        shells: {
          ...base.shells,
          s2: ShellState(tabIds: [t3], activeTabId: t3),
        },
        tabs: {
          ...base.tabs,
          t3: TabState(root: WindowLeaf(w4)),
        },
        windows: {...base.windows, w4: _w(_a)},
      );
      // The entry moved t2 into s2...
      final moved = two.copyWith(
        shells: {
          s1: ShellState(tabIds: [t1], activeTabId: t1),
          s2: ShellState(tabIds: [t3, t2], activeTabId: t2),
        },
      );
      // ...and s2 has since gone, its tabs back in s1.
      final now = moved.copyWith(
        shells: {
          s1: ShellState(tabIds: [t1, t2, t3], activeTabId: t1),
        },
      );
      expect([two, moved, now].every((d) => d.isValid), isTrue);
      expect(WindowingPatch.diff(two, moved).reversed.apply(now), isNull);
    });

    test('a unit the patch adds already exists: apply yields null', () {
      final p = WindowingPatch.diff(base, closed);
      expect(p.reversed.apply(base), isNull);
    });

    test('a window moved to another tab since: apply yields null', () {
      // Undo of closing w3 restores t2 as (w2 | w3)...
      final w3Closed = base.copyWith(
        tabs: {
          ...base.tabs,
          t2: TabState(root: WindowLeaf(w2), activeWindowId: w2),
        },
        windows: {...base.windows}..remove(w3),
      );
      // ...but w2 has since been moved into t1.
      final now = w3Closed.copyWith(
        tabs: {
          t1: TabState(
            root: WindowBranch(
              axis: Axis.vertical,
              children: [WindowLeaf(w1), WindowLeaf(w2)],
              ratios: const [0.5, 0.5],
            ),
            activeWindowId: w1,
          ),
          t2: const TabState(),
        },
      );
      expect(now.isValid, isTrue);
      expect(WindowingPatch.diff(base, w3Closed).reversed.apply(now), isNull);
    });

    test('the host falls back to the whole snapshot', () {
      final w3Closed = base.copyWith(
        tabs: {
          ...base.tabs,
          t2: TabState(root: WindowLeaf(w2), activeWindowId: w2),
        },
        windows: {...base.windows}..remove(w3),
      );
      final now = w3Closed.copyWith(
        tabs: {
          t1: TabState(
            root: WindowBranch(
              axis: Axis.vertical,
              children: [WindowLeaf(w1), WindowLeaf(w2)],
              ratios: const [0.5, 0.5],
            ),
            activeWindowId: w1,
          ),
          t2: const TabState(),
        },
      );
      final doc = ValueNotifier(now);
      final host = WindowingUndoHost(doc);
      host.undo(_entry(base, w3Closed));
      expect(doc.value, base);
      doc.value = now;
      host.redo(_entry(w3Closed, base));
      expect(doc.value, base);
    });
  });
}
