// The experimental multi-window entrypoint (blueprint §10.4 spike). One
// ProviderScope above the window manager — every view's tree descends through
// it, so buffers are plain shared state across OS windows.
//
// Run (master channel; do NOT use `flutter config --enable-windowing` — the
// global flag breaks `flutter test` on Windows, the Win32 owner FFI-initializes
// inside flutter_tester):
//   $env:FLUTTER_WINDOWING = "true"
//   fvm flutter run -t lib/main_windowed.dart -d windows
//
// The windowing API is experimental (flutter/flutter#30701): `@internal`,
// main-channel only.
// ignore_for_file: invalid_use_of_internal_member, implementation_imports

import 'package:flutter/src/widgets/_window.dart' as windowing;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reef_example/main.dart';

void main() {
  // The initialWindows list is evaluated before runWidget initializes the
  // binding — and WindowController's factory (unlike .shrinkWrap) does not
  // ensureInitialized itself, so this must come first.
  WidgetsFlutterBinding.ensureInitialized();
  runWidget(
    ProviderScope(
      child: windowing.WindowManager(
        initialWindows: [
          windowing.WindowEntry(
            controller: windowing.WindowController(
              size: const Size(1280, 800),
              title: 'Reef example',
            ),
            builder: (_) => const ReefExampleShellApp(),
          ),
        ],
      ),
    ),
  );
}
