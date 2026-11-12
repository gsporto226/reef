import 'package:uuid/uuid.dart';

/// Identity of a materialized buffer (§4.4, §10 of `docs/blueprint.md`).
///
/// A buffer is one keyed instance of a page's state (viewmodel + model + UI
/// objects). The id is the persistence/reattachment key: hibernation records,
/// logs and (later) cross-window sync payloads are keyed by it.
///
/// Extension type over [String] — zero-cost wrapper, equality is string
/// equality. Generated with uuid v7: unique and time-sortable.
extension type BufferId._(String value) {
  /// Creates a buffer id from a fixed string — tests, hibernation
  /// reattachment, deterministic scenarios.
  const BufferId.manual(String manual) : value = manual;

  /// The `kind:token` id a [LinkTable] maps to and from a path.
  const BufferId.of(String kind, String token) : value = '$kind:$token';

  /// Generates a fresh buffer id (uuid v7).
  static BufferId generate() => BufferId._(const Uuid().v7());

  /// Namespaces a child scope under this buffer.
  BufferId sub(String sub) => BufferId.manual('$value.$sub');

  /// The raw id string.
  String get id => value;

  /// The part before the first `:`; null for an id that isn't `kind:token`.
  String? get kind => switch (value.indexOf(':')) {
    -1 => null,
    final i => value.substring(0, i),
  };

  /// The part after the first `:`; null for an id that isn't `kind:token`.
  String? get token => switch (value.indexOf(':')) {
    -1 => null,
    final i => value.substring(i + 1),
  };
}
