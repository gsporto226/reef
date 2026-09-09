import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reef/features/page/_implementations/reef_window.dart';
import 'package:reef/features/page_identity/_implementations/buffer_id.dart';
import 'package:reef/features/view_model/_implementations/view_model.dart';
import 'package:reef/features/workspace/_implementations/split_tree.dart';
import 'package:reef/features/workspace/_implementations/split_tree_controller.dart';
import 'package:reef/features/workspace/_implementations/split_workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MarkerModel {
  const MarkerModel(this.label);

  final String label;
}

class MarkerViewModel extends ViewModel<MarkerModel> {
  MarkerViewModel(String initial) : super(MarkerModel(initial));
}

final markerProvider = Provider.autoDispose.family<MarkerViewModel, BufferId>(
  (ref, id) => MarkerViewModel(id.id),
);

Widget _host(SplitTreeController controller) => ProviderScope(
      child: WidgetsApp(
        color: const Color(0xFF00695C),
        builder: (_, _) => SplitWorkspace(
          controller: controller,
          buildWindow: (context, bufferId) => ReefWindow(
            bufferId: bufferId,
            viewModel: (id) => markerProvider(id),
            builder: (context, vm) => Text(vm.model.label),
          ),
        ),
      ),
    );

void main() {
  group('SplitNode serialization', () {
    test('leaf roundtrip', () {
      const node = LeafSplitNode(BufferId.manual('doc'));
      expect(SplitNode.fromJson(node.toJson()), node);
    });

    test('nested branch roundtrip', () {
      const node = SplitBranchNode(
        axis: Axis.horizontal,
        flexes: [2, 1],
        children: [
          LeafSplitNode(BufferId.manual('a')),
          SplitBranchNode(
            axis: Axis.vertical,
            flexes: [1, 1],
            children: [
              LeafSplitNode(BufferId.manual('b')),
              LeafSplitNode(BufferId.manual('c')),
            ],
          ),
        ],
      );
      expect(SplitNode.fromJson(node.toJson()), node);
    });

    test('garbage json throws ArgumentError', () {
      expect(() => SplitNode.fromJson({'kind': '???'}), throwsArgumentError);
    });
  });

  group('SplitTreeController', () {
    test('open on empty becomes root; further opens replace the focused leaf',
        () {
      final controller = SplitTreeController();
      final a = BufferId.manual('a');
      final b = BufferId.manual('b');

      controller.open(a);
      expect(controller.$root.value, LeafSplitNode(a));
      expect(controller.$focused.value, a);

      controller.open(b);
      expect(controller.$root.value, LeafSplitNode(b));
      expect(controller.$focused.value, b);
    });

    test('split wraps the focused leaf in a branch and focuses the new pane',
        () {
      final controller = SplitTreeController();
      final a = BufferId.manual('a');
      final b = BufferId.manual('b');
      controller.open(a);

      controller.split(b, axis: Axis.horizontal);
      expect(
        controller.$root.value,
        SplitBranchNode(
          axis: Axis.horizontal,
          flexes: [1, 1],
          children: [LeafSplitNode(a), LeafSplitNode(b)],
        ),
      );
      expect(controller.$focused.value, b);
    });

    test('closeFocused removes the leaf and collapses single-child branches',
        () {
      final controller = SplitTreeController();
      final a = BufferId.manual('a');
      final b = BufferId.manual('b');
      controller.open(a);
      controller.split(b, axis: Axis.vertical);

      controller.closeFocused(); // closes b
      expect(controller.$root.value, LeafSplitNode(a));
      expect(controller.$focused.value, a);

      controller.closeFocused(); // closes a — workspace empty
      expect(controller.$root.value, isNull);
      expect(controller.$focused.value, isNull);
    });

    test('toJson/fromJson restores the tree and focus', () {
      final controller = SplitTreeController();
      controller.open(BufferId.manual('a'));
      controller.split(BufferId.manual('b'), axis: Axis.vertical);

      final restored = SplitTreeController.fromJson(controller.toJson());
      expect(restored.$root.value, controller.$root.value);
      expect(restored.$focused.value, BufferId.manual('b'));
      restored.dispose();
    });
  });

  group('SplitWorkspace widget', () {
    testWidgets('renders one pane per leaf, ReefWindow-backed', (tester) async {
      final controller = SplitTreeController();
      controller.open(BufferId.manual('doc-a'));
      await tester.pumpWidget(_host(controller));

      expect(find.text('doc-a'), findsOneWidget);
      controller.dispose();
    });

    testWidgets('two panes on the same buffer render the same viewmodel '
        '(live-sync across panes)', (tester) async {
      final buffer = BufferId.manual('shared');
      final controller = SplitTreeController();
      controller.open(buffer);
      controller.split(buffer, axis: Axis.horizontal);
      await tester.pumpWidget(_host(controller));

      expect(find.text('shared'), findsNWidgets(2),
          reason: 'both panes show the shared buffer');
      controller.dispose();
    });

    testWidgets('empty workspace renders the placeholder', (tester) async {
      final controller = SplitTreeController();
      await tester.pumpWidget(WidgetsApp(
        color: const Color(0xFF00695C),
        builder: (_, _) => SplitWorkspace(
          controller: controller,
          emptyBuilder: (_) => const Text('no buffers'),
          buildWindow: (_, _) => const SizedBox(),
        ),
      ));
      expect(find.text('no buffers'), findsOneWidget);
      controller.dispose();
    });
  });
}


