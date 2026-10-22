import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Packages that set the app name or icon and would fight with this one.
const legacyTools = [
  'flutter_launcher_icons',
  'flutter_launcher_name',
  'rename_app',
  'icons_launcher',
];

/// What was found of older icon/name tools (for example `flutter_launcher_icons`).
class LegacyReport {
  const LegacyReport({
    required this.tools,
    required this.configFiles,
    this.androidIconName,
  });

  /// Legacy tools still referenced in pubspec.yaml (dependency or config).
  final List<String> tools;

  /// Standalone legacy config files in the project root.
  final List<String> configFiles;

  /// Custom Android icon name from flutter_launcher_icons (`android: "name"`),
  /// when it is not the default `ic_launcher`.
  final String? androidIconName;

  bool get found => tools.isNotEmpty || configFiles.isNotEmpty;

  /// Human-readable steps we ask the user to do (we never edit pubspec.yaml).
  List<String> get instructions => [
    for (final t in tools)
      'Remove `$t` from dev_dependencies (and its config block) in pubspec.yaml.',
    for (final f in configFiles) 'Delete the old config file $f.',
    if (found) 'Then run: flutter pub get',
  ];
}

/// Looks for older icon/name tools in `pubspec.yaml` and standalone config files.
LegacyReport detectLegacy(String root) {
  final tools = <String>[];
  final files = <String>[];
  final sources = <dynamic>[];

  final pub = File(p.join(root, 'pubspec.yaml'));
  var text = '';
  if (pub.existsSync()) {
    text = pub.readAsStringSync();
    try {
      sources.add(loadYaml(text));
    } catch (_) {}
  }
  for (final t in legacyTools) {
    if (RegExp('^\\s*$t\\s*:', multiLine: true).hasMatch(text)) tools.add(t);
  }

  final dir = Directory(root);
  if (dir.existsSync()) {
    final re = RegExp(
      r'^(flutter_launcher_icons|flutter_launcher_name|icons_launcher)(-.+)?\.ya?ml$',
    );
    for (final e in dir.listSync()) {
      if (e is File && re.hasMatch(p.basename(e.path))) {
        files.add(p.basename(e.path));
        try {
          sources.add(loadYaml(e.readAsStringSync()));
        } catch (_) {}
      }
    }
  }
  files.sort();

  String? custom;
  for (final doc in sources) {
    if (doc is! YamlMap) continue;
    final section = doc['flutter_launcher_icons'] is YamlMap
        ? doc['flutter_launcher_icons']
        : doc;
    final android = section is YamlMap ? section['android'] : null;
    if (android is String && android.isNotEmpty && android != 'ic_launcher') {
      custom = android;
    }
  }
  return LegacyReport(
    tools: tools,
    configFiles: files,
    androidIconName: custom,
  );
}
