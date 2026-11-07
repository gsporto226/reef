import 'package:uuid/uuid.dart';

// Windowing ids follow the `BufferId` recipe: extension types over [String],
// uuid v7 generation, a `manual` constructor for tests and restoration.

/// Identity of a shell (a platform window).
extension type ShellId._(String value) {
  /// Creates a shell id from a fixed string: tests, restoration.
  const ShellId.manual(String manual) : value = manual;

  /// Generates a fresh shell id (uuid v7).
  static ShellId generate() => ShellId._(const Uuid().v7());

  /// The raw id string.
  String get id => value;
}

/// Identity of a tab.
extension type TabId._(String value) {
  /// Creates a tab id from a fixed string: tests, restoration.
  const TabId.manual(String manual) : value = manual;

  /// Generates a fresh tab id (uuid v7).
  static TabId generate() => TabId._(const Uuid().v7());

  /// The raw id string.
  String get id => value;
}

/// Identity of a window (a buffer viewport).
extension type WindowId._(String value) {
  /// Creates a window id from a fixed string: tests, restoration.
  const WindowId.manual(String manual) : value = manual;

  /// Generates a fresh window id (uuid v7).
  static WindowId generate() => WindowId._(const Uuid().v7());

  /// The raw id string.
  String get id => value;
}
