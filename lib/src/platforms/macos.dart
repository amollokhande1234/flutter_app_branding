import '../config.dart';
import '../icon_source.dart';
import '../image_utils.dart';
import '../reporter.dart';
import '../workspace.dart';
import 'platform_branding.dart';

/// Writes the app name and icons for macOS.
class MacosBranding implements PlatformBranding {
  @override
  String get id => 'macos';
  @override
  String get folder => 'macos';

  static const _sizes = [16, 32, 64, 128, 256, 512, 1024];

  @override
  void apply(BrandingConfig c, Workspace ws, Reporter log, IconSource icons) {
    const cfg = 'macos/Runner/Configs/AppInfo.xcconfig';
    final text = ws.readText(cfg);
    if (text == null) {
      log.warn('$cfg not found; app name not changed.');
    } else {
      ws.writeText(
        cfg,
        text.replaceFirstMapped(
          RegExp(r'^PRODUCT_NAME\s*=.*$', multiLine: true),
          (_) => 'PRODUCT_NAME = ${c.name}',
        ),
      );
    }

    final icon = icons.forVariant(c.variants.first);
    if (icon == null) return;
    for (final s in _sizes) {
      ws.writeBytes(
        'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_$s.png',
        pngBytes(resizeTo(icon, s)),
      );
    }
  }
}
