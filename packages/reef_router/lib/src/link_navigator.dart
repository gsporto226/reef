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
      {bool newShell = false, bool? fresh, WindowId? window}) {
    final (:buffer, :arguments) = tree.linkOf(route, fresh: fresh);
    // A fresh buffer is never open: go pushes into the focused window (D3).
    if (verb == LinkVerb.go && tree.isFresh(buffer)) verb = LinkVerb.push;
    return controller.openLink(buffer,
        arguments: arguments, newShell: newShell, verb: verb, window: window);
  }

  /// Opens [route] as the link policy decides (ADR 0004 D22); with
  /// [newShell], in a new shell where supported. [fresh] overrides the
  /// link's freshness here and in the other verbs.
  Future<void> go(R route, {bool newShell = false, bool? fresh}) =>
      _open(route, LinkVerb.go, newShell: newShell, fresh: fresh);

  // The history verbs act on [window], or the focused window when null;
  // focus stays as it is. Link policy and guards apply either way.

  /// Pushes [route] onto [window]; go without one.
  void push(R route, {bool? fresh, WindowId? window}) =>
      _open(route, LinkVerb.push, fresh: fresh, window: window);

  /// Replaces [window]'s entry with [route]; go without one.
  void replace(R route, {bool? fresh, WindowId? window}) =>
      _open(route, LinkVerb.replace, fresh: fresh, window: window);

  /// Pushes the parent of [window]'s route onto it. Returns false at a
  /// root route or without the window.
  bool up({WindowId? window}) {
    final state = _window(window);
    if (state == null) return false;
    final HistoryEntry(:buffer, :arguments) = state.history.current;
    final parent = tree.parentOf(tree.routeOfBuffer(buffer, arguments));
    if (parent == null) return false;
    push(parent, window: window);
    return true;
  }

  /// Steps [window] back. Returns false with nothing to go back to or
  /// without the window.
  bool back({WindowId? window}) => _step(window, (h) => h.back, PopBuffer.new);

  /// Steps [window] forward; false as [back].
  bool forward({WindowId? window}) =>
      _step(window, (h) => h.forward, NavigateForward.new);

  WindowState? _window(WindowId? window) {
    final doc = controller.doc.value;
    return doc.windows[window ?? doc.activeWindowId];
  }

  bool _step(WindowId? window, List<HistoryEntry> Function(BufferHistory) side,
      WindowingCommand Function(WindowId) command) {
    final id = window ?? controller.doc.value.activeWindowId;
    final state = _window(id);
    if (state == null || side(state.history).isEmpty) return false;
    controller.dispatch(command(id!));
    return true;
  }

  /// Opens [route] in a new tab of the focused shell.
  void openInNewTab(R route, {bool? fresh}) =>
      _dispatch(tree.linkOf(route, fresh: fresh), newTabOpenPolicy);

  /// Opens [route] in a new window beside the focused one.
  void openInSplit(R route, {bool? fresh}) =>
      _dispatch(tree.linkOf(route, fresh: fresh), splitBesideOpenPolicy);

  /// Opens [route] in a new platform window (a new shell) where pop-out is
  /// supported. Without pop-out, or when the shell fails to open, it opens
  /// in a new tab of the focused shell, the nearest in-app equivalent.
  Future<void> openInNewWindow(R route, {bool? fresh}) async {
    final link = tree.linkOf(route, fresh: fresh);
    if (controller.capabilities.canPopOut &&
        (await controller.openShell(
          buffer: link.buffer,
          arguments: link.arguments,
        )).isOk) {
      return;
    }
    _dispatch(link, newTabOpenPolicy);
  }

  void _dispatch(ResolvedLink link, WindowingOpenPolicy policy) =>
      controller.dispatchAll(policy(controller.doc.value, link.buffer,
          arguments: link.arguments));
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

  Future<void> go(BuildContext context, {bool newShell = false, bool? fresh}) =>
      LinkNavigator.of<R>(context).go(_self, newShell: newShell, fresh: fresh);

  void push(BuildContext context, {bool? fresh}) =>
      LinkNavigator.of<R>(context).push(_self, fresh: fresh);

  void replace(BuildContext context, {bool? fresh}) =>
      LinkNavigator.of<R>(context).replace(_self, fresh: fresh);

  /// Pushes this route's parent; false at a root route.
  bool up(BuildContext context) {
    final nav = LinkNavigator.of<R>(context);
    final parent = nav.tree.parentOf(_self);
    if (parent == null) return false;
    nav.push(parent);
    return true;
  }

  void openInNewTab(BuildContext context, {bool? fresh}) =>
      LinkNavigator.of<R>(context).openInNewTab(_self, fresh: fresh);

  void openInSplit(BuildContext context, {bool? fresh}) =>
      LinkNavigator.of<R>(context).openInSplit(_self, fresh: fresh);

  Future<void> openInNewWindow(BuildContext context, {bool? fresh}) =>
      LinkNavigator.of<R>(context).openInNewWindow(_self, fresh: fresh);
}
