import 'package:flutter/widgets.dart';
import 'package:reef/features/page_identity/_implementations/buffer_id.dart';
import 'package:reef/features/workspace/_implementations/split_tree.dart';
import 'package:reef/features/workspace/_implementations/split_tree_controller.dart';

/// Renders the workspace: the controller's split tree as a flex layout, one
/// pane per leaf (§10.1). Router-agnostic — the app (or a router adapter)
/// supplies [buildWindow], mapping a buffer id to its page widget; every pane
/// is a `ReefWindow`, so two panes on the same buffer live-sync (§10.1).
class SplitWorkspace extends StatelessWidget {
  /// Creates a workspace bound to [controller].
  const SplitWorkspace({
    super.key,
    required this.controller,
    required this.buildWindow,
    this.emptyBuilder,
  });

  /// The workspace state.
  final SplitTreeController controller;

  /// Maps a buffer id to its page widget (typically `TaskListPage(bufferId: id)`).
  final Widget Function(BuildContext context, BufferId bufferId) buildWindow;

  /// Rendered while the workspace is empty.
  final WidgetBuilder? emptyBuilder;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<SplitNode?>(
        valueListenable: controller.$root,
        builder: (context, root, _) => root == null
            ? (emptyBuilder?.call(context) ?? const SizedBox.shrink())
            : _node(context, root),
      );

  Widget _node(BuildContext context, SplitNode node) {
    if (node is LeafSplitNode) {
      return buildWindow(context, node.bufferId);
    }
    if (node is SplitBranchNode) {
      return Flex(
        direction: node.axis,
        children: [
          for (var i = 0; i < node.children.length; i++)
            Expanded(
              flex: _flexOf(node.flexes, i),
              child: _node(context, node.children[i]),
            ),
        ],
      );
    }
    throw StateError('unknown SplitNode: $node');
  }

  int _flexOf(List<double> flexes, int index) =>
      ((flexes.length > index ? flexes[index] : 1) * 1000).round();
}
