/// Barrel of `reef` — MVVM framework core: ValueListenable-first pages,
/// models and viewmodels.
library;

export 'package:reef/features/builders/_implementations/async_result_builders.dart';
export 'package:reef/features/formularium_bridge/_implementations/result_validation.dart';
export 'package:reef/features/hibernation/_implementations/buffer_registry.dart';
export 'package:reef/features/hibernation/_implementations/lifecycle.dart';
export 'package:reef/features/hibernation/_interfaces/hibernation_store.dart';
export 'package:reef/features/operation/_implementations/operation.dart';
export 'package:reef/features/page/_implementations/reef_buffer_scope.dart';
export 'package:reef/features/page/_implementations/reef_window.dart';
export 'package:reef/features/page_identity/_implementations/buffer_id.dart';
export 'package:reef/features/page_identity/_implementations/reef_scope.dart';
export 'package:reef/features/page_identity/_providers/reef_scope_provider.dart';
export 'package:reef/features/responsive/_implementations/screen_type_layout.dart';
export 'package:reef/features/view_model/_implementations/view_model.dart';
export 'package:reef/features/windowing/_implementations/windowing_controller.dart';
export 'package:reef/features/windowing/_implementations/windowing_doc.dart';
export 'package:reef/features/windowing/_implementations/windowing_ids.dart';
export 'package:reef/features/windowing/_implementations/windowing_root.dart';
export 'package:reef/features/workspace/_implementations/split_tree.dart';
export 'package:reef/features/workspace/_implementations/split_tree_controller.dart';
export 'package:reef/features/workspace/_implementations/split_workspace.dart';
export 'package:reef/features/undo/_implementations/undo_controller.dart';
export 'package:reef/features/undo/_implementations/buffer_undo_host.dart';
