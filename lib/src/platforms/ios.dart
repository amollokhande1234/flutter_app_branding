import 'dart:convert';

import '../config.dart';
import '../icon_source.dart';
import '../image_utils.dart';
import '../reporter.dart';
import '../workspace.dart';
import 'platform_branding.dart';

class _Slot {
  const _Slot(this.idiom, this.size, this.scale);
  final String idiom;
  final double size;
  final int scale;
}

/// Writes the app name and icons for iOS.
class IosBranding implements PlatformBranding {
  @override
  String get id => 'ios';
  @override
  String get folder => 'ios';

  static const _slots = [
    _Slot('iphone', 20, 2),
    _Slot('iphone', 20, 3),
    _Slot('iphone', 29, 2),
    _Slot('iphone', 29, 3),
    _Slot('iphone', 40, 2),
    _Slot('iphone', 40, 3),
    _Slot('iphone', 60, 2),
    _Slot('iphone', 60, 3),
    _Slot('ipad', 20, 1),
    _Slot('ipad', 20, 2),
    _Slot('ipad', 29, 1),
    _Slot('ipad', 29, 2),
    _Slot('ipad', 40, 1),
    _Slot('ipad', 40, 2),
    _Slot('ipad', 76, 1),
    _Slot('ipad', 76, 2),
    _Slot('ipad', 83.5, 2),
    _Slot('ios-marketing', 1024, 1),
  ];

  @override
  void apply(BrandingConfig c, Workspace ws, Reporter log, IconSource icons) {
    _patchPlist(c.name, ws, log);

    for (final v in c.variants) {
      final icon = icons.forVariant(v);
      if (icon == null) continue;
      final setName = v.flavor == null ? 'AppIcon' : 'AppIcon-${v.flavor}';
      _writeSet('ios/Runner/Assets.xcassets/$setName.appiconset', icon, ws);
    }

    if (c.flavors.isNotEmpty) {
      log.warn(
        'iOS flavors: icon sets were generated as AppIcon-<flavor>. '
        'Point each build configuration at its set via '
        'ASSETCATALOG_COMPILER_APPICON_NAME in Xcode (name per flavor is '
        'not automated yet).',
      );
    }
  }

  void _writeSet(String dir, image, Workspace ws) {
    final flat = flattenOnto(image); // iOS rejects alpha
    final images = <Map<String, String>>[];
    final done = <String>{};
    for (final s in _slots) {
      final px = (s.size * s.scale).round();
      final n = _n(s.size);
      final file = 'Icon-App-${n}x$n@${s.scale}x.png';
      if (done.add(file)) {
        ws.writeBytes('$dir/$file', pngBytes(resizeTo(flat, px)));
      }
      images.add({
        'size': '${n}x$n',
        'idiom': s.idiom,
        'filename': file,
        'scale': '${s.scale}x',
      });
    }
    ws.writeText(
      '$dir/Contents.json',
      '${const JsonEncoder.withIndent('  ').convert({
        'images': images,
        'info': {'version': 1, 'author': 'flutter_app_branding'},
      })}\n',
    );
  }

  String _n(double v) => v == v.roundToDouble() ? v.toInt().toString() : '$v';

  void _patchPlist(String name, Workspace ws, Reporter log) {
    const path = 'ios/Runner/Info.plist';
    var xml = ws.readText(path);
    if (xml == null) {
      log.warn('$path not found; display name not changed.');
      return;
    }
    xml = _setKey(xml, 'CFBundleDisplayName', name);
    xml = _setKey(xml, 'CFBundleName', name);
    ws.writeText(path, xml);
  }

  String _setKey(String xml, String key, String value) {
    final esc = value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
    final re = RegExp('(<key>$key</key>\\s*<string>)[^<]*(</string>)');
    if (re.hasMatch(xml)) {
      return xml.replaceFirstMapped(re, (m) => '${m[1]}$esc${m[2]}');
    }
    return xml.replaceFirst(
      '<dict>',
      '<dict>\n\t<key>$key</key>\n\t<string>$esc</string>',
    );
  }
}
