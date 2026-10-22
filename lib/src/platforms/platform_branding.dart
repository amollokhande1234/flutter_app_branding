import '../config.dart';
import '../icon_source.dart';
import '../reporter.dart';
import '../workspace.dart';

/// One class per platform. Adding a platform = one new implementation.
abstract class PlatformBranding {
  String get id;

  /// Top-level project folder that must exist (e.g. `android`).
  String get folder;

  void apply(
    BrandingConfig config,
    Workspace ws,
    Reporter log,
    IconSource icons,
  );
}
