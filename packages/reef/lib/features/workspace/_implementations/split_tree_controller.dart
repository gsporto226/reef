import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:reef/features/page_identity/_implementations/buffer_id.dart';
import 'package:reef/features/workspace/_implementations/split_tree.dart';

/// Owns the workspace's split tree and the focused window (§10.1) — the
/// open/split/close intents of a tab. Pure listenables; the [SplitWorkspace]
/// widget renders it, navigation (router adapter) hosts it.
class SplitTreeController {
  /// Creates a controller, optionally restoring a serialized tree.
  SplitTreeController({SplitNode? initialRoot, BufferId? initialFocus})
      : _root = ValueNotifier(initialRoot),
        _focused = ValueNotifier(initialFocus);

  final ValueNotifier<SplitNode?> _root;
  final ValueNotifier<BufferId?> _focused;

  /// The current tree, null while the workspace is empty.
  ValueListenable<SplitNode?> get $root => _root;

  /// The focused window's buffer (receives [open]).
  ValueListenable<BufferId?> get $focused => _focused;

  /// Opens [bufferId]: replaces the focused leaf — or becomes the root when
  /// the workspace is empty. The opened window takes focus.
  void open(BufferId bufferId) {
    final root = _root.value;
    if (root == null) {
      _root.value = LeafSplitNode(bufferId);
      _focused.value = bufferId;
      return;
    }
    _root.value = _mapFocused(root, (leaf) => LeafSplitNode(bufferId));
    _focused.value = bufferId;
  }

  /// Splits the focused leaf along [axis]; the focused buffer keeps one pane
  /// and [bufferId] takes the other (and the focus).
  void split(BufferId bufferId, {required Axis axis}) {
    final root = _root.value;
    final focused = _focused.value;
    if (root == null) {
      open(bufferId);
      return;
    }
    final newLeaf = LeafSplitNode(bufferId);
    _root.value = _mapFocused(
      root,
      (leaf) => SplitBranchNode(
        axis: axis,
        flexes: const [1, 1],
        children: focused == leaf.bufferId
            ? [LeafSplitNode(leaf.bufferId), newLeaf]
            : [newLeaf, LeafSplitNode(leaf.bufferId)],
      ),
    );
    _focused.value = bufferId;
  }

  /// Closes the focused leaf. Branches collapsing to a single child are
  /// replaced by that child. Closing the last leaf empties the workspace.
  void closeFocused() {
    final root = _root.value;
    final focused = _focused.value;
    if (root == null || focused == null) return;

    SplitNode? next = _removeLeaf(root, focused);
    if (next is SplitBranchNode) {
      next = _collapse(next);
    }
    _root.value = next;
    _focused.value = _firstLeafBuffer(next);
  }

  /// Focuses the window showing [bufferId].
  void focus(BufferId bufferId) => _focused.value = bufferId;

  /// Serializes the tree and focus (workspace hibernation, §10.2).
  Map<String, dynamic>? toJson() {
    final root = _root.value;
    if (root == null) return null;
    return <String, dynamic>{
      'root': root.toJson(),
      'focused': _focused.value?.id,
    };
  }

  /// Restores a serialized tree (and its focus).
  static SplitTreeController fromJson(Map<String, dynamic>? json) {
    if (json == null) return SplitTreeController();
    final root = SplitNode.fromJson(json['root'] as Map<String, dynamic>);
    final focusedId = json['focused'] as String?;
    return SplitTreeController(
      initialRoot: root,
      initialFocus: focusedId == null ? _firstLeafBuffer(root) : BufferId.manual(focusedId),
    );
  }

  /// Releases the notifiers.
  void dispose() {
    _root.dispose();
    _focused.dispose();
  }

  SplitNode _mapFocused(SplitNode node, SplitNode Function(LeafSplitNode) transform) {
    if (node is LeafSplitNode) {
      return node.bufferId == _focused.value ? transform(node) : node;
    }
    if (node is SplitBranchNode) {
      return SplitBranchNode(
        axis: node.axis,
        flexes: node.flexes,
        children: node.children.map((child) => _mapFocused(child, transform)).toList(),
      );
    }
    throw StateError('unknown SplitNode: $node');
  }

  SplitNode? _removeLeaf(SplitNode node, BufferId bufferId) {
    if (node is LeafSplitNode) {
      return node.bufferId == bufferId ? null : node;
    }
    if (node is SplitBranchNode) {
      final children = node.children
          .map((child) => _removeLeaf(child, bufferId))
          .whereType<SplitNode>()
          .toList();
      if (children.isEmpty) return null;
      return SplitBranchNode(
        axis: node.axis,
        flexes: List<double>.of(node.flexes)..length = children.length,
        children: children,
      );
    }
    throw StateError('unknown SplitNode: $node');
  }

  SplitNode _collapse(SplitNode node) => switch (node) {
        final LeafSplitNode leaf => leaf,
        SplitBranchNode(:final children) when children.length == 1 =>
          _collapse(children.single),
        SplitBranchNode branch => SplitBranchNode(
            axis: branch.axis,
            flexes: branch.flexes,
            children: branch.children.map(_collapse).toList(),
          ),
      };

  static BufferId? _firstLeafBuffer(SplitNode? node) => switch (node) {
        null => null,
        LeafSplitNode(:final bufferId) => bufferId,
        SplitBranchNode(:final children) => _firstLeafBuffer(children.first),
      };
}
