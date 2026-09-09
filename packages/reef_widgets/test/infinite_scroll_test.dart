import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reef_widgets/features/infinite_scroll/_implementations/infinite_scroll_controller.dart';
import 'package:reef_widgets/features/infinite_scroll/_implementations/infinite_scroll_state.dart';
import 'package:reef_widgets/features/infinite_scroll/_implementations/infinite_scroll_widget.dart';
import 'package:reef_fp/async.dart';
import 'package:reef_fp/result.dart';

class FakeError {
  const FakeError();
}

/// Paged fake source with per-call future queue for stale-generation tests.
class FakeRepo {
  FakeRepo(this.pages);

  final Map<int, List<String>> pages;
  final Set<int> failingPages = {};
  final List<int> requestedPages = [];
  final List<Completer<Result<FakeError, InfiniteScrollPage<String>>?>>
      _pending = [];
  bool manualMode = false;

  Future<Result<FakeError, InfiniteScrollPage<String>>?> load({
    required String filter,
    required int page,
    required int pageSize,
  }) {
    requestedPages.add(page);
    if (manualMode) {
      final completer =
          Completer<Result<FakeError, InfiniteScrollPage<String>>?>();
      _pending.add(completer);
      return completer.future;
    }
    return Future.value(_resultFor(page));
  }

  Result<FakeError, InfiniteScrollPage<String>>? _resultFor(int page) {
    if (failingPages.contains(page)) {
      return const Err<FakeError, InfiniteScrollPage<String>>(FakeError());
    }
    final items = pages[page];
    if (items == null) return null;
    return Ok<FakeError, InfiniteScrollPage<String>>(
      InfiniteScrollPage<String>(items: items),
    );
  }

  /// Completes the oldest in-flight (manualMode) call.
  void completeOldest([Result<FakeError, InfiniteScrollPage<String>>? result]) {
    _pending.removeAt(0).complete(result ?? _resultFor(requestedPages.first));
  }
}

class Harness {
  Harness({this.initialLoad = true, FakeRepo? repo, this.refreshWrapper})
      : repo = repo ?? FakeRepo({1: ['a', 'b'], 2: ['c'], 3: []});

  final bool initialLoad;
  final RefreshWrapper? refreshWrapper;
  final FakeRepo repo;
  final filter = ValueNotifier<Async<String>>(const Async<String>.idle());
  late final InfiniteScrollController<String, String, FakeError> controller =
      InfiniteScrollController<String, String, FakeError>(
    $filter: filter,
    loadPage: ({required filter, required page, required pageSize}) =>
        repo.load(filter: filter, page: page, pageSize: pageSize),
    initialLoad: initialLoad,
  );

  Widget host() => WidgetsApp(
        color: const Color(0xFF00897B),
        builder: (_, _) => InfiniteScrollWidget<String, String, FakeError>(
          controller: controller,
          idleBuilder: (_) => const Text('idle'),
          emptyBuilder: (_) => const Text('empty'),
          refreshWrapper: refreshWrapper,
          itemBuilder: (_, item, i) => Text('item: $item'),
        ),
      );

  void dispose() => controller.dispose();
}

void main() {
  testWidgets('idle until the filter is ready, then loads the first page',
      (tester) async {
    final h = Harness();
    addTearDown(h.dispose);
    await tester.pumpWidget(h.host());
    expect(find.text('idle'), findsOneWidget);

    h.filter.value = const Async<String>.ready('q');
    await tester.pump();
    await tester.pump();

    expect(find.text('item: a'), findsOneWidget);
    expect(find.text('item: b'), findsOneWidget);
    expect(h.repo.requestedPages, [1]);
  });

  testWidgets('loadMore accumulates pages', (tester) async {
    final h = Harness();
    addTearDown(h.dispose);
    await tester.pumpWidget(h.host());
    h.filter.value = const Async<String>.ready('q');
    await tester.pump();
    await tester.pump();

    h.controller.loadMore();
    await tester.pump();
    await tester.pump();

    expect(find.text('item: a'), findsOneWidget);
    expect(find.text('item: c'), findsOneWidget);
    expect(h.repo.requestedPages, [1, 2]);
  });

  testWidgets('null page signals the end; loadMore is a no-op afterwards',
      (tester) async {
    final h = Harness(repo: FakeRepo({1: ['a']}));
    addTearDown(h.dispose);
    await tester.pumpWidget(h.host());
    h.filter.value = const Async<String>.ready('q');
    await tester.pump();
    await tester.pump();

    h.controller.loadMore();
    await tester.pump();
    await tester.pump();
    expect(h.repo.requestedPages, [1, 2]); // page 2 probed once

    h.controller.loadMore();
    await tester.pump();
    await tester.pump();
    expect(h.repo.requestedPages, [1, 2], reason: 'end reached — no re-probe');
  });

  testWidgets('an empty page ends pagination', (tester) async {
    final h = Harness();
    addTearDown(h.dispose);
    await tester.pumpWidget(h.host());
    h.filter.value = const Async<String>.ready('q');
    await tester.pump();
    await tester.pump();
    h.controller.loadMore();
    await tester.pump();
    await tester.pump();
    // Page 2 = ['c'] → not end; page 3 = [] → end.
    h.controller.loadMore();
    await tester.pump();
    await tester.pump();
    expect(h.repo.requestedPages, [1, 2, 3]);

    h.controller.loadMore();
    await tester.pump();
    await tester.pump();
    expect(h.repo.requestedPages, [1, 2, 3]);
  });

  testWidgets('maxPage caps pagination', (tester) async {
    final repo = FakeRepo({1: ['a']});
    final filter = ValueNotifier<Async<String>>(const Async<String>.idle());
    final controller = InfiniteScrollController<String, String, FakeError>(
      $filter: filter,
      loadPage: ({required filter, required page, required pageSize}) async {
        repo.requestedPages.add(page);
        return page == 1
            ? const Ok<FakeError, InfiniteScrollPage<String>>(
                InfiniteScrollPage<String>(items: ['a'], maxPage: 1))
            : null;
      },
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(WidgetsApp(
      color: const Color(0xFF00897B),
      builder: (_, _) => InfiniteScrollWidget<String, String, FakeError>(
        controller: controller,
        itemBuilder: (_, item, i) => Text('item: $item'),
      ),
    ));
    filter.value = const Async<String>.ready('q');
    await tester.pump();
    await tester.pump();

    controller.loadMore();
    await tester.pump();
    await tester.pump();
    expect(repo.requestedPages, [1], reason: 'maxPage reached — no page 2');
  });

  testWidgets('a distinct filter restarts the machine', (tester) async {
    final h = Harness();
    addTearDown(h.dispose);
    await tester.pumpWidget(h.host());
    h.filter.value = const Async<String>.ready('q1');
    await tester.pump();
    await tester.pump();
    h.controller.loadMore();
    await tester.pump();
    await tester.pump();

    h.filter.value = const Async<String>.ready('q2');
    await tester.pump();
    await tester.pump();

    expect(find.text('item: c'), findsNothing, reason: 'accumulation reset');
    expect(find.text('item: a'), findsOneWidget);
    expect(h.repo.requestedPages, [1, 2, 1]);
  });

  testWidgets('a failed page keeps the list and loadMore retries',
      (tester) async {
    final h = Harness();
    addTearDown(h.dispose);
    h.repo.failingPages.add(2);
    await tester.pumpWidget(h.host());
    h.filter.value = const Async<String>.ready('q');
    await tester.pump();
    await tester.pump();
    h.controller.loadMore();
    await tester.pump();
    await tester.pump();

    expect(find.text('item: a'), findsOneWidget,
        reason: 'list kept after a failed page');
    expect(find.text('item: c'), findsNothing);

    h.repo.failingPages.clear();
    h.controller.loadMore();
    await tester.pump();
    await tester.pump();
    expect(find.text('item: c'), findsOneWidget);
    expect(h.repo.requestedPages, [1, 2, 2], reason: 'page 2 retried');
  });

  testWidgets('results from a superseded generation are dropped',
      (tester) async {
    final h = Harness();
    addTearDown(h.dispose);
    h.repo.manualMode = true;
    await tester.pumpWidget(h.host());

    h.filter.value = const Async<String>.ready('slow');
    await tester.pump();
    h.filter.value = const Async<String>.ready('fast');
    await tester.pump();

    // Complete the superseded (slow) call — its result must be dropped.
    h.repo.completeOldest(const Ok<FakeError, InfiniteScrollPage<String>>(
      InfiniteScrollPage<String>(items: ['stale']),
    ));
    // Complete the current (fast) call.
    h.repo.completeOldest();
    await tester.pump();
    await tester.pump();

    expect(find.text('item: a'), findsOneWidget,
        reason: 'the fast filter loaded fine');
    expect(find.text('item: stale'), findsNothing,
        reason: 'stale generation result must be dropped');
  });

  testWidgets('initialLoad=false waits for an explicit loadMore',
      (tester) async {
    final h = Harness(initialLoad: false);
    addTearDown(h.dispose);
    await tester.pumpWidget(h.host());
    h.filter.value = const Async<String>.ready('q');
    await tester.pump();
    await tester.pump();

    expect(find.text('idle'), findsOneWidget);
    expect(h.repo.requestedPages, isEmpty);

    h.controller.loadMore();
    await tester.pump();
    await tester.pump();
    expect(find.text('item: a'), findsOneWidget);
    expect(h.repo.requestedPages, [1]);
  });

  testWidgets('widget: a provided footer shows while loading more', (tester) async {
    final h = Harness(
      refreshWrapper: (_, list, _) => list,
    );
    addTearDown(h.dispose);
    h.repo.manualMode = true;
    await tester.pumpWidget(WidgetsApp(
      color: const Color(0xFF00897B),
      builder: (_, _) => InfiniteScrollWidget<String, String, FakeError>(
        controller: h.controller,
        emptyBuilder: (_) => const Text('empty'),
        idleBuilder: (_) => const Text('idle'),
        refreshWrapper: h.refreshWrapper,
        footerBuilder: (_) => const Text('loading more…'),
        itemBuilder: (_, item, i) => Text('item: $item'),
      ),
    ));
    h.filter.value = const Async<String>.ready('q');
    await tester.pump();
    h.repo.completeOldest();
    await tester.pump();
    await tester.pump();
    expect(find.text('item: a'), findsOneWidget);

    h.controller.loadMore();
    await tester.pump();
    expect(find.text('loading more…'), findsOneWidget,
        reason: 'provided footer while the next page is in flight');

    h.repo.completeOldest();
    await tester.pump();
    await tester.pump();
    expect(find.text('loading more…'), findsNothing);
  });

  testWidgets('widget: empty first page renders the empty builder',
      (tester) async {
    final h = Harness(repo: FakeRepo({1: []}));
    addTearDown(h.dispose);
    await tester.pumpWidget(h.host());
    h.filter.value = const Async<String>.ready('q');
    await tester.pump();
    await tester.pump();
    expect(find.text('empty'), findsOneWidget);
  });

  testWidgets('widget: no Material chrome — defaults are design-free',
      (tester) async {
    // Type names as strings — the package (even its tests) imports no
    // design system.
    bool exists(WidgetTester tester, String type) => tester
        .widgetList(find.byWidgetPredicate((w) => w.runtimeType.toString() == type))
        .isNotEmpty;

    final h = Harness();
    addTearDown(h.dispose);
    h.repo.manualMode = true;
    await tester.pumpWidget(h.host());

    h.filter.value = const Async<String>.ready('q');
    await tester.pump();
    expect(exists(tester, 'CircularProgressIndicator'), isFalse,
        reason: 'loadingFirst has no Material default');

    h.repo.completeOldest();
    await tester.pump();
    await tester.pump();
    expect(exists(tester, 'RefreshIndicator'), isFalse,
        reason: "pull-to-refresh chrome is the app's choice, not the widget's");

    h.controller.loadMore();
    await tester.pump();
    expect(exists(tester, 'CircularProgressIndicator'), isFalse,
        reason: 'footer has no Material default');
  });

  testWidgets('widget: refreshWrapper injects chrome and its onRefresh resets',
      (tester) async {
    Future<void> Function()? capturedOnRefresh;
    final h = Harness(
      refreshWrapper: (_, list, onRefresh) {
        capturedOnRefresh = onRefresh;
        return list;
      },
    );
    addTearDown(h.dispose);
    await tester.pumpWidget(h.host());
    h.filter.value = const Async<String>.ready('q');
    await tester.pump();
    await tester.pump();
    h.controller.loadMore();
    await tester.pump();
    await tester.pump();
    expect(find.text('item: c'), findsOneWidget);
    expect(h.repo.requestedPages, [1, 2]);

    await capturedOnRefresh!();
    await tester.pump();
    await tester.pump();

    expect(find.text('item: c'), findsNothing,
        reason: 'onRefresh resets the accumulation');
    expect(find.text('item: a'), findsOneWidget);
    expect(h.repo.requestedPages, [1, 2, 1]);
  });
}


