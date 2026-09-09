/// A type with exactly one value — used to signal "no meaningful payload".
class Unit {
  const Unit();

  /// The single [Unit] instance.
  static const unit = Unit();

  @override
  bool operator ==(Object other) => identical(this, other) || other is Unit;

  @override
  int get hashCode => 0x0517;

  @override
  String toString() => 'unit';
}
