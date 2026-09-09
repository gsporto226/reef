/// State of an [InfiniteScrollController] — a hand-written sealed union (reef
/// core stays codegen-free; the freezed mandate covers app models).
sealed class InfiniteScrollState<T> {
  const InfiniteScrollState();

  /// The accumulated items, empty when none.
  List<T> get itemsOrNull => switch (this) {
        LoadingMore<T>(:final items) => items,
        ScrollLoaded<T>(:final items) => items,
        _ => const [],
      };
}

/// No filter yet (or filter cleared) — nothing to list.
final class ScrollIdle<T> extends InfiniteScrollState<T> {
  const ScrollIdle();
}

/// First page in flight.
final class LoadingFirst<T> extends InfiniteScrollState<T> {
  const LoadingFirst();
}

/// A follow-up page is in flight over the accumulated items.
final class LoadingMore<T> extends InfiniteScrollState<T> {
  const LoadingMore(this.items);

  final List<T> items;
}

/// Items settled (accumulated pages; empty when the source is empty or a
/// failed page was retried away).
final class ScrollLoaded<T> extends InfiniteScrollState<T> {
  const ScrollLoaded(this.items);

  final List<T> items;
}

/// One page from the source. A `null` loader return signals "no more data".
final class InfiniteScrollPage<T> {
  const InfiniteScrollPage({required this.items, this.maxPage});

  final List<T> items;

  /// Highest page the source will serve; null = unbounded.
  final int? maxPage;
}
