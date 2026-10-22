import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'config.dart';
import 'icon_source.dart';
import 'image_utils.dart';
import 'legacy.dart';
import 'platforms/android.dart';
import 'platforms/ios.dart';
import 'platforms/macos.dart';
import 'platforms/platform_branding.dart';
import 'platforms/web.dart';
import 'platforms/windows.dart';
import 'reporter.dart';
import 'validate.dart';
import 'workspace.dart';

/// Every platform handler, in the order they run.
final List<PlatformBranding> allHandlers = [
  AndroidBranding(),
  IosBranding(),
  WebBranding(),
  WindowsBranding(),
  MacosBranding(),
];

/// Applies name + icons. Returns a process exit code.
int runApply({
  required String root,
  required Reporter log,
  String? configFile,
  bool dryRun = false,
  Set<String> only = const {},
  String? name,
  String? icon,
  bool flutterClean = false,
}) {
  BrandingConfig config;
  try {
    config = BrandingConfig.load(root, file: configFile);
  } on MissingConfigException {
    if (name == null || icon == null) {
      if (dryRun) rethrow;
      _createStarter(root);
      log.log(
        'No config yet, so I created flutter_app_branding.yaml from your project.',
      );
      log.log(
        'Edit name, icon and platforms in it, then run again: '
        'dart run flutter_app_branding',
      );
      log.finish();
      return 0;
    }
    config = BrandingConfig(name: name, icon: icon);
    if (!dryRun) {
      File(p.join(root, 'flutter_app_branding.yaml')).writeAsStringSync(
        'flutter_app_branding:\n  name: "${name.replaceAll('"', r'\"')}"\n  icon: $icon\n',
      );
      log.log(
        'Saved flutter_app_branding.yaml (edit it later for flavors, locales, etc.).',
      );
    }
  }
  config = config.copyWith(name: name, icon: icon);

  final issues = validateConfig(config, root);
  for (final i in issues) {
    i.isError ? log.error(i.message) : log.warn(i.message);
  }
  if (issues.any((i) => i.isError)) {
    log.finish();
    return 1;
  }

  _reportLegacy(root, log);

  final ws = Workspace(root, dryRun: dryRun);
  final icons = IconSource(root);
  var failed = false;

  for (final h in allHandlers) {
    if (!config.platforms.contains(h.id)) continue;
    if (only.isNotEmpty && !only.contains(h.id)) continue;
    if (!ws.dirExists(h.folder)) {
      log.warn(
        'Skipping ${h.id}: no ${h.folder}/ folder '
        '(run: flutter create --platforms=${h.id} .)',
      );
      continue;
    }
    log.log('> ${h.id}');
    try {
      h.apply(config, ws, log, icons);
    } on BrandingException catch (e) {
      log.error('${h.id}: ${e.message}');
      failed = true;
    }
  }

  ws.commit();
  log.printChanges(ws.changes, dryRun: dryRun);
  final changedAny = ws.changes.any((c) => c.kind != ChangeKind.unchanged);
  if (!dryRun && changedAny) {
    log.log('Undo with: dart run flutter_app_branding revert');
    if (flutterClean) {
      _flutterClean(root, log);
    } else {
      log.log(
        'Launchers cache icons: uninstall the app (or re-run with '
        '--clean) before testing.',
      );
    }
  }
  log.finish();
  return failed ? 1 : 0;
}

/// Asks the user to remove old tools; we never edit pubspec.yaml ourselves.
void _reportLegacy(String root, Reporter log) {
  final legacy = detectLegacy(root);
  if (!legacy.found) return;
  log.warn(
    'Another icon/name tool is still set up '
    '(${[...legacy.tools, ...legacy.configFiles].join(', ')}). '
    'flutter_app_branding replaces it; keeping both makes them overwrite '
    'each other.',
  );
  for (final step in legacy.instructions) {
    log.log('      - $step');
  }
  log.log(
    '      Files it generated (old adaptive icon, foregrounds, .webp, '
    'round icons) are removed below; `revert` restores them.',
  );
}

void _flutterClean(String root, Reporter log) {
  for (final args in [
    ['clean'],
    ['pub', 'get'],
  ]) {
    log.log('> flutter ${args.join(' ')}');
    try {
      final r = Process.runSync(
        'flutter',
        args,
        workingDirectory: root,
        runInShell: true,
      );
      if (r.exitCode != 0) {
        log.warn('flutter ${args.join(' ')} failed: ${r.stderr}');
      }
    } on ProcessException catch (e) {
      log.warn('Could not run flutter: ${e.message}');
      return;
    }
  }
}

/// Checks the config and images. Returns an exit code.
int runValidate(String root, Reporter log, {String? configFile}) {
  final config = BrandingConfig.load(root, file: configFile);
  final issues = validateConfig(config, root);
  for (final i in issues) {
    i.isError ? log.error(i.message) : log.warn(i.message);
  }
  if (issues.isEmpty) log.log('Config and images look good.');
  log.finish();
  return issues.any((i) => i.isError) ? 1 : 0;
}

/// Restores files from the latest backup. Returns an exit code.
int runRevert(String root, Reporter log) {
  final n = revertLatest(root);
  log.log('Restored $n file(s) from the last apply.');
  log.finish();
  return 0;
}

/// Diagnoses the project setup. Returns an exit code.
int runDoctor(String root, Reporter log, {String? configFile}) {
  var errors = 0;
  final pubspec = File(p.join(root, 'pubspec.yaml'));
  if (!pubspec.existsSync()) {
    log.error('No pubspec.yaml in $root. Is this a Flutter project root?');
    log.finish();
    return 1;
  }

  final legacy = detectLegacy(root);
  if (legacy.found) {
    log.warn(
      'Legacy tools found: ${[...legacy.tools, ...legacy.configFiles].join(', ')}',
    );
    for (final step in legacy.instructions) {
      log.log('      - $step');
    }
  } else {
    log.log('No legacy icon/name tools found.');
  }

  log.log('Platform folders:');
  for (final h in allHandlers) {
    final ok = Directory(p.join(root, h.folder)).existsSync();
    log.log('  ${ok ? 'ok ' : '-- '} ${h.folder}/');
  }

  try {
    final config = BrandingConfig.load(root, file: configFile);
    for (final i in validateConfig(config, root)) {
      if (i.isError) {
        log.error(i.message);
        errors++;
      } else {
        log.warn(i.message);
      }
    }
  } on BrandingException catch (e) {
    log.error(e.message);
    errors++;
  }
  log.finish();
  return errors == 0 ? 0 : 1;
}

String _projectName(String root) {
  final f = File(p.join(root, 'pubspec.yaml'));
  if (f.existsSync()) {
    final d = loadYaml(f.readAsStringSync());
    if (d is YamlMap && d['name'] != null) {
      return d['name']
          .toString()
          .split('_')
          .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
          .join(' ');
    }
  }
  return 'My App';
}

String _detectIcon(String root) {
  String rel(String path) => p.relative(path, from: root).replaceAll(r'\', '/');
  final assets = Directory(p.join(root, 'assets'));
  if (assets.existsSync()) {
    final pngs = [
      for (final e in assets.listSync(recursive: true))
        if (e is File && e.path.toLowerCase().endsWith('.png')) e.path,
    ]..sort();
    for (final key in ['icon', 'logo']) {
      for (final f in pngs) {
        if (p.basename(f).toLowerCase().contains(key)) return rel(f);
      }
    }
    if (pngs.isNotEmpty) return rel(pngs.first);
  }
  return 'assets/icon/icon.png';
}

/// Writes flutter_app_branding.yaml pre-filled from the project: pubspec name,
/// a detected icon, and only the platform folders that exist.
void _createStarter(String root) {
  final found = [
    for (final pl in supportedPlatforms)
      if (Directory(p.join(root, pl)).existsSync()) pl,
  ];
  final platforms = (found.isEmpty ? supportedPlatforms : found).join(', ');
  File(p.join(root, 'flutter_app_branding.yaml')).writeAsStringSync('''
# flutter_app_branding: ONE file for your app name, icon and platforms.
# Edit the values below, then run:   dart run flutter_app_branding
# Preview first (changes nothing):   dart run flutter_app_branding --dry-run
# Undo the last run:                 dart run flutter_app_branding revert
flutter_app_branding:
  name: "${_projectName(root)}"
  icon: ${_detectIcon(root)}          # square PNG, 1024x1024 recommended
  platforms: [$platforms]

  # --- optional ---------------------------------------------------------
  # adaptive_icon:                    # Android: auto-built if omitted
  #   background: "#FFFFFF"           # "#RRGGBB" or an image path
  #   foreground: assets/icon/foreground.png
  #   monochrome: assets/icon/monochrome.png   # Android 13 themed icon
  #
  # localized_names:                  # Android only for now
  #   hi: "माय ऐप"
  #   es: "Mi App"
  #
  # flavors:                          # names must match Gradle productFlavors
  #   dev:
  #     name: "My App Dev"
  #     icon: assets/icon/icon.png
  #     badge: "DEV"                  # ribbon drawn on the icon
''');
}

/// Creates a pre-filled `flutter_app_branding.yaml`. Returns an exit code.
int runInit(String root, Reporter log, {bool force = false}) {
  final f = File(p.join(root, 'flutter_app_branding.yaml'));
  if (f.existsSync() && !force) {
    throw BrandingException(
      'flutter_app_branding.yaml already exists (use --force).',
    );
  }
  _createStarter(root);
  log.log(
    'Created flutter_app_branding.yaml. Edit name, icon and platforms, then run: '
    'dart run flutter_app_branding',
  );
  log.finish();
  return 0;
}

/// Converts a flutter_launcher_icons config to flutter_app_branding format.
int runMigrate(String root, Reporter log, {bool write = false}) {
  YamlMap? icons;
  YamlMap? pubDoc;

  final yamlFile = File(p.join(root, 'flutter_launcher_icons.yaml'));
  if (yamlFile.existsSync()) {
    final d = loadYaml(yamlFile.readAsStringSync());
    if (d is YamlMap) {
      icons = d['flutter_launcher_icons'] is YamlMap
          ? d['flutter_launcher_icons'] as YamlMap
          : d;
    }
  }
  final pub = File(p.join(root, 'pubspec.yaml'));
  if (pub.existsSync()) {
    final d = loadYaml(pub.readAsStringSync());
    if (d is YamlMap) {
      pubDoc = d;
      if (icons == null && d['flutter_launcher_icons'] is YamlMap) {
        icons = d['flutter_launcher_icons'] as YamlMap;
      }
    }
  }
  if (icons == null) {
    throw BrandingException('No flutter_launcher_icons configuration found.');
  }

  bool on(dynamic v) => v == null
      ? false
      : v is bool
      ? v
      : v is YamlMap
      ? v['generate'] == true
      : true;

  final platforms = [
    if (on(icons['android'])) 'android',
    if (on(icons['ios'])) 'ios',
    if (on(icons['web'])) 'web',
    if (on(icons['windows'])) 'windows',
    if (on(icons['macos'])) 'macos',
  ];

  final rawName = (pubDoc?['name'] ?? 'my_app').toString();
  final name = rawName
      .split('_')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  final b = StringBuffer('flutter_app_branding:\n')
    ..writeln('  name: "$name"   # TODO: set your display name');
  if (icons['image_path'] != null) b.writeln('  icon: ${icons['image_path']}');
  final bg = icons['adaptive_icon_background'];
  final fg = icons['adaptive_icon_foreground'];
  final mono = icons['adaptive_icon_monochrome'];
  if (bg != null || fg != null) {
    b.writeln('  adaptive_icon:');
    if (bg != null) b.writeln('    background: "$bg"');
    if (fg != null) b.writeln('    foreground: $fg');
    if (mono != null) b.writeln('    monochrome: $mono');
  }
  b.writeln('  platforms: [${platforms.join(', ')}]');

  if (write) {
    final out = File(p.join(root, 'flutter_app_branding.yaml'));
    if (out.existsSync()) {
      throw BrandingException(
        'flutter_app_branding.yaml already exists; not overwriting.',
      );
    }
    out.writeAsStringSync(b.toString());
    log.log(
      'Wrote flutter_app_branding.yaml. Remove the old flutter_launcher_icons config.',
    );
  } else {
    log.log(b.toString());
    log.log('(pass --write to save this as flutter_app_branding.yaml)');
  }
  log.finish();
  return 0;
}

/// Contact sheet: your icon at several sizes in circle / rounded / square masks.
int runPreview(String root, Reporter log, {String? configFile}) {
  final config = BrandingConfig.load(root, file: configFile);
  if (config.icon == null) throw BrandingException('No "icon" configured.');
  final src = IconSource(root).load(config.icon!);

  const sizes = [128, 64, 32];
  const shapes = ['circle', 'rounded', 'square'];
  const pad = 20;
  final width = pad + shapes.length * (128 + pad);
  final height = pad + sizes.fold<int>(0, (a, s) => a + s + pad);

  final sheet = solid(width, '#EEEEEE');
  final canvas = img.copyCrop(sheet, x: 0, y: 0, width: width, height: height);
  var y = pad;
  for (final size in sizes) {
    var x = pad;
    for (final shape in shapes) {
      img.compositeImage(
        canvas,
        maskShape(resizeTo(src, size), shape),
        dstX: x,
        dstY: y,
      );
      x += 128 + pad;
    }
    y += size + pad;
  }

  final out = File(p.join(root, '.flutter_app_branding', 'preview.png'));
  out.parent.createSync(recursive: true);
  out.writeAsBytesSync(pngBytes(canvas));
  log.log('Wrote ${p.relative(out.path, from: root)}');
  log.finish();
  return 0;
}
