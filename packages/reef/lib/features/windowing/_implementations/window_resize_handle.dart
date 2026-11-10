import 'package:flutter/widgets.dart';
import 'package:reef/features/windowing/_implementations/windowing_delegate.dart';
import 'package:reef/features/windowing/_implementations/windowing_doc.dart';
import 'package:reef/features/windowing/_implementations/windowing_root.dart';

/// The divider between child `index - 1` and child `index` of [branch]: a
/// drag trades share between those two neighbours only, keeping at least 5%
/// each. Place it as a direct child of the flex that lays out [branch]; the
/// drag is measured against that flex's extent. One drag is one undo step.
/// Its look is the delegate's [WindowingDelegate.splitter].
class WindowResizeHandle extends StatefulWidget {
  const WindowResizeHandle({
    super.key,
    required this.branch,
    required this.index,
  });

  final WindowBranch branch;
  final int index;

  @override
  State<WindowResizeHandle> createState() => _WindowResizeHandleState();
}

class _WindowResizeHandleState extends State<WindowResizeHandle> {
  // Ratios at drag start plus the offset since then, so updates landing in
  // one frame never stack on stale ratios.
  List<double> _start = const [];
  double _offset = 0;

  bool get _horizontal => widget.branch.axis == Axis.horizontal;

  void _begin(DragStartDetails _) {
    _start = widget.branch.ratios;
    _offset = 0;
  }

  void _update(DragUpdateDetails d) {
    final flex = context.findAncestorRenderObjectOfType<RenderBox>()!.size;
    _offset += _horizontal ? d.delta.dx : d.delta.dy;
    final fraction = _offset / (_horizontal ? flex.width : flex.height);

    // ResizeWindow addresses a branch through any window under it: descend
    // first children to a leaf, counting the branches passed below this one.
    var levels = 0;
    var first = widget.branch.children.first;
    while (first is WindowBranch) {
      first = first.children.first;
      levels++;
    }
    final window = (first as WindowLeaf).id;
    WindowingScope.of(context).controller.resizeWindow(
      window,
      _shift(_start, widget.index - 1, fraction),
      levels: levels,
      coalesceKey: 'resize:${window.value}',
    );
  }

  void _end(DragEndDetails _) =>
      WindowingScope.of(context).controller.sealCoalescing();

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: _horizontal
        ? SystemMouseCursors.resizeColumn
        : SystemMouseCursors.resizeRow,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: _horizontal ? _begin : null,
      onHorizontalDragUpdate: _horizontal ? _update : null,
      onHorizontalDragEnd: _horizontal ? _end : null,
      onVerticalDragStart: _horizontal ? null : _begin,
      onVerticalDragUpdate: _horizontal ? null : _update,
      onVerticalDragEnd: _horizontal ? null : _end,
      child: WindowingDelegateScope.of(
        context,
      ).splitter(context, widget.branch.axis),
    ),
  );
}

/// Moves [delta] of the total from ratio `i + 1` to ratio `i`, keeping both
/// at least 5% and the sum at exactly one.
List<double> _shift(List<double> ratios, int i, double delta) {
  final pair = ratios[i] + ratios[i + 1];
  final a = (ratios[i] + delta).clamp(0.05, pair - 0.05);
  final out = [...ratios]
    ..[i] = a
    ..[i + 1] = pair - a;
  // Absorb float drift into the last ratio so ResizeWindow accepts the sum.
  out[out.length - 1] += 1 - out.fold(0.0, (s, r) => s + r);
  return out;
}
