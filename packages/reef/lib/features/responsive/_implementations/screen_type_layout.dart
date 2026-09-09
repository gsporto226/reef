import 'package:flutter/widgets.dart';

/// Window-class of the current viewport, from Material window-class
/// breakpoints: compact (< 600) → mobile, medium (600–839) → tablet,
/// expanded (≥ 840) → desktop.
enum ScreenType { mobile, tablet, desktop }

/// Resolves the [ScreenType] for [context] from its width.
ScreenType screenTypeOf(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  if (width < 600) return ScreenType.mobile;
  if (width < 840) return ScreenType.tablet;
  return ScreenType.desktop;
}

/// Responsive layout switch over [ScreenType] (§4.3 `_layouts/` convention).
///
/// Dependency-free (no `responsive_builder`): resolves the screen type from
/// `MediaQuery` and builds the matching variant. Unspecified variants fall
/// back down the chain — desktop → tablet → mobile; tablet → mobile.
class ScreenTypeLayout extends StatelessWidget {
  /// Creates a responsive layout with per-screen-type builders.
  const ScreenTypeLayout({
    super.key,
    required this.mobile,
    this.tablet,
    this.desktop,
  });

  /// Builder for compact widths (< 600).
  final WidgetBuilder mobile;

  /// Builder for medium widths (600–839). Falls back to [mobile].
  final WidgetBuilder? tablet;

  /// Builder for expanded widths (≥ 840). Falls back to [tablet] then
  /// [mobile].
  final WidgetBuilder? desktop;

  @override
  Widget build(BuildContext context) => switch (screenTypeOf(context)) {
        ScreenType.mobile => mobile(context),
        ScreenType.tablet => (tablet ?? mobile)(context),
        ScreenType.desktop => (desktop ?? tablet ?? mobile)(context),
      };
}
