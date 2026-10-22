import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import 'config.dart';
import 'reporter.dart';
import 'runner.dart';

String _root(ArgResults g) => p.normalize(p.absolute(g['project'] as String));
Reporter _reporter(ArgResults g) => Reporter(json: g['json'] as bool);
String? _config(ArgResults g) => g['config'] as String?;

/// `apply`: writes the app name and icons to every configured platform.
class ApplyCommand extends Command<int> {
  ApplyCommand() {
    argParser
      ..addFlag(
        'dry-run',
        negatable: false,
        help: 'Show what would change without writing.',
      )
      ..addOption('name', abbr: 'n', help: 'App name (overrides config).')
      ..addOption('icon', abbr: 'i', help: 'Icon path (overrides config).')
      ..addFlag(
        'clean',
        negatable: false,
        help: 'Run flutter clean && flutter pub get afterwards.',
      )
      ..addMultiOption(
        'platform',
        abbr: 'P',
        allowed: supportedPlatforms,
        help: 'Limit to these platforms (default: all in config).',
      );
  }
  @override
  final name = 'apply';
  @override
  final description = 'Apply app name and icons to all configured platforms.';
  @override
  int run() {
    final g = globalResults!;
    return runApply(
      root: _root(g),
      log: _reporter(g),
      configFile: _config(g),
      dryRun: argResults!['dry-run'] as bool,
      only: (argResults!['platform'] as List<String>).toSet(),
      name: argResults!['name'] as String?,
      icon: argResults!['icon'] as String?,
      flutterClean: argResults!['clean'] as bool,
    );
  }
}

/// `validate`: checks the config and source images without changing files.
class ValidateCommand extends Command<int> {
  @override
  final name = 'validate';
  @override
  final description =
      'Check the config and source images without changing anything.';
  @override
  int run() {
    final g = globalResults!;
    return runValidate(_root(g), _reporter(g), configFile: _config(g));
  }
}

/// `doctor`: reports missing platform folders and leftover legacy tools.
class DoctorCommand extends Command<int> {
  @override
  final name = 'doctor';
  @override
  final description =
      'Diagnose missing platform folders and leftover legacy tool configs.';
  @override
  int run() {
    final g = globalResults!;
    return runDoctor(_root(g), _reporter(g), configFile: _config(g));
  }
}

/// `revert`: restores the files changed by the most recent `apply`.
class RevertCommand extends Command<int> {
  @override
  final name = 'revert';
  @override
  final description = 'Undo the most recent apply using the automatic backup.';
  @override
  int run() {
    final g = globalResults!;
    return runRevert(_root(g), _reporter(g));
  }
}

/// `init`: creates a starter config pre-filled from the project.
class InitCommand extends Command<int> {
  InitCommand() {
    argParser.addFlag(
      'force',
      negatable: false,
      help: 'Overwrite existing file.',
    );
  }
  @override
  final name = 'init';
  @override
  final description = 'Create a starter flutter_app_branding.yaml.';
  @override
  int run() {
    final g = globalResults!;
    return runInit(_root(g), _reporter(g), force: argResults!['force'] as bool);
  }
}

/// `migrate`: converts a `flutter_launcher_icons` config to this format.
class MigrateCommand extends Command<int> {
  MigrateCommand() {
    argParser.addFlag(
      'write',
      negatable: false,
      help: 'Save as flutter_app_branding.yaml instead of printing.',
    );
  }
  @override
  final name = 'migrate';
  @override
  final description =
      'Convert a flutter_launcher_icons config to flutter_app_branding.';
  @override
  int run() {
    final g = globalResults!;
    return runMigrate(
      _root(g),
      _reporter(g),
      write: argResults!['write'] as bool,
    );
  }
}

/// `preview`: renders a contact sheet of the icon in common mask shapes.
class PreviewCommand extends Command<int> {
  @override
  final name = 'preview';
  @override
  final description =
      'Render a contact sheet of the icon in circle/rounded/square masks.';
  @override
  int run() {
    final g = globalResults!;
    return runPreview(_root(g), _reporter(g), configFile: _config(g));
  }
}

/// Entry point of the `flutter_app_branding` executable.
///
/// Returns the process exit code: 0 on success, 1 on errors, 64 on bad usage.
Future<int> runCli(List<String> args) async {
  final runner =
      CommandRunner<int>(
          'flutter_app_branding',
          'Set your Flutter app name and icons from one config.',
        )
        ..argParser.addOption(
          'project',
          abbr: 'p',
          defaultsTo: '.',
          help: 'Flutter project root.',
        )
        ..argParser.addOption(
          'config',
          abbr: 'c',
          help: 'Config file (default: flutter_app_branding.yaml, then pubspec.yaml).',
        )
        ..argParser.addFlag(
          'json',
          negatable: false,
          help: 'Machine-readable output for CI.',
        )
        ..addCommand(ApplyCommand())
        ..addCommand(ValidateCommand())
        ..addCommand(DoctorCommand())
        ..addCommand(RevertCommand())
        ..addCommand(InitCommand())
        ..addCommand(MigrateCommand())
        ..addCommand(PreviewCommand());

  // Global options may appear anywhere; `flutter_app_branding` with no command
  // means `apply`.
  const commands = {
    'apply',
    'validate',
    'doctor',
    'revert',
    'init',
    'migrate',
    'preview',
    'help',
  };
  final globals = <String>[];
  final rest = <String>[];
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--json' ||
        a.startsWith('--project=') ||
        a.startsWith('--config=')) {
      globals.add(a);
    } else if (a == '-p' || a == '--project' || a == '-c' || a == '--config') {
      globals.add(a);
      if (i + 1 < args.length) globals.add(args[++i]);
    } else {
      rest.add(a);
    }
  }
  final wantsHelp = rest.contains('-h') || rest.contains('--help');
  final hasCommand = rest.any(commands.contains);
  final effective = [
    ...globals,
    if (!hasCommand && !wantsHelp) 'apply',
    ...rest,
  ];

  try {
    return await runner.run(effective) ?? 0;
  } on UsageException catch (e) {
    stderr.writeln(e);
    return 64;
  } on BrandingException catch (e) {
    stderr.writeln('error: ${e.message}');
    return 1;
  }
}
