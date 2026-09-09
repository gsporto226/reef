import 'package:flutter/widgets.dart';
import 'package:reef/features/page_identity/_implementations/buffer_id.dart';
import 'package:reef_example/_kit/kit.dart';

/// The content of a popped-out OS window (blueprint §10.4): a header with the
/// buffer id and the buffer's page, built by the same kind→page mapping the
/// workspace registry uses. Design-free — a raw `View` has no [Directionality]
/// ancestor, so this page owns one.
class BufferWindowPage extends StatelessWidget {
  const BufferWindowPage({
    super.key,
    required this.bufferId,
    required this.title,
    required this.contentBuilder,
  });

  final BufferId bufferId;
  final String title;
  final Widget Function(BuildContext context, BufferId bufferId) contentBuilder;

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            KitHeader(title: title),
            Expanded(child: contentBuilder(context, bufferId)),
          ],
        ),
      );
}
