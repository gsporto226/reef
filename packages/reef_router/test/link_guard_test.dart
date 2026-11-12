import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reef/reef.dart';
import 'package:reef_router/reef_router.dart';

import 'nesting_routes.dart';

/// The app's interface; the fake below stands in for any container.
abstract interface class Session {
  bool get signedIn;
}

class FakeSession implements Session {
  FakeSession({this.signedIn = false});
  @override
  bool signedIn;
}

const login = FilesRoute(['login']);
const project = ProjectRoute('p1');
const task = TaskRoute(project, 't9');

/// Sends signed-out users to [login]; a guard class typed by its route.
final class SignedIn extends LinkGuard<AppRoute, AppRoute, Session> {
  const SignedIn();
  @override
  GuardDecision call(AppRoute route, AppRoute destination, Session session) =>
      session.signedIn ? const GuardDecision.allow() : const GuardDecision.redirect(login);
}

LinkTree<AppRoute> treeWith({
  List<TreeGuard<AppRoute>> guards = const [],
  LinkNode<AppRoute, Never>? projects,
  LinkNode<AppRoute, Never>? files,
  int redirectLimit = 5,
}) => LinkTree<AppRoute>(
  [
    NotFoundRoute.link,
    projects ??
        ProjectRoute.link.children([TaskRoute.link, ProjectMissingRoute.link]),
    files ?? FilesRoute.link.children([FileEditRoute.link]),
  ],
  guards: guards,
  redirectLimit: redirectLimit,
);

void main() {
  group('the guard chain', () {
    test('runs tree-wide, then ancestors from the root with their own '
        'value, then the route\'s own, each with the destination', () {
      final calls = <String>[];
      GuardDecision Function(R, AppRoute, Object?) log<R>(String name) =>
          (route, destination, _) {
            calls.add('$name $route -> $destination');
            return const GuardDecision.allow();
          };
      final tree = treeWith(
        guards: [TreeGuard.of(log<AppRoute>('tree'))],
        projects: ProjectRoute.link
            .children([TaskRoute.link.guard(log<TaskRoute>('task'))])
            .guard(log<ProjectRoute>('project')),
      );
      expect(tree.bind(null).check(task), const GuardDecision.allow());
      expect(calls, [
        'tree $task -> $task',
        'project $project -> $task',
        'task $task -> $task',
      ]);
    });

    test('the first non-allow decision wins', () {
      var ownRan = false;
      final tree = treeWith(
        projects: ProjectRoute.link
            .children([
              TaskRoute.link.guard((TaskRoute _, AppRoute _, Object? _) {
                ownRan = true;
                return const GuardDecision.allow();
              }),
            ])
            .guard(
              (ProjectRoute _, AppRoute _, Object? _) =>
                  const GuardDecision.redirect(login),
            ),
      );
      final decision = tree.bind(null).check(task);
      expect(decision, const GuardDecision.redirect(login));
      expect(ownRan, isFalse);
    });

    test('a guard class runs against a fake environment, no container', () {
      final tree = treeWith(guards: [TreeGuard.of(const SignedIn().call)]);
      final session = FakeSession();
      // login itself is guarded too, so exempt it to reach a stable target.
      final exempt = treeWith(
        guards: [
          TreeGuard.of((AppRoute r, AppRoute d, Session s) =>
              r == login ? const GuardDecision.allow() : const SignedIn()(r, d, s)),
        ],
      );
      expect(exempt.bind(session).check(task),
          const GuardDecision.redirect(login));
      session.signedIn = true;
      expect(tree.bind(session).check(task), const GuardDecision.allow());
    });

    test('a redirect target runs its own guards, and chains', () {
      final tree = treeWith(
        projects: ProjectRoute.link
            .children([TaskRoute.link])
            .guard(
              (ProjectRoute _, AppRoute _, Object? _) =>
                  const GuardDecision.redirect(FilesRoute(['a'])),
            ),
        files: FilesRoute.link
            .children([FileEditRoute.link])
            .guard(
              (FilesRoute r, AppRoute _, Object? _) => r == login
                  ? const GuardDecision.allow()
                  : const GuardDecision.redirect(login),
            ),
      );
      expect(tree.bind(null).check(task), const GuardDecision.redirect(login));
    });

    test('a redirect loop fails past the limit, naming the guard', () {
      final tree = treeWith(
        redirectLimit: 3,
        files: FilesRoute.link
            .children([FileEditRoute.link])
            .guard(
              (FilesRoute r, AppRoute _, Object? _) =>
                  GuardDecision.redirect(FilesRoute(['${r.path.length}', ...r.path])),
              name: 'Bouncer',
            ),
      );
      expect(
        () => tree.bind(null).check(login),
        throwsA(isA<StateError>().having((e) => e.message, 'message',
            allOf(contains('Bouncer'), contains('3')))),
      );
    });
  });

  group('bind', () {
    test('fails when the environment is not the guard\'s environment type', () {
      final tree = treeWith(guards: [TreeGuard.of(const SignedIn().call, name: 'SignedIn')]);
      expect(
        () => tree.bind(Object()),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', allOf(contains('SignedIn'), contains('Session')))),
      );
      expect(tree.bind(FakeSession()), isA<BoundLinkTree<AppRoute>>());
    });

    test('fails when a route is not the guard\'s destination type', () {
      final tree = treeWith(
        projects: ProjectRoute.link
            .children([TaskRoute.link])
            .guard((ProjectRoute _, TaskRoute _, Object? _) =>
                const GuardDecision.allow()),
      );
      expect(
        () => tree.bind(null),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('TaskRoute'))),
      );
    });
  });

  group('the interceptor', () {
    late WindowingController controller;
    late FakeSession session;
    final tree = treeWith(
      projects: ProjectRoute.link
          .children([TaskRoute.link, ProjectMissingRoute.link])
          .guard(
            (ProjectRoute _, AppRoute _, Session s) => s.signedIn
                ? const GuardDecision.allow()
                : const GuardDecision.redirect(login),
          ),
      files: FilesRoute.link
          .children([FileEditRoute.link]),
    );
    final home = tree.linkOf(const FilesRoute(['home']));
    const w = WindowId.manual('w');

    setUp(() {
      session = FakeSession();
      controller = WindowingController(
        initial: () {
          final d = WindowingDoc.initial();
          return NewTab(
            shellId: d.focusedShellId,
            tabId: const TabId.manual('t'),
            buffer: (w, home.buffer),
          ).apply(d);
        },
        interceptor: tree.bind(session).interceptor,
      );
    });
    tearDown(() => controller.dispose());

    BufferHistory history() => controller.doc.value.windows[w]!.history;
    HistoryEntry entryOf(AppRoute r) {
      final (:buffer, :arguments) = tree.linkOf(r);
      return HistoryEntry(buffer, arguments: arguments);
    }

    void push(AppRoute r) {
      final (:buffer, :arguments) = tree.linkOf(r);
      controller.dispatch(PushBuffer(w, buffer, arguments: arguments));
    }

    test('a redirect pushes the target in place of the guarded entry', () {
      push(task);
      expect(history().current, entryOf(login));
      expect(history().back, [entryOf(const FilesRoute(['home']))]);
    });

    test('back onto an entry that now redirects replaces it', () {
      session.signedIn = true;
      push(task);
      push(const FilesRoute(['b']));
      session.signedIn = false;
      controller.dispatch(const PopBuffer(w));
      expect(history().current, entryOf(login));
      expect(history().back, [entryOf(const FilesRoute(['home']))]);
      expect(history().forward, [entryOf(const FilesRoute(['b']))]);
    });

    test('buffers outside the tree pass', () {
      controller.dispatch(PushBuffer(w, const BufferId.manual('compose:1')));
      expect(history().current.buffer, const BufferId.manual('compose:1'));
    });
  });

  group('the re-check (D8)', () {
    final tree = treeWith(
      projects: ProjectRoute.link
          .children([TaskRoute.link, ProjectMissingRoute.link])
          .guard(
            (ProjectRoute _, AppRoute _, Session s) => s.signedIn
                ? const GuardDecision.allow()
                : const GuardDecision.redirect(login),
          ),
    );
    final home = tree.linkOf(const FilesRoute(['home']));
    const w = WindowId.manual('w');
    const w2 = WindowId.manual('w2');
    late NotifyingSession session;
    late WindowingController controller;
    late void Function() unwatch;

    HistoryEntry entryOf(AppRoute r) {
      final (:buffer, :arguments) = tree.linkOf(r);
      return HistoryEntry(buffer, arguments: arguments);
    }

    WindowingDoc docShowing(AppRoute r) {
      final d = WindowingDoc.initial();
      final (:buffer, :arguments) = tree.linkOf(r);
      return PushBuffer(w, buffer, arguments: arguments).apply(NewTab(
        shellId: d.focusedShellId,
        tabId: const TabId.manual('t'),
        buffer: (w, home.buffer),
      ).apply(d));
    }

    void start({
      WindowingDoc Function()? initial,
      HibernationStore? store,
      UndoController? undo,
    }) {
      final bound = tree.bind(session);
      controller = WindowingController(
        initial: initial,
        store: store,
        undo: undo,
        interceptor: bound.interceptor,
      );
      unwatch = bound.watch(controller, refresh: session);
    }

    setUp(() => session = NotifyingSession(signedIn: true));
    tearDown(() {
      unwatch();
      controller.dispose();
    });

    test('signing out on a members-only page replaces the entry', () {
      start(initial: () => docShowing(task));
      session.signOut();
      final h = controller.doc.value.windows[w]!.history;
      expect(h.current, entryOf(login));
      expect(h.back, [entryOf(const FilesRoute(['home']))]);
    });

    test('restoring a doc with a now-guarded page redirects it', () {
      final store = InMemoryHibernationStore()
        ..save(WindowingController.hibernationKey,
            docShowing(task).toRecord());
      session.signedIn = false;
      start(store: store);
      expect(controller.doc.value.windows[w]!.history.current, entryOf(login));
    });

    test('redo that brings back a now-guarded page redirects it', () {
      final undo = UndoController();
      start(initial: () => docShowing(const FilesRoute(['home'])), undo: undo);
      final (:buffer, :arguments) = tree.linkOf(task);
      controller.dispatch(SplitWindow(w,
          newWindowId: w2,
          axis: Axis.horizontal,
          buffer: buffer,
          arguments: arguments));
      undo.undo();
      expect(controller.doc.value.windows[w2], isNull);
      session.signedIn = false; // no notify: only the redo re-checks
      undo.redo();
      expect(controller.doc.value.windows[w2]!.history.current, entryOf(login));
    });

    test('a re-check that allows everything leaves the doc unchanged', () {
      start(initial: () => docShowing(task));
      final before = controller.doc.value;
      session.notifyListeners();
      expect(identical(controller.doc.value, before), isTrue);
    });
  });
}

class NotifyingSession extends ChangeNotifier implements Session {
  NotifyingSession({required this.signedIn});
  @override
  bool signedIn;
  void signOut() {
    signedIn = false;
    notifyListeners();
  }

  @override
  // ignore: unnecessary_overrides
  void notifyListeners() => super.notifyListeners();
}
