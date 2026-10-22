import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'config.dart';

/// What happened to a file during `apply`.
enum ChangeKind { created, updated, removed, unchanged }

/// One file touched (or checked) during `apply`.
class Change {
  const Change(this.path, this.kind);
  final String path;
  final ChangeKind kind;
}

/// All file access goes through here so we get dry-run, idempotency
/// (identical content is never rewritten) and automatic backups for free.
class Workspace {
  Workspace(this.root, {this.dryRun = false})
    : stamp = DateTime.now().toUtc().toIso8601String().replaceAll(
        RegExp(r'[:.]'),
        '-',
      );

  final String root;
  final bool dryRun;
  final String stamp;
  final List<Change> changes = [];
  final Map<String, bool> _backedUp = {};

  String abs(String rel) => p.join(root, rel);
  bool dirExists(String rel) => Directory(abs(rel)).existsSync();
  bool fileExists(String rel) => File(abs(rel)).existsSync();

  String? readText(String rel) {
    final f = File(abs(rel));
    return f.existsSync() ? f.readAsStringSync() : null;
  }

  void writeText(String rel, String content) =>
      _write(rel, utf8.encode(content));

  void writeBytes(String rel, List<int> bytes) => _write(rel, bytes);

  /// Deletes a file (backed up first, so `revert` restores it).
  void delete(String rel) {
    final file = File(abs(rel));
    if (!file.existsSync()) return;
    changes.add(Change(rel, ChangeKind.removed));
    if (dryRun) return;
    _backup(rel, true);
    file.deleteSync();
  }

  /// Files under [relDir] whose name matches [name]; optionally only those
  /// whose parent folder name starts with [dirPrefix] (e.g. `drawable`).
  List<String> findFiles(String relDir, RegExp name, {String? dirPrefix}) {
    final d = Directory(abs(relDir));
    if (!d.existsSync()) return [];
    return [
      for (final e in d.listSync(recursive: true))
        if (e is File &&
            name.hasMatch(p.basename(e.path)) &&
            (dirPrefix == null ||
                p.basename(p.dirname(e.path)).startsWith(dirPrefix)))
          p.relative(e.path, from: root).replaceAll(r'\', '/'),
    ];
  }

  String get backupDir =>
      p.join(root, '.flutter_app_branding', 'backups', stamp);

  void _write(String rel, List<int> bytes) {
    final file = File(abs(rel));
    final existed = file.existsSync();
    if (existed && _same(file.readAsBytesSync(), bytes)) {
      changes.add(Change(rel, ChangeKind.unchanged));
      return;
    }
    changes.add(Change(rel, existed ? ChangeKind.updated : ChangeKind.created));
    if (dryRun) return;
    _backup(rel, existed);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
  }

  void _backup(String rel, bool existed) {
    if (_backedUp.containsKey(rel)) return;
    _backedUp[rel] = existed;
    if (existed) {
      final dest = File(p.join(backupDir, rel));
      dest.parent.createSync(recursive: true);
      File(abs(rel)).copySync(dest.path);
    }
  }

  /// Persists the backup manifest so `revert` knows what to restore.
  void commit() {
    if (dryRun || _backedUp.isEmpty) return;
    final manifest = {
      'files': [
        for (final e in _backedUp.entries) {'path': e.key, 'existed': e.value},
      ],
    };
    final f = File(p.join(backupDir, 'manifest.json'));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(manifest));
  }

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Restores every file touched by the most recent `apply`.
/// Returns the number of files restored or removed.
int revertLatest(String root) {
  final dir = Directory(p.join(root, '.flutter_app_branding', 'backups'));
  if (!dir.existsSync()) throw BrandingException('Nothing to revert.');
  final runs = dir.listSync().whereType<Directory>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  if (runs.isEmpty) throw BrandingException('Nothing to revert.');

  final last = runs.last;
  final manifestFile = File(p.join(last.path, 'manifest.json'));
  if (!manifestFile.existsSync()) {
    throw BrandingException('Backup is missing its manifest.json.');
  }
  final manifest = jsonDecode(manifestFile.readAsStringSync()) as Map;
  var count = 0;
  for (final entry in (manifest['files'] as List).cast<Map>()) {
    final rel = entry['path'] as String;
    final target = File(p.join(root, rel));
    if (entry['existed'] == true) {
      target.parent.createSync(recursive: true);
      File(p.join(last.path, rel)).copySync(target.path);
      count++;
    } else if (target.existsSync()) {
      target.deleteSync();
      count++;
    }
  }
  last.deleteSync(recursive: true);
  return count;
}
