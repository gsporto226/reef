import 'package:flutter/widgets.dart';
import 'package:reef/reef.dart';
import 'package:reef_router/src/links.dart';

/// Navigates with route values of type [R]: each verb resolves the route
/// through [tree] and dispatches the windowing commands for it.
class LinkNavigator<R> {
  LinkNavigator(this.tree, this.controller);

  final LinkTree<R> tree;
  final WindowingController controller;

  /// The navigator of the nearest [LinkScope] of [R].
  static LinkNavigator<R> of<R>(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<LinkScope<R>>();
    if (scope == null) throw StateError('No LinkScope<$R> above $context');
    return scope.navigator;
  }

  Future<void> _open(R route, LinkVerb verb,
      {bool newShell = false, bool? fresh}) {
    final (:buffer, :arguments) = tree.linkOf(route, fresh: fresh);
    // A fresh buffer is never open: go pushes into the focused window (D3).
    if (verb == LinkVerb.go && tree.isFresh(buffer)) verb = LinkVerb.push;
    return controller.openLink(buffer,
        arguments: arguments, newShell: newShell, verb: verb);
  }

  /// Opens [route] as the link policy decides (ADR 0004 D22); with
  /// [newShell], in a new shell where supported. [fresh] overrides the
  /// link's freshness here and in the other verbs.
  Future<void> go(R route, {bool newShell = false, bool? fresh}) =>
      _open(route, LinkVerb.go, newShell: newShell, fresh: fresh);

  /// Pushes [route] onto the focused window; go without one.
  void push(R route, {bool? fresh}) =>
      _open(route, LinkVerb.push, fresh: fresh);

  /// Replaces the focused window's entry with [route]; go without one.
  void replace(R route, {bool? fresh}) =>
      _open(route, LinkVerb.replace, fresh: fresh);

  /// Pushes the parent of the focused window's route. Returns false at a
  /// root route or without a focused window.
  bool up() {
    final doc = controller.doc.value;
    final window = doc.activeWindowId;
    if (window == null) return false;
    final HistoryEntry(:buffer, :arguments) =
        doc.windows[window]!.history.current;
    final parent = tree.parentOf(tree.routeOfBuffer(buffer, arguments));
    if (parent == null) return false;
    push(parent);
    return true;
  }

  /// Opens [route] in a new tab of the focused shell.
  void openInNewTab(R route) => _dispatch(route, newTabOpenPolicy);

  /// Opens [route] in a new window beside the focused one.
  void openInSplit(R route) => _dispatch(route, splitBesideOpenPolicy);

  void _dispatch(R route, WindowingOpenPolicy policy) {
    final (:buffer, :arguments) = tree.linkOf(route);
    controller.dispatchAll(
        policy(controller.doc.value, buffer, arguments: arguments));
  }
}

/// Gives the widgets below it [navigator], read by [LinkNavigator.of].
class LinkScope<R> extends InheritedWidget {
  const LinkScope({super.key, required this.navigator, required super.child});

  final LinkNavigator<R> navigator;

  @override
  bool updateShouldNotify(LinkScope<R> oldWidget) =>
      navigator != oldWidget.navigator;
}

/// The verbs on a route value; mix into the app's sealed route base [R].
mixin LinkVerbs<R> {
  R get _self => this as R;

  Future<void> go(BuildContext context, {bool newShell = false}) =>
      LinkNavigator.of<R>(context).go(_self, newShell: newShell);

  void push(BuildContext context) => LinkNavigator.of<R>(context).push(_self);

  void replace(BuildContext context) =>
      LinkNavigator.of<R>(context).replace(_self);

  void openInNewTab(BuildContext context) =>
      LinkNavigator.of<R>(context).openInNewTab(_self);

  void openInSplit(BuildContext context) =>
      LinkNavigator.of<R>(context).openInSplit(_self);
}
