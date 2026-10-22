import 'dart:convert';

import '../config.dart';
import '../icon_source.dart';
import '../image_utils.dart';
import '../reporter.dart';
import '../workspace.dart';
import 'platform_branding.dart';

/// Writes the app name and icons for web.
class WebBranding implements PlatformBranding {
  @override
  String get id => 'web';
  @override
  String get folder => 'web';

  @override
  void apply(BrandingConfig c, Workspace ws, Reporter log, IconSource icons) {
    _patchIndex(c.name, ws, log);
    _patchManifest(c.name, ws, log);

    final icon = icons.forVariant(c.variants.first);
    if (icon == null) return;
    final maskBg = (c.adaptive?.backgroundIsColor ?? false)
        ? c.adaptive!.background!
        : '#FFFFFF';

    ws.writeBytes('web/favicon.png', pngBytes(resizeTo(icon, 32)));
    for (final s in [192, 512]) {
      ws.writeBytes('web/icons/Icon-$s.png', pngBytes(resizeTo(icon, s)));
      ws.writeBytes(
        'web/icons/Icon-maskable-$s.png',
        pngBytes(maskableIcon(icon, s, maskBg)),
      );
    }
  }

  void _patchIndex(String name, Workspace ws, Reporter log) {
    const path = 'web/index.html';
    var html = ws.readText(path);
    if (html == null) {
      log.warn('$path not found; page title not changed.');
      return;
    }
    final esc = name
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('"', '&quot;');
    html = html.replaceFirstMapped(
      RegExp(r'<title>[^<]*</title>'),
      (_) => '<title>$esc</title>',
    );
    html = html.replaceFirstMapped(
      RegExp(r'(<meta name="apple-mobile-web-app-title" content=")[^"]*(")'),
      (m) => '${m[1]}$esc${m[2]}',
    );
    ws.writeText(path, html);
  }

  void _patchManifest(String name, Workspace ws, Reporter log) {
    const path = 'web/manifest.json';
    final text = ws.readText(path);
    if (text == null) {
      log.warn('$path not found; web manifest not changed.');
      return;
    }
    final map = jsonDecode(text) as Map<String, dynamic>;
    map['name'] = name;
    map['short_name'] = name;
    ws.writeText(
      path,
      '${const JsonEncoder.withIndent('    ').convert(map)}\n',
    );
  }
}
