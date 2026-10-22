import '../config.dart';
import '../icon_source.dart';
import '../image_utils.dart';
import '../reporter.dart';
import '../workspace.dart';
import 'platform_branding.dart';

/// Writes the app name and icons for Windows.
class WindowsBranding implements PlatformBranding {
  @override
  String get id => 'windows';
  @override
  String get folder => 'windows';

  static const _sizes = [16, 24, 32, 48, 64, 128, 256];

  @override
  void apply(BrandingConfig c, Workspace ws, Reporter log, IconSource icons) {
    _patchMain(c.name, ws, log);
    _patchRc(c.name, ws, log);

    final icon = icons.forVariant(c.variants.first);
    if (icon == null) return;
    final frames = {for (final s in _sizes) s: pngBytes(resizeTo(icon, s))};
    ws.writeBytes('windows/runner/resources/app_icon.ico', buildIco(frames));
  }

  /// Window title.
  void _patchMain(String name, Workspace ws, Reporter log) {
    const path = 'windows/runner/main.cpp';
    final src = ws.readText(path);
    if (src == null) {
      log.warn('$path not found; window title not changed.');
      return;
    }
    final esc = name.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    ws.writeText(
      path,
      src.replaceFirstMapped(
        RegExp(r'(window\.Create\(L")[^"]*(")'),
        (m) => '${m[1]}$esc${m[2]}',
      ),
    );
  }

  /// File properties shown in Explorer / Task Manager.
  void _patchRc(String name, Workspace ws, Reporter log) {
    const path = 'windows/runner/Runner.rc';
    var rc = ws.readText(path);
    if (rc == null) {
      log.warn('$path not found; file description not changed.');
      return;
    }
    final esc = name.replaceAll('"', '""');
    for (final key in ['FileDescription', 'ProductName']) {
      rc = rc!.replaceFirstMapped(
        RegExp('(VALUE\\s+"$key",\\s*")[^"]*(")'),
        (m) => '${m[1]}$esc${m[2]}',
      );
    }
    ws.writeText(path, rc!);
  }
}
