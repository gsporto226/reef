import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:reef/features/hibernation/_interfaces/hibernation_store.dart';
import 'package:reef/features/hibernation/_implementations/lifecycle.dart';
import 'package:reef/features/windowing/_implementations/windowing_root.dart';

/// Turns a restorable value into JSON and back. [decode] throws on JSON it
/// cannot read; the bucket is then dropped to defaults.
class RestorableCodec<T> {
  const RestorableCodec({required this.encode, required this.decode});

  final Object? Function(T value) encode;
  final T Function(Object? json) decode;
}

/// A typed value restored from a [ReefRestorationBucket] when registered there,
/// and written back when it changes. Like Flutter's `RestorableValue`.
class ReefRestorableValue<T> extends ChangeNotifier
    implements ValueListenable<T> {
  /// Without [codec], the value is stored as is and must be JSON already.
  ReefRestorableValue(this.defaultValue, {RestorableCodec<T>? codec})
    : codec =
          codec ??
          RestorableCodec<T>(encode: (v) => v, decode: (json) => json as T),
      _value = defaultValue;

  /// The value without saved data, or after its bucket was dropped.
  final T defaultValue;
  final RestorableCodec<T> codec;

  T _value;
  ReefRestorationBucket? _bucket;
  String? _key;

  @override
  T get value => _value;
  set value(T value) {
    if (value == _value) return;
    _value = value;
    _bucket?._write(_key!, codec.encode(value));
    notifyListeners();
  }

  Object? _resetToDefault() {
    _restore(defaultValue);
    return codec.encode(defaultValue);
  }

  void _restore(T value) {
    if (value == _value) return;
    _value = value;
    notifyListeners();
  }
}

/// A node of the restoration tree (ADR 0010): JSON values by key and child
/// buckets by id. Like Flutter's `RestorationBucket`.
class ReefRestorationBucket {
  ReefRestorationBucket._(this.id, this._parent, Object? json) {
    if (json case {'values': final Map values, 'children': final Map kids}) {
      _values.addAll(values.cast<String, Object?>());
      for (final MapEntry(:key, :value) in kids.entries) {
        _children[key as String] = ReefRestorationBucket._(key, this, value);
      }
    }
  }

  final String id;
  final ReefRestorationBucket? _parent;
  final _values = <String, Object?>{};
  final _children = <String, ReefRestorationBucket>{};
  final _registered = <String, ReefRestorableValue<dynamic>>{};

  /// The child bucket [id], with its saved data; the same bucket each time.
  ReefRestorationBucket claimChild(String id) =>
      _children[id] ??= ReefRestorationBucket._(id, this, null);

  /// Restores [value] from the saved data under [key] (without any, writes
  /// a value changed from its default), then writes it back on every change. A value that
  /// fails to decode drops this bucket's values to their defaults.
  void register<T>(String key, ReefRestorableValue<T> value) {
    value
      .._bucket = this
      .._key = key;
    _registered[key] = value;
    if (!_values.containsKey(key)) {
      if (value.value != value.defaultValue) {
        _write(key, value.codec.encode(value.value));
      }
      return;
    }
    try {
      value._restore(value.codec.decode(_values[key]));
    } catch (_) {
      _drop();
    }
  }

  /// What registering [value] under [key] would restore, without
  /// registering it: the saved value decoded with [value]'s codec, or its
  /// default when nothing is saved or it fails to decode. Reads a setting
  /// before the controller restores the doc.
  T peek<T>(String key, ReefRestorableValue<T> value) {
    if (!_values.containsKey(key)) return value.defaultValue;
    try {
      return value.codec.decode(_values[key]);
    } catch (_) {
      return value.defaultValue;
    }
  }

  /// The saved JSON under [key], or null.
  Object? read(String key) => _values[key];

  /// Stops writing the value under [key]; its saved data is kept.
  void unregister(String key) => _registered.remove(key)?._bucket = null;

  void _drop() {
    _values.clear();
    for (final MapEntry(:key, :value) in _registered.entries) {
      _values[key] = value._resetToDefault();
    }
    _changed();
  }

  void _write(String key, Object? json) {
    _values[key] = json;
    _changed();
  }

  void _changed() => _parent?._changed();

  Map<String, Object?> toJson() => {
    'values': {..._values},
    'children': {for (final e in _children.entries) e.key: e.value.toJson()},
  };
}

/// The root bucket, loaded from [store] at construction and saved there
/// at most once per frame.
class ReefRootRestorationBucket extends ReefRestorationBucket {
  ReefRootRestorationBucket(this._store)
    : super._('', null, _store?.load(restorationHibernationKey));

  final HibernationStore? _store;
  bool _scheduled = false;

  @override
  void _changed() {
    if (_store == null || _scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) => flush())
      ..ensureVisualUpdate();
  }

  /// Saves now instead of after the frame.
  void flush() {
    _scheduled = false;
    _store?.save(restorationHibernationKey, toJson());
  }
}

/// Claims the child bucket [restorationId] of the controller's root under
/// the nearest [WindowingRoot], and calls [restoreState] once to register
/// the state's [ReefRestorableValue]s. Like Flutter's `RestorationMixin`.
mixin ReefRestorationMixin<S extends StatefulWidget> on State<S> {
  /// The id of this state's bucket. Saved data: renaming it drops the state.
  String get restorationId;

  /// Registers this state's values with [registerForRestoration].
  void restoreState();

  ReefRestorationBucket? _bucket;
  final _keys = <String>[];

  /// The claimed bucket, from [didChangeDependencies] on.
  ReefRestorationBucket get bucket => _bucket!;

  /// Registers [value] under [key] in [bucket], restoring it.
  void registerForRestoration<T>(ReefRestorableValue<T> value, String key) {
    _keys.add(key);
    bucket.register(key, value);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bucket != null) return;
    _bucket = WindowingScope.of(context).controller.restoration
        .claimChild(restorationId);
    restoreState();
  }

  @override
  void dispose() {
    _keys.forEach(_bucket!.unregister);
    super.dispose();
  }
}
