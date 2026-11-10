import 'package:flutter_riverpod/flutter_riverpod.dart' show Provider;
import 'package:reef/features/undo/_implementations/buffer_undo_host.dart';
import 'package:reef/features/undo/_implementations/undo_controller.dart';

/// The app's one undo timeline (spec §4), keepAlive.
final undoControllerProvider = Provider((ref) => UndoController());

/// Buffer content undo on [undoControllerProvider], keepAlive.
final bufferUndoHostProvider =
    Provider((ref) => BufferUndoHost(ref.watch(undoControllerProvider)));
