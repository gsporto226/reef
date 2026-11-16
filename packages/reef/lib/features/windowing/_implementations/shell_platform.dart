import 'dart:ui' show FlutterView, Offset;

import 'package:meta/meta.dart' show experimental;
import 'package:reef/features/windowing/_implementations/windowing_ids.dart';
import 'package:reef_fp/result.dart';
import 'package:reef_fp/unit.dart';

/// Opens and closes platform shells (spec §7). Reef core never imports a
/// platform windowing API; an adapter implements this.
abstract interface class ShellPlatform {
  /// Whether this platform can open more than one shell.
  bool get isSupported;

  Future<Result<ShellError, Unit>> open(ShellId id);

  /// Best-effort.
  void close(ShellId id);

  /// Where [view]'s top-left sits on the screen, in physical pixels; null
  /// when unknown. A dock drag crosses into another view only when both
  /// views' origins are known (ADR 0012). Experimental (ADR 0013).
  @experimental
  Offset? viewOrigin(FlutterView view);
}

enum ShellErrorKind { unsupported, refused, platformFailure }

/// Why a shell intent failed, with an optional platform [cause].
class ShellError {
  const ShellError(this.kind, {this.cause});

  final ShellErrorKind kind;
  final Object? cause;

  @override
  bool operator ==(Object other) =>
      other is ShellError && other.kind == kind && other.cause == cause;

  @override
  int get hashCode => Object.hash(kind, cause);

  @override
  String toString() => 'ShellError(${kind.name}, $cause)';
}

/// What the controller's platform can do.
class ShellCapabilities {
  const ShellCapabilities({required this.canPopOut});

  final bool canPopOut;
}

/// A [ShellPlatform] for tests: records [opened] and [closed] ids, and fails
/// the next open on demand.
class FakeShellPlatform implements ShellPlatform {
  FakeShellPlatform({this.isSupported = true});

  @override
  bool isSupported;

  /// The screen origins [viewOrigin] reports; a view not listed sits at
  /// zero, so shells drawn side by side in one test view share a screen.
  @experimental
  final viewOrigins = <FlutterView, Offset>{};

  final opened = <ShellId>[];
  final closed = <ShellId>[];
  ShellError? _failure;

  /// Makes the next [open] return [error] (and not record the id).
  void failNextOpen(ShellError error) => _failure = error;

  @override
  Future<Result<ShellError, Unit>> open(ShellId id) async {
    if (_failure case final error?) {
      _failure = null;
      return Err(error);
    }
    opened.add(id);
    return const Ok(Unit.unit);
  }

  @override
  void close(ShellId id) => closed.add(id);

  @override
  @experimental
  Offset? viewOrigin(FlutterView view) => viewOrigins[view] ?? Offset.zero;
}
