import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

/// Windowing widget tests run on an expanded (desktop) screen unless a test
/// resizes the view; 800px wide would be a medium screen.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(1000, 600) * view.devicePixelRatio;
  });
  await testMain();
}
