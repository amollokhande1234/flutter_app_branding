import 'dart:convert';
import 'dart:io';

import 'workspace.dart';

/// Collects and prints progress, warnings and errors (or JSON with `--json`).
class Reporter {
  Reporter({this.json = false, this.silent = false});

  final bool json;
  final bool silent;
  final List<String> warnings = [];
  final List<String> errors = [];
  List<Change> changes = const [];

  bool get _print => !json && !silent;

  void log(String m) {
    if (_print) stdout.writeln(m);
  }

  void warn(String m) {
    warnings.add(m);
    if (_print) stdout.writeln('  ! $m');
  }

  void error(String m) {
    errors.add(m);
    if (_print) stderr.writeln('  x $m');
  }

  void printChanges(List<Change> list, {required bool dryRun}) {
    changes = list;
    final changed = list.where((c) => c.kind != ChangeKind.unchanged).toList();
    for (final c in changed) {
      final sym = switch (c.kind) {
        ChangeKind.created => '+',
        ChangeKind.removed => '-',
        _ => '~',
      };
      log('  $sym ${c.path}');
    }
    final verb = dryRun ? 'Would change' : 'Changed';
    log(
      '\n$verb ${changed.length} file(s); '
      '${list.length - changed.length} already up to date.',
    );
    if (dryRun) log('(dry run: nothing was written)');
  }

  /// In --json mode, prints one machine-readable document at the end.
  void finish() {
    if (!json || silent) return;
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'ok': errors.isEmpty,
        'errors': errors,
        'warnings': warnings,
        'changes': [
          for (final c in changes) {'path': c.path, 'kind': c.kind.name},
        ],
      }),
    );
  }
}
