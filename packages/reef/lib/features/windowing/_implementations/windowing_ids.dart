import 'package:uuid/uuid.dart';

// Windowing ids follow the `BufferId` recipe: extension types over [String],
// uuid v7 generation, a `manual` constructor for tests and restoration.

/// Identity of a shell (a platform window).
extension type ShellId._(String value) {
  const ShellId.manual(String manual) : value = manual;
  static ShellId generate() => ShellId._(const Uuid().v7());
  String get id => value;
}

/// Identity of a tab.
extension type TabId._(String value) {
  const TabId.manual(String manual) : value = manual;
  static TabId generate() => TabId._(const Uuid().v7());
  String get id => value;
}

/// Identity of a window (a buffer viewport).
extension type WindowId._(String value) {
  const WindowId.manual(String manual) : value = manual;
  static WindowId generate() => WindowId._(const Uuid().v7());
  String get id => value;
}
