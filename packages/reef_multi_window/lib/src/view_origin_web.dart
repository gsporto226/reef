import 'dart:ui' show Offset;

/// No platform windows on the web.
Offset? clientOrigin(Object window) => null;
