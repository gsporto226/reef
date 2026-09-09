/// Throws an [AssertionError]. Use where a value of type [Never] is needed.
Never never([String? msg]) {
  throw AssertionError(msg);
}

/// Throws an [AssertionError], ignoring the dummy [T] value.
Never never1<T>(T _, [String? msg]) {
  throw AssertionError(msg);
}
