// Reads a platform window's screen position, which Flutter's windowing API
// does not expose: on Windows, through the window handle and user32.
// ignore_for_file: invalid_use_of_internal_member, implementation_imports

import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:ui' show Offset;

import 'package:ffi/ffi.dart' show calloc;
import 'package:flutter/src/widgets/_window_win32.dart'
    show BaseWindowControllerWin32;

typedef _ClientToScreenC = Int32 Function(Pointer<Void>, Pointer<Int32>);
typedef _ClientToScreen = int Function(Pointer<Void>, Pointer<Int32>);

final _clientToScreen = Platform.isWindows
    ? DynamicLibrary.open('user32.dll')
        .lookupFunction<_ClientToScreenC, _ClientToScreen>('ClientToScreen')
    : null;

/// The screen position, in physical pixels, of the top-left of [window]'s
/// client area; null off Windows (ponytail: macOS and Linux need their own
/// lookups) or when the call fails.
Offset? clientOrigin(Object window) {
  final clientToScreen = _clientToScreen;
  if (clientToScreen == null || window is! BaseWindowControllerWin32) {
    return null;
  }
  final point = calloc<Int32>(2); // POINT {0, 0}
  try {
    if (clientToScreen(window.windowHandle, point) == 0) return null;
    return Offset(point[0].toDouble(), point[1].toDouble());
  } finally {
    calloc.free(point);
  }
}
