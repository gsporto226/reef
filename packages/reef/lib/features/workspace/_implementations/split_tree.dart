import 'package:flutter/widgets.dart';
import 'package:reef/features/page_identity/_implementations/buffer_id.dart';

/// A node of the workspace's split tree (§10.1): leaves are windows bound to
/// a buffer, branches are splits with per-child flex ratios. Serializable —
/// the tree JSON is what a workspace hibernates (and, in Phase D, what
/// crosses OS-window boundaries).
sealed class SplitNode {
  const SplitNode();

  Map<String, dynamic> toJson();

  /// Rebuilds a node from [SplitNode.toJson] output. Buffer ids are
  /// reconstructed with [BufferId.manual] — the reattachment path.
  static SplitNode fromJson(Map<String, dynamic> json) => switch (json) {
        {'kind': 'leaf', 'bufferId': final String id} =>
          LeafSplitNode(BufferId.manual(id)),
        {
          'kind': 'branch',
          'axis': final String axis,
          'flexes': final List<dynamic> flexes,
          'children': final List<dynamic> children,
        } =>
          SplitBranchNode(
            axis: axis == 'vertical' ? Axis.vertical : Axis.horizontal,
            flexes: flexes.cast<double>(),
            children: children
                .map((child) => fromJson(child as Map<String, dynamic>))
                .toList(growable: false),
          ),
        _ => throw ArgumentError.value(json, 'json', 'not a SplitNode'),
      };
}

/// A window: one buffer in one pane.
final class LeafSplitNode extends SplitNode {
  const LeafSplitNode(this.bufferId);

  final BufferId bufferId;

  @override
  bool operator ==(Object other) => other is LeafSplitNode && other.bufferId == bufferId;

  @override
  int get hashCode => bufferId.hashCode;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'kind': 'leaf',
        'bufferId': bufferId.id,
      };
}

/// A split: children laid out along [axis], sized by [flexes].
final class SplitBranchNode extends SplitNode {
  const SplitBranchNode({
    required this.axis,
    required this.flexes,
    required this.children,
  });

  final Axis axis;
  final List<double> flexes;
  final List<SplitNode> children;

  @override
  bool operator ==(Object other) =>
      other is SplitBranchNode &&
      other.axis == axis &&
      _listEquals(other.flexes, flexes) &&
      _listEquals(other.children, children);

  @override
  int get hashCode => Object.hash(axis, Object.hashAll(flexes),
      Object.hashAll(children.map((child) => child.hashCode)));

  static bool _listEquals<T>(List<T> a, List<T> b) =>
      a.length == b.length && a.indexed.every((e) => b[e.$1] == e.$2);

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'kind': 'branch',
        'axis': axis == Axis.vertical ? 'vertical' : 'horizontal',
        'flexes': flexes,
        'children': children.map((child) => child.toJson()).toList(),
      };
}
