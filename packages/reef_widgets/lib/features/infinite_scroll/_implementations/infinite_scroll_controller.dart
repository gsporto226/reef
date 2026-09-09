import 'package:flutter/foundation.dart';
import 'package:listenable_plus/listenable_plus.dart';
import 'package:reef_widgets/features/infinite_scroll/_implementations/infinite_scroll_state.dart';
import 'package:reef_fp/async.dart';
import 'package:reef_fp/result.dart';

/// Loads one page. Returning `null` signals "no more data".
typedef InfiniteScrollLoader<T, F, E> = Future<Result<E, InfiniteScrollPage<T>>?>
    Function({
  required F filter,
  required int page,
  required int pageSize,
});

/// Paginated list behavior over listenables only — the CIApp
/// `InfiniteScrollController` re-expressed without rxdart/Subjects
/// (`switchMap`/`exhaustMap` → an explicit state machine, the
/// `CancellationToken` → a generation counter) (§1: streams are banned).
///
/// - [\$filter] drives resets: every *distinct* new ready filter restarts the
///   machine (accumulation cleared, page 1 loaded). [F] should implement `==`.
/// - [loadMore] is guarded: ignored while a page is in flight or the end was
///   reached (null page, empty page or [InfiniteScrollPage.maxPage]).
/// - A failed page keeps the accumulated list and allows a retry — a
///   deliberate divergence from CIApp, which cleared the list.
/// - Results from superseded generations are dropped (filter changed /
///   reset while in flight).
class InfiniteScrollController<T, F, E> {
  /// Creates a controller bound to [\$filter] and [loadPage].
  InfiniteScrollController({
    required this.$filter,
    required this.loadPage,
    this.pageSize = 20,
    this.initialLoad = true,
  }) {
    $filter.addListener(_onFilterChanged);
    _onFilterChanged();
  }

  /// The filter listenable driving resets (distinct ready filters restart
  /// the machine).
  final ValueListenable<Async<F>> $filter;

  /// Loads one page.
  final InfiniteScrollLoader<T, F, E> loadPage;

  /// Page size handed to [loadPage].
  final int pageSize;

  /// Whether the first ready filter triggers an automatic initial load.
  final bool initialLoad;

  final ValueNotifier<InfiniteScrollState<T>> _state =
      ValueNotifier(ScrollIdle<T>());

  /// The paginated list state.
  ValueListenable<InfiniteScrollState<T>> get $state => _state;

  /// Whether a follow-up page is currently in flight.
  late final ValueListenable<bool> $isLoadingMore =
      $state.map((state) => state is LoadingMore<T>);

  List<T> _accumulated = const [];
  int _page = 0;
  int? _maxPage;
  bool _hasReachedEnd = false;
  bool _loading = false;
  int _generation = 0;
  bool _skippedFirstInitialLoad = false;
  F? _currentFilter;

  /// Requests the next page (no-op while loading or after the end). With
  /// [initialLoad] false this triggers the first page once a filter is ready.
  void loadMore() {
    if (_loading || _hasReachedEnd) return;
    final state = _state.value;
    switch (state) {
      case ScrollLoaded<T>() || LoadingMore<T>():
        if (_maxPage != null && _page >= _maxPage!) return;
        _state.value = LoadingMore<T>(_accumulated);
        _load(page: _page + 1);
      case ScrollIdle<T>() when _currentFilter != null:
        _state.value = LoadingFirst<T>();
        _load(page: 1);
      default:
        break;
    }
  }

  /// Restarts the machine with the current filter (pull-to-reload).
  void reset() {
    final filter = _currentFilter;
    if (filter != null) _startWith(filter);
  }

  /// Releases the filter listener and the state notifier.
  void dispose() {
    $filter.removeListener(_onFilterChanged);
    _state.dispose();
  }

  void _onFilterChanged() {
    switch ($filter.value) {
      case Idle<F>() || Pending<F>():
        _generation++; // invalidate anything in flight
        _loading = false;
        _currentFilter = null;
        _state.value = ScrollIdle<T>();
      case Ready<F>(:final value):
        if (value != _currentFilter) _startWith(value);
    }
  }

  void _startWith(F filter) {
    _currentFilter = filter;
    _generation++;
    _loading = false;
    _accumulated = const [];
    _page = 0;
    _maxPage = null;
    _hasReachedEnd = false;

    if (!initialLoad && !_skippedFirstInitialLoad) {
      // Only the first filter application skips the automatic initial load.
      _skippedFirstInitialLoad = true;
      _state.value = ScrollIdle<T>();
      return;
    }
    _state.value = LoadingFirst<T>();
    _load(page: 1);
  }

  Future<void> _load({required int page}) async {
    final filter = _currentFilter;
    if (filter == null) return;

    _loading = true;
    final generation = _generation;
    final result =
        await loadPage(filter: filter, page: page, pageSize: pageSize);

    if (generation != _generation) return; // superseded — drop the stale result
    _loading = false;

    switch (result) {
      case null:
        _hasReachedEnd = true;
        _state.value = ScrollLoaded<T>(_accumulated);
      case Err<E, InfiniteScrollPage<T>>():
        // Keep the list, allow the user to try again.
        _state.value = ScrollLoaded<T>(_accumulated);
      case Ok<E, InfiniteScrollPage<T>>(:final value):
        _page = page;
        _maxPage = value.maxPage;
        if (value.items.isEmpty) _hasReachedEnd = true;
        _accumulated = [..._accumulated, ...value.items];
        _state.value = ScrollLoaded<T>(_accumulated);
    }
  }
}
