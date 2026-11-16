// The browser's entrypoint: the real platform wiring no test reaches,
// outside the coverage gate (ADR 0014). `flutter run -t lib/entry.dart`.
// ignore_for_file: experimental_member_use
import 'package:flutter/widgets.dart';
import 'package:reef_multi_window/reef_multi_window.dart';

import 'file_store.dart';
import 'main.dart';

/// Launched with a URL (the default browser), it opens on top of the
/// restored session. A dragged-out tab is a real window with
/// `FLUTTER_WINDOWING=true` (master channel); without it, one window.
void main(List<String> args) {
  final platform = RealShellPlatform(title: 'Browser');
  runWidget(
    BrowserApp(
      store: JsonFileHibernationStore(sessionFile()),
      launchArg: args.firstOrNull,
      platform: platform,
      views: (controller, shells) => ShellViews(
        controller: controller,
        platform: platform,
        shellBuilder: shells,
      ),
    ),
  );
}
