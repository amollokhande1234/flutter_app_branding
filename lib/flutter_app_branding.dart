/// Change a Flutter app's icon, name, localized names and flavors from one
/// YAML file with one command.
///
/// Most people only use the command line (`dart run flutter_app_branding`).
/// The functions exported here let you run the same steps from Dart code,
/// for example in tests or custom tooling.
library;

export 'src/cli.dart' show runCli;
export 'src/config.dart';
export 'src/legacy.dart';
export 'src/reporter.dart';
export 'src/runner.dart';
export 'src/validate.dart';
export 'src/workspace.dart';
