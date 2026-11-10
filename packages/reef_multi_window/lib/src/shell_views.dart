// The only import of Flutter's experimental windowing API in reef
// (flutter/flutter#30701): `@internal`, master channel only, enabled per
// invocation with `FLUTTER_WINDOWING=true`. None of its types leave this file.
// ignore_for_file: invalid_use_of_internal_member, implementation_imports

import 'package:flutter/src/foundation/_features.dart' show isWindowingEnabled;
import 'package:flutter/src/widgets/_window.dart' as windowing;
import 'package:flutter/widgets.dart';
import 'package:listenable_plus/listenable_plus.dart';
import 'package:reef/reef.dart';
import 'package:reef_fp/result.dart';
import 'package:reef_fp/unit.dart';

/// Draws shell [shellId]'s surface: app widget, theme, chrome.
typedef ShellBuilder = Widget Function(BuildContext context, ShellId shellId);

/// A [ShellPlatform] over Flutter's windowing API: one platform window per
/// open shell. Notifies when the set of open shells changes.
class RealShellPlatform extends ChangeNotifier implements ShellPlatform {
  RealShellPlatform({this.title, this.size = const Size(1280, 800)});

  /// Title of new shells.
  String? title;

  /// Initial content size of new shells.
  Size size;

  final _windows = <ShellId, windowing.WindowController>{};

  /// The windowing feature flag.
  @override
  bool get isSupported => isWindowingEnabled;

  @override
  Future<Result<ShellError, Unit>> open(ShellId id) async {
    try {
      _windows[id] = windowing.WindowController(size: size, title: title);
    } on UnsupportedError catch (e) {
      return Err(ShellError(ShellErrorKind.platformFailure, cause: e));
    }
    notifyListeners();
    return const Ok(Unit.unit);
  }

  @override
  void close(ShellId id) {
    final window = _windows.remove(id);
    if (window == null) return;
    notifyListeners();
    window.destroy();
  }
}

/// The root widget of a multi-shell app: one platform view per open shell of
/// [platform], each drawn by [shellBuilder]. Shells already in the doc get a
/// real shell at mount. Without multi-shell support it draws the doc's
/// focused shell inline in the implicit view. Place it under a single
/// provider scope and [WindowingRoot] so every view shares them.
class ShellViews extends StatefulWidget {
  const ShellViews({
    super.key,
    required this.controller,
    required this.platform,
    required this.shellBuilder,
  });

  final WindowingController controller;
  final RealShellPlatform platform;
  final ShellBuilder shellBuilder;

  @override
  State<ShellViews> createState() => _ShellViewsState();
}

class _ShellViewsState extends State<ShellViews> {
  late final _mapped = MappedValueListenable(
    widget.controller.doc.value.focusedShellId,
    mapper: (WindowingDoc doc) => doc.focusedShellId,
    source: widget.controller.doc,
  );
  late final _focused = DistinctValueNotifier(_mapped.value, source: _mapped);

  @override
  void initState() {
    super.initState();
    final platform = widget.platform;
    if (!platform.isSupported) return;
    for (final id in widget.controller.doc.value.shells.keys) {
      if (!platform._windows.containsKey(id)) platform.open(id);
    }
  }

  @override
  void dispose() {
    _focused.dispose();
    _mapped.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ShellViews(:platform, :shellBuilder) = widget;
    if (!platform.isSupported) {
      return View(
        view: WidgetsBinding.instance.platformDispatcher.implicitView!,
        child: ValueListenableBuilder(
          valueListenable: _focused,
          builder: (context, shellId, _) => shellBuilder(context, shellId),
        ),
      );
    }
    return ListenableBuilder(
      listenable: platform,
      builder: (context, _) => ViewCollection(
        views: [
          for (final MapEntry(key: id, value: window)
              in platform._windows.entries)
            windowing.Window(
              key: ObjectKey(id),
              controller: window,
              child: Builder(builder: (context) => shellBuilder(context, id)),
            ),
        ],
      ),
    );
  }
}
