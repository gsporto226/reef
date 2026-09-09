import 'dart:async';

/// Returns [value] unchanged.
T identity<T>(T value) => value;

/// Returns [value] unchanged, async.
FutureOr<T> identityAsync<T>(FutureOr<T> value) async => value;
