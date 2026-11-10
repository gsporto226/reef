import 'package:flutter/widgets.dart';
import 'package:reef/features/responsive/_implementations/screen_type_layout.dart';
import 'package:reef/features/windowing/_implementations/windowing_controller.dart';
import 'package:reef/features/windowing/_implementations/windowing_delegate.dart';
import 'package:reef/features/windowing/_implementations/windowing_ids.dart';
import 'package:reef/features/windowing/_implementations/windowing_root.dart';

/// Draws shell [shellId] as a whole layout, e.g. [DesktopProjection].
typedef WindowingProjection = Widget Function(
  BuildContext context,
  WindowingController controller,
  ShellId shellId,
);

/// Picks the [WindowingProjection] for shell [shellId] in [context].
typedef WindowingProjectionPolicy = WindowingProjection Function(
  BuildContext context,
  WindowingController controller,
  ShellId shellId,
);

/// [DesktopProjection] on expanded screens, [TabbedProjection] on medium
/// and compact ones.
WindowingProjection defaultWindowingProjection(
  BuildContext context,
  WindowingController _,
  ShellId _,
) => screenTypeOf(context) == ScreenType.desktop
    ? (_, _, shellId) => DesktopProjection(shellId)
    : (_, _, shellId) => TabbedProjection(shellId);

/// Shell [shellId] with an optional tab strip over its windows tiled as the
/// [WindowArrangement.flexTree].
class DesktopProjection extends StatelessWidget {
  const DesktopProjection(
    this.shellId, {
    super.key,
    this.showTabStrip = true,
    this.tabStrip,
  });

  final ShellId shellId;

  /// Whether the tab strip shows.
  final bool showTabStrip;

  /// Default: the delegate's [WindowingDelegate.tabStrip].
  final TabStripBuilder? tabStrip;

  @override
  Widget build(BuildContext context) => _project(
    context,
    shellId,
    WindowArrangement.flexTree,
    showTabStrip
        ? tabStrip ?? WindowingDelegateScope.of(context).tabStrip
        : null,
  );
}

/// Shell [shellId] with its tab bar over the tab's active window alone, the
/// [WindowArrangement.focusedOnly]; floating windows still show.
class TabbedProjection extends StatelessWidget {
  const TabbedProjection(this.shellId, {super.key, this.tabBar});

  final ShellId shellId;

  /// Default: the delegate's [WindowingDelegate.tabStrip], drawn over a
  /// [TabStripSlot].
  final TabStripBuilder? tabBar;

  @override
  Widget build(BuildContext context) => _project(
    context,
    shellId,
    WindowArrangement.focusedOnly,
    tabBar ?? WindowingDelegateScope.of(context).tabStrip,
  );
}

Widget _project(
  BuildContext context,
  ShellId shellId,
  WindowArrangement arrangement,
  TabStripBuilder? strip,
) => WindowingDelegateScope(
  delegate: WindowingDelegateScope.of(context).copyWith(
    windowArrangement:
        WindowingDelegateScope.of(context).windowArrangement ?? arrangement,
  ),
  child: ShellHost(
    shellId,
    surfaceBuilder: (context, shellId, canvas) => Column(
      children: [
        ?strip?.call(context, shellId),
        Expanded(child: canvas),
      ],
    ),
  ),
);
