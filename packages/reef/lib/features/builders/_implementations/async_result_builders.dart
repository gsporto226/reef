import 'package:flutter/widgets.dart';
import 'package:formularium/features/localization/localizable_interface.dart';
import 'package:reef_fp/async.dart';
import 'package:reef_fp/result.dart';

/// Renders an [Async] value: idle/pending render the builder fed with
/// [sample] (real layout, placeholder data — the CIApp `PendingBuilder`
/// pattern without a skeleton dependency; wrap with your skeleton library if
/// wanted), ready renders the real value.
///
/// Takes a value, not a listenable — compose with `ValueListenableBuilder`
/// (§5: widgets are pure views).
class AsyncBuilder<T> extends StatelessWidget {
  /// Creates an async builder.
  const AsyncBuilder({
    super.key,
    required this.value,
    required this.sample,
    required this.builder,
    this.pending,
  });

  /// The async value to render.
  final Async<T> value;

  /// Placeholder value rendered while idle/pending.
  final T sample;

  /// Builds the UI for the current value (sample while not ready).
  final Widget Function(BuildContext context, T value) builder;

  /// Optional placeholder override for idle/pending.
  final WidgetBuilder? pending;

  @override
  Widget build(BuildContext context) => switch (value) {
        Idle<T>() || Pending<T>() =>
          pending?.call(context) ?? builder(context, sample),
        Ready<T>(:final value) => builder(context, value),
      };
}

/// Renders a [Result]: `Err` → [errorBuilder] (or the default error row),
/// `Ok` → [builder].
class ResultBuilder<E, T> extends StatelessWidget {
  /// Creates a result builder.
  const ResultBuilder({
    super.key,
    required this.value,
    required this.builder,
    this.errorBuilder,
  });

  /// The result to render.
  final Result<E, T> value;

  /// Builds the UI for the success value.
  final Widget Function(BuildContext context, T value) builder;

  /// Builds the UI for the error; defaults to a text row using
  /// [ILocalizable.localize] when the error implements it.
  final Widget Function(BuildContext context, E error)? errorBuilder;

  @override
  Widget build(BuildContext context) => switch (value) {
        Err<E, T>(:final value) =>
          errorBuilder?.call(context, value) ?? _defaultError(context, value),
        Ok<E, T>(:final value) => builder(context, value),
      };

  Widget _defaultError(BuildContext context, E error) => Text(
        error is ILocalizable ? error.localize() : error.toString(),
      );
}

/// Renders the universal async/error surface `Async<Result<E, T>>` (§1):
/// idle/pending → sample layout, `Ready(Ok)` → [builder], `Ready(Err)` →
/// error. Composes [AsyncBuilder] and [ResultBuilder] (the CIApp
/// `PendingResultBuilder` pattern).
class AsyncResultBuilder<E, T> extends StatelessWidget {
  /// Creates an async-result builder.
  const AsyncResultBuilder({
    super.key,
    required this.value,
    required this.sample,
    required this.builder,
    this.errorBuilder,
    this.pending,
  });

  /// The async result to render.
  final Async<Result<E, T>> value;

  /// Placeholder value (wrapped in `Ok`) rendered while idle/pending.
  final T sample;

  /// Builds the UI for the success value.
  final Widget Function(BuildContext context, T value) builder;

  /// Builds the UI for a surfaced error.
  final Widget Function(BuildContext context, E error)? errorBuilder;

  /// Optional placeholder override for idle/pending.
  final WidgetBuilder? pending;

  @override
  Widget build(BuildContext context) => AsyncBuilder<Result<E, T>>(
        value: value,
        sample: Ok<E, T>(sample),
        pending: pending,
        builder: (context, result) => ResultBuilder<E, T>(
          value: result,
          errorBuilder: errorBuilder,
          builder: builder,
        ),
      );
}
