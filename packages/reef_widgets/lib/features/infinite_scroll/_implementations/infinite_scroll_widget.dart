import 'package:flutter/widgets.dart';
import 'package:reef_widgets/features/infinite_scroll/_implementations/infinite_scroll_controller.dart';
import 'package:reef_widgets/features/infinite_scroll/_implementations/infinite_scroll_state.dart';

/// Wraps the scroll list to provide pull-to-refresh chrome — the app's
/// design-system choice (e.g. material_ui's `RefreshIndicator`), never the
/// widget's. [onRefresh] restarts the machine with the current filter
/// (§10-adjacent pull-to-reload).
typedef RefreshWrapper = Widget Function(
  BuildContext context,
  Widget list,
  Future<void> Function() onRefresh,
);

/// Paginated list over an [InfiniteScrollController] (behavior from CIApp's
/// `_behavior/infinite_scrolling`): scroll near the end triggers `loadMore`,
/// and the state is rendered through builder slots.
///
/// Design-system-agnostic (blueprint §5): depends only on
/// `package:flutter/widgets.dart` — no Material, no Cupertino. Pull-to-refresh
/// chrome is injected via [refreshWrapper] (null = no pull gesture) and the
/// loading slots ([loadingFirstBuilder], [footerBuilder]) default to empty —
/// bring your own indicators.
class InfiniteScrollWidget<T, F, E> extends StatelessWidget {
  /// Creates a paginated list.
  const InfiniteScrollWidget({
    super.key,
    required this.controller,
    required this.itemBuilder,
    this.refreshWrapper,
    this.emptyBuilder,
    this.idleBuilder,
    this.loadingFirstBuilder,
    this.footerBuilder,
    this.threshold = 200,
  });

  /// The paginated list controller.
  final InfiniteScrollController<T, F, E> controller;

  /// Builds an item row.
  final Widget Function(BuildContext context, T item, int index) itemBuilder;

  /// Wraps the list with pull-to-refresh chrome; [RefreshWrapper.onRefresh]
  /// resets the controller. Null (the default) renders the bare list — no
  /// pull gesture.
  final RefreshWrapper? refreshWrapper;

  /// Rendered when a load settled with zero items.
  final WidgetBuilder? emptyBuilder;

  /// Rendered while no filter is ready.
  final WidgetBuilder? idleBuilder;

  /// Rendered while the first page loads. Defaults to nothing — bring your
  /// own indicator.
  final WidgetBuilder? loadingFirstBuilder;

  /// Rendered below the items while a follow-up page loads. Defaults to
  /// nothing — bring your own indicator.
  final WidgetBuilder? footerBuilder;

  /// Distance (logical px) from the end that triggers
  /// [InfiniteScrollController.loadMore].
  final double threshold;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder(
        valueListenable: controller.$state,
        builder: (context, state, _) => switch (state) {
          ScrollIdle<T>() =>
            idleBuilder?.call(context) ??
                (emptyBuilder?.call(context) ?? const SizedBox.shrink()),
          LoadingFirst<T>() =>
            loadingFirstBuilder?.call(context) ?? const SizedBox.shrink(),
          LoadingMore<T>() || ScrollLoaded<T>() => _refreshable(context, state),
        },
      );

  Widget _refreshable(BuildContext context, InfiniteScrollState<T> state) {
    final list = NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.pixels >=
            notification.metrics.maxScrollExtent - threshold) {
          controller.loadMore();
        }
        return false;
      },
      child: _list(context, state),
    );
    return refreshWrapper?.call(context, list, () async => controller.reset()) ??
        list;
  }

  Widget _list(BuildContext context, InfiniteScrollState<T> state) {
    final items = state.itemsOrNull;
    final loadingMore = state is LoadingMore<T>;

    if (items.isEmpty && !loadingMore) {
      return emptyBuilder?.call(context) ?? ListView();
    }

    return ListView.builder(
      itemCount: items.length + (loadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= items.length) {
          return footerBuilder?.call(context) ?? const SizedBox.shrink();
        }
        return itemBuilder(context, items[index], index);
      },
    );
  }
}
