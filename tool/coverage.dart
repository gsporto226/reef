// Merged-coverage gate (docs/adr/0001-three-layer-tests-merged-coverage.md).
//
// Runs every test layer, merges their lcov, and fails when a touched `lib/`
// line is not hit by any layer.
//
//   dart run tool/coverage.dart                 # files changed vs main
//   dart run tool/coverage.dart --base HEAD~3   # files changed vs a ref
//   dart run tool/coverage.dart packages/reef/lib/features/windowing
//
// Unit + widget layer: `flutter test` in each package, example, or app
// (`apps/*`) with test/.
// Integration layer: `flutter test integration_test -d windows` in each
// example with integration_test/. Both collect coverage for every `reef*`
// package, so a line in reef core counts when the example app hits it.

import 'dart:io';

const _flutter = ['fvm', 'flutter'];
const _device = 'windows';

Future<void> main(List<String> args) async {
  final root = Directory.current.path;
  var base = 'main';
  final paths = <String>[];
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--base') {
      base = args[++i];
    } else {
      paths.add(args[i]);
    }
  }

  final hits = <String, Map<int, int>>{};
  for (final dir in _projects(root)) {
    // Real-window code is experimental (ADR 0013): its tests run to track
    // Flutter's windowing API, but a failure only warns.
    if (!isGated('$dir/lib/x.dart')) {
      if (Directory('$dir/test').existsSync()) {
        await _run(dir, ['test'], gate: false);
      }
      continue;
    }
    final unit = Directory('$dir/test').existsSync();
    final integration = Directory('$dir/integration_test').existsSync();
    if (unit) {
      await _run(dir, ['test', '--coverage', '--coverage-package=^reef']);
      mergeLcov(hits, dir, File('$dir/coverage/lcov.info').readAsStringSync());
    }
    if (integration) {
      await _run(dir, [
        'test', 'integration_test', '-d', _device, //
        '--coverage', '--coverage-package=^reef',
      ]);
      mergeLcov(hits, dir, File('$dir/coverage/lcov.info').readAsStringSync());
    }
  }

  final targets = paths.isEmpty
      ? await _changedFiles(root, base)
      : paths.expand((p) => _dartFiles(_abs(root, p))).toList();
  final gated = targets
      .where((t) => isGated(t) && hasCode(File(t).readAsStringSync()))
      .toList();
  final failures = uncovered(hits, gated);

  if (failures.isEmpty) {
    stdout.writeln('coverage: 100% over ${gated.length} '
        'touched lib files');
    return;
  }
  for (final MapEntry(key: file, value: lines) in failures.entries) {
    final where = lines == null
        ? 'not loaded by any test'
        : 'lines ${lines.join(', ')}';
    stdout.writeln('${_rel(root, file)}: $where');
  }
  exitCode = 1;
}

/// Adds an lcov report's line hits into [hits], keyed by absolute path.
/// `SF:` paths are resolved against [cwd], the directory the run started in.
void mergeLcov(Map<String, Map<int, int>> hits, String cwd, String lcov) {
  Map<int, int>? file;
  for (final line in lcov.split('\n').map((l) => l.trim())) {
    if (line.startsWith('SF:')) {
      file = hits.putIfAbsent(_abs(cwd, line.substring(3)), () => {});
    } else if (line.startsWith('DA:') && file != null) {
      final [number, count, ...] = line.substring(3).split(',');
      final n = int.parse(number);
      file[n] = (file[n] ?? 0) + int.parse(count);
    }
  }
}

/// Uncovered lines per target file; a null value means no layer loaded the
/// file at all.
Map<String, List<int>?> uncovered(
  Map<String, Map<int, int>> hits,
  List<String> targets,
) {
  final result = <String, List<int>?>{};
  for (final target in targets) {
    final lines = hits[_normalize(target)];
    if (lines == null) {
      result[target] = null;
      continue;
    }
    final missed = [
      for (final MapEntry(:key, :value) in lines.entries)
        if (value == 0) key,
    ]..sort();
    if (missed.isNotEmpty) result[target] = missed;
  }
  return result;
}

/// False for a library of directives and comments only (a barrel): it has no
/// executable lines, so no layer reports it.
bool hasCode(String source) => source
    .split('\n')
    .map((l) => l.trim())
    .any((l) =>
        l.isNotEmpty &&
        !l.startsWith('//') &&
        !RegExp(r'^(library|import|export)\b').hasMatch(l));

/// Hand-written library code under some package's `lib/`; generated files
/// and code only real platform windows reach (ADR 0013) are not gated.
bool isGated(String path) {
  final p = path.replaceAll('\\', '/');
  return p.contains('/lib/') &&
      p.endsWith('.dart') &&
      !p.endsWith('.g.dart') &&
      !p.endsWith('.freezed.dart') &&
      !p.contains('packages/reef_multi_window/lib/');
}

/// Packages, their examples, and the integration apps (docs/integration-apps.md).
Iterable<String> _projects(String root) sync* {
  for (final parent in ['packages', 'apps']) {
    final dir = Directory('$root/$parent');
    if (!dir.existsSync()) continue;
    for (final pkg in dir.listSync().whereType<Directory>()) {
      yield pkg.path;
      final example = Directory('${pkg.path}/example');
      if (example.existsSync()) yield example.path;
    }
  }
}

Future<void> _run(String dir, List<String> args, {bool gate = true}) async {
  stdout.writeln('> ${[..._flutter, ...args].join(' ')}  ($dir)');
  final process = await Process.start(
    _flutter.first,
    [..._flutter.skip(1), ...args],
    workingDirectory: dir,
    runInShell: true,
    mode: ProcessStartMode.inheritStdio,
  );
  if (await process.exitCode != 0) {
    if (!gate) return stderr.writeln('experimental tests failed in $dir');
    stderr.writeln('tests failed in $dir');
    exit(1);
  }
}

Future<List<String>> _changedFiles(String root, String base) async {
  Future<List<String>> git(List<String> args) async {
    final r = await Process.run('git', args, workingDirectory: root);
    if (r.exitCode != 0) {
      stderr.write(r.stderr);
      exit(1);
    }
    return (r.stdout as String)
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .map((l) => _abs(root, l.trim()))
        .toList();
  }

  final changed = await git(['diff', '--name-only', '--diff-filter=AMR', base]);
  final untracked = await git(['ls-files', '--others', '--exclude-standard']);
  return {...changed, ...untracked}.toList();
}

Iterable<String> _dartFiles(String path) => FileSystemEntity.isDirectorySync(path)
    ? Directory(path)
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => _normalize(f.path))
    : [path];

String _abs(String cwd, String path) => _normalize(
      File(path).isAbsolute ? path : '$cwd/$path',
    );

/// Absolute, `/`-separated, `.`/`..`-free, lower-cased drive letter.
String _normalize(String path) {
  final parts = <String>[];
  for (final part in path.replaceAll('\\', '/').split('/')) {
    if (part == '..') {
      parts.removeLast();
    } else if (part.isNotEmpty && part != '.') {
      parts.add(part);
    }
  }
  final joined = parts.join('/');
  final rooted = path.startsWith('/') ? '/$joined' : joined;
  return rooted.length > 1 && rooted[1] == ':'
      ? rooted[0].toLowerCase() + rooted.substring(1)
      : rooted;
}

String _rel(String root, String path) {
  final r = '${_normalize(root)}/';
  return path.startsWith(r) ? path.substring(r.length) : path;
}
