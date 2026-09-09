import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reef/features/page_identity/_implementations/buffer_id.dart';
import 'package:reef/features/workspace/_implementations/split_tree.dart';
import 'package:reef/features/workspace/_implementations/split_tree_controller.dart';
import 'package:reef/features/workspace/_implementations/split_workspace.dart';
import 'package:reef_auto_route/features/workspace_routing/_implementations/workspace_controller.dart';
import 'package:reef_auto_route/features/workspace_routing/_implementations/workspace_registry.dart';

/// Reach for the tab's controller from inside any pane — the workspace
/// counterpart of reef's `ReefBufferScope` (§4.4). This is how a page fires
/// workspace intents (open/focus another buffer — the `:e`/`:split`
/// equivalents) without threading the controller through constructors.
class WorkspaceScope extends InheritedWidget {
  /// Wraps the workspace subtree.
  const WorkspaceScope({
    super.key,
    required this.controller,
    required super.child,
  });

  /// The hosting tab's split-tree controller.
  final SplitTreeController controller;

  /// The nearest [WorkspaceScope]'s controller.
  static SplitTreeController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WorkspaceScope>()!.controller;

  @override
  bool updateShouldNotify(WorkspaceScope oldWidget) =>
      oldWidget.controller != controller;
}

/// The route page hosting a workspace tab (blueprint §10.3). Reads `:tabId`
/// and the `?b=` deep-link param from its [RouteData], applies the deep link
/// to the tab's controller (already open → [SplitTreeController.focus], else
/// [SplitTreeController.open]), and renders the split tree through the
/// app's [WorkspaceRegistry].
class WorkspaceShell extends ConsumerWidget {
  /// Creates a shell for the workspace tab [tabId].
  const WorkspaceShell({
    super.key,
    required this.tabId,
    required this.registry,
    this.emptyBuilder,
  });

  /// The workspace tab this shell hosts — the controller provider key.
  final String tabId;

  /// Maps buffer ids to pages.
  final WorkspaceRegistry registry;

  /// Rendered while the workspace is empty.
  final WidgetBuilder? emptyBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(workspaceControllerProvider(tabId));
    _scheduleDeepLink(context, controller);
    return WorkspaceScope(
      controller: controller,
      child: ValueListenableBuilder<BufferId?>(
        valueListenable: controller.$focused,
        builder: (context, _, _) {
          _scheduleSync(context, controller);
          return SplitWorkspace(
            controller: controller,
            buildWindow: registry.buildWindow,
            emptyBuilder: emptyBuilder,
          );
        },
      ),
    );
  }

  /// Two-way URL sync (§10.3): focus changes rewrite this route's `?b=`
  /// query (replace — no stack growth). The guard compares against the
  /// focus read at callback time, so deep links applied in the same
  /// post-frame phase never trigger a redundant (or clobbering) replace.
  void _scheduleSync(BuildContext context, SplitTreeController controller) {
    final data = RouteData.of(context);
    final router = context.router;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final focused = controller.$focused.value;
      final routable = focused?.kind == null ? null : focused!.id;
      if (data.queryParams.optString('b') == routable) return;
      final path = data.match;
      router.replacePath(
        routable == null ? path : '$path?b=${Uri.encodeComponent(routable)}',
      );
    });
  }

  void _scheduleDeepLink(BuildContext context, SplitTreeController controller) {
    final data = RouteData.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final focusParam = data.queryParams.optString('b');
      if (focusParam == null || focusParam.isEmpty) return;
      final bufferId = BufferId.manual(focusParam);
      if (controller.$focused.value == bufferId) return;
      if (_contains(controller.$root.value, bufferId)) {
        controller.focus(bufferId);
      } else {
        controller.open(bufferId);
      }
    });
  }

  static bool _contains(SplitNode? node, BufferId bufferId) => switch (node) {
        null => false,
        final LeafSplitNode leaf => leaf.bufferId == bufferId,
        SplitBranchNode(:final children) =>
          children.any((child) => _contains(child, bufferId)),
      };
}
