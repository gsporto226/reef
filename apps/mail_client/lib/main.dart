// The mail client integration app (docs/integration-apps.md): folders, a
// thread list and threads in one windowing doc. Expanded screens show the
// folder window beside the detail window; compact ones show the focused
// window alone, and back walks that window's history.
import 'package:flutter/material.dart';
import 'package:reef/reef.dart';

void main() => runApp(MailApp(store: InMemoryHibernationStore()));

typedef Thread = ({String folder, String subject, String body});

const folderNames = {'inbox': 'Inbox', 'archive': 'Archive'};

const threads = <String, Thread>{
  '42': (folder: 'inbox', subject: 'Lunch on Friday?', body: 'Noon works.'),
  '7': (folder: 'inbox', subject: 'Build is green', body: 'Ship it.'),
  '13': (folder: 'archive', subject: 'Old receipts', body: 'Attached.'),
};

const folderList = BufferId.manual('folders:');

BufferId folder(String id) => BufferId.manual('folder:$id');

BufferId thread(String id) => BufferId.manual('thread:$id');

/// One path template per buffer kind; every `/compose` is a fresh draft.
const links = LinkTable(
  {
    'folders': '/folders',
    'folder': '/folders/:folderId',
    'thread': '/threads/:threadId',
    'compose': '/compose',
  },
  drafts: {'compose'},
);

/// The first-run layout: the folder list beside the inbox.
WindowingDoc defaultLayout() {
  final seed = WindowingController();
  final empty = seed.doc.value.shells.values.single.activeTabId;
  seed
    ..newTab(buffer: folderList)
    ..closeTab(empty);
  final list = seed.doc.value.windows.keys.single;
  seed.attachBuffer(
    seed.splitWindow(list, axis: Axis.horizontal),
    folder('inbox'),
  );
  final doc = seed.doc.value;
  seed.dispose();
  return doc;
}

/// Opens folders, threads and drafts in the detail window: the active tab's
/// window not showing the folder list. A folder replaces the detail history;
/// anything else is pushed on it. The folder list, or anything without a
/// detail window, goes through reef's default (focus it where shown).
List<WindowingCommand> mailOpenPolicy(WindowingDoc doc, BufferId buffer) {
  // API_NOTES.md Â§2 and Â§3.
  final tab = doc.tabs[doc.shells[doc.focusedShellId]!.activeTabId]!;
  final detail = tab.root?.windowIds
      .where((w) => doc.windows[w]!.history.current != folderList)
      .lastOrNull;
  if (detail == null || buffer == folderList) {
    return defaultOpenPolicy(doc, buffer);
  }
  return [
    buffer.id.startsWith('folder:')
        ? AttachBuffer(detail, buffer)
        : PushBuffer(detail, buffer),
    ActivateWindow(detail),
  ];
}

/// The mail client over [store]. A [launchLink] (a tapped notification)
/// opens on top of the restored doc, or into an empty one on a fresh
/// install.
class MailApp extends StatefulWidget {
  const MailApp({super.key, required this.store, this.launchLink});

  final HibernationStore store;
  final Uri? launchLink;

  @override
  State<MailApp> createState() => MailAppState();
}

class MailAppState extends State<MailApp> {
  late final WindowingController controller;

  @override
  void initState() {
    super.initState();
    // API_NOTES.md Â§4: the controller can't say whether it restored.
    final fresh = widget.store.load(WindowingController.hibernationKey) == null;
    controller = WindowingController(
      initial: fresh && widget.launchLink != null
          ? WindowingDoc.initial()
          : defaultLayout(),
      store: widget.store,
      links: links,
      openPolicy: mailOpenPolicy,
      focusPolicy: const WindowingFocusPolicy(
        emptyBack: EmptyBackAction.unhandled,
      ),
    );
    if (widget.launchLink case final uri?) notify(uri);
  }

  /// A tapped push notification for [uri].
  Future<bool> notify(Uri uri) => controller.openLink(BufferPath.fromUri(uri));

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Mail',
    theme: ThemeData(useMaterial3: true),
    home: Scaffold(
      appBar: AppBar(
        title: const Text('Mail'),
        actions: [
          IconButton(
            tooltip: 'Compose',
            icon: const Icon(Icons.edit),
            onPressed: () => notify(Uri.parse('/compose')),
          ),
          IconButton(
            tooltip: 'Simulate notification',
            icon: const Icon(Icons.notifications),
            onPressed: () => notify(Uri.parse('/threads/42')),
          ),
        ],
      ),
      body: WindowingRoot(
        controller: controller,
        bufferBuilder: (_, buffer) => MailPage(buffer),
        child: const WindowingSystemBack(child: _FocusedShell()),
      ),
    ),
  );
}

class _FocusedShell extends StatelessWidget {
  const _FocusedShell();

  @override
  Widget build(BuildContext context) {
    final c = WindowingScope.of(context).controller;
    return ValueListenableBuilder<WindowingDoc>(
      valueListenable: c.doc,
      builder: (_, doc, _) => ShellProjection(doc.focusedShellId),
    );
  }
}

/// The page for one mail buffer, picked by its kind.
class MailPage extends StatelessWidget {
  const MailPage(this.buffer, {super.key});

  final BufferId buffer;

  @override
  Widget build(BuildContext context) {
    void open(BufferId buffer) =>
        WindowingScope.of(context).controller.openBuffer(buffer);
    final colon = buffer.id.indexOf(':');
    final token = buffer.id.substring(colon + 1);
    return switch (buffer.id.substring(0, colon)) {
      'folders' => ListView(
        children: [
          for (final MapEntry(:key, :value) in folderNames.entries)
            ListTile(title: Text(value), onTap: () => open(folder(key))),
        ],
      ),
      'folder' => ListView(
        children: [
          ListTile(
            leading: IconButton(
              tooltip: 'Folders',
              icon: const Icon(Icons.folder),
              onPressed: () => open(folderList),
            ),
            title: Text(folderNames[token] ?? token),
          ),
          for (final MapEntry(:key, :value) in threads.entries)
            if (value.folder == token)
              ListTile(
                title: Text(value.subject),
                onTap: () => open(thread(key)),
              ),
        ],
      ),
      'thread' => ListTile(
        title: Text(threads[token]?.subject ?? 'Missing thread'),
        subtitle: Text(threads[token]?.body ?? ''),
      ),
      'compose' => const Padding(
        padding: EdgeInsets.all(8),
        child: TextField(decoration: InputDecoration(labelText: 'Draft')),
      ),
      _ => Center(child: Text('Unknown buffer ${buffer.id}')),
    };
  }
}
