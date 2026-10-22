import 'package:image/image.dart' as img;

import '../config.dart';
import '../icon_source.dart';
import '../legacy.dart';
import '../image_utils.dart';
import '../reporter.dart';
import '../workspace.dart';
import 'platform_branding.dart';

/// Writes the app name and icons for Android.
class AndroidBranding implements PlatformBranding {
  @override
  String get id => 'android';
  @override
  String get folder => 'android';

  static const _legacy = {
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
  };

  // Adaptive layers are 108dp.
  static const _adaptiveSizes = {
    'mdpi': 108,
    'hdpi': 162,
    'xhdpi': 216,
    'xxhdpi': 324,
    'xxxhdpi': 432,
  };

  @override
  void apply(BrandingConfig c, Workspace ws, Reporter log, IconSource icons) {
    _checkGradleFlavors(c, ws, log);
    final legacy = detectLegacy(ws.root);

    for (final v in c.variants) {
      // Flavor folder names must match your Gradle productFlavors.
      final set = v.flavor ?? 'main';
      final res = 'android/app/src/$set/res';

      _setString('$res/values/strings.xml', 'app_name', v.name, ws);

      final icon = icons.forVariant(v);
      if (icon == null) continue;

      _legacy.forEach((density, size) {
        ws.writeBytes(
          '$res/mipmap-$density/ic_launcher.png',
          pngBytes(resizeTo(icon, size)),
        );
      });

      final a = c.adaptive;
      if (a != null) {
        if (v.badge != null) {
          log.warn(
            'android/${v.flavor}: badge is applied to the legacy icon '
            'only; the adaptive foreground is left unbadged.',
          );
        }
        _adaptiveLayers(
          res,
          ws,
          bgColor: a.backgroundIsColor ? a.background : null,
          bgImage: a.backgroundIsColor ? null : icons.load(a.background!),
          fg: icons.load(a.foreground!),
          mono: a.monochrome != null ? icons.load(a.monochrome!) : null,
        );
      } else if (c.autoAdaptive) {
        // Zero-config: build the adaptive icon from the main icon so a stale
        // adaptive icon from another tool can never override it.
        _adaptiveLayers(
          res,
          ws,
          bgColor: _sampleBackground(icon),
          fg: _autoForeground(icon),
        );
      } else {
        ws.delete('$res/mipmap-anydpi-v26/ic_launcher.xml');
        ws.delete('$res/mipmap-anydpi-v26/ic_launcher_round.xml');
      }

      _cleanLegacy(res, ws, legacy.androidIconName);
    }

    c.localizedNames.forEach((locale, name) {
      _setString(
        'android/app/src/main/res/values-${_qualifier(locale)}/strings.xml',
        'app_name',
        name,
        ws,
      );
    });

    _patchManifest(ws, log);
  }

  void _adaptiveLayers(
    String res,
    Workspace ws, {
    String? bgColor,
    img.Image? bgImage,
    required img.Image fg,
    img.Image? mono,
  }) {
    String bgRef;
    if (bgColor != null) {
      // Unique names: never clash with colors.xml written by other tools.
      ws.writeText('$res/values/flutter_app_branding_colors.xml', '''
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="flutter_app_branding_icon_background">$bgColor</color>
</resources>
''');
      bgRef = '@color/flutter_app_branding_icon_background';
    } else {
      _layer(res, 'flutter_app_branding_icon_background', bgImage!, ws);
      bgRef = '@mipmap/flutter_app_branding_icon_background';
    }

    _layer(res, 'ic_launcher_foreground', fg, ws);

    var monoTag = '';
    if (mono != null) {
      _layer(res, 'ic_launcher_monochrome', mono, ws);
      monoTag = '\n    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>';
    }

    ws.writeText('$res/mipmap-anydpi-v26/ic_launcher.xml', '''
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="$bgRef"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>$monoTag
</adaptive-icon>
''');
  }

  void _layer(String res, String name, img.Image image, Workspace ws) {
    _adaptiveSizes.forEach((density, size) {
      ws.writeBytes(
        '$res/mipmap-$density/$name.png',
        pngBytes(resizeTo(image, size)),
      );
    });
  }

  /// Icon scaled into the 66dp adaptive safe zone (~61%) on a transparent canvas.
  img.Image _autoForeground(img.Image icon) {
    const canvasSize = 432;
    final canvas = img.Image(
      width: canvasSize,
      height: canvasSize,
      numChannels: 4,
    );
    final inner = (canvasSize * 0.62).round();
    final off = (canvasSize - inner) ~/ 2;
    img.compositeImage(canvas, resizeTo(icon, inner), dstX: off, dstY: off);
    return canvas;
  }

  /// Background colour = the icon's corner pixel (white if transparent).
  String _sampleBackground(img.Image icon) {
    final px = icon.getPixel(2, 2);
    if (px.a < 250) return '#FFFFFF';
    String h(num v) => v.toInt().toRadixString(16).padLeft(2, '0');
    return '#${h(px.r)}${h(px.g)}${h(px.b)}'.toUpperCase();
  }

  /// Removes leftovers from flutter_launcher_icons / Android Studio that
  /// would override or clash with the icons we just wrote. Backed up, so
  /// `revert` brings them back.
  void _cleanLegacy(String res, Workspace ws, String? customName) {
    // Default names written by flutter_launcher_icons / Android Studio.
    for (final f in ws.findFiles(
      res,
      RegExp(r'^ic_launcher_(foreground|monochrome)\.(png|webp)$'),
      dirPrefix: 'drawable',
    )) {
      ws.delete(f);
    }
    for (final f in ws.findFiles(res, RegExp(r'^ic_launcher\.webp$'))) {
      ws.delete(f);
    }
    for (final f in ws.findFiles(
      res,
      RegExp(r'^ic_launcher_round\.(png|webp|xml)$'),
    )) {
      ws.delete(f);
    }

    // Its adaptive-background colour lived in values/colors.xml.
    final colors = '$res/values/colors.xml';
    final xml = ws.readText(colors);
    if (xml != null) {
      final re = RegExp(
        r'[ \t]*<color\s+name="ic_launcher_background"[^>]*>[^<]*</color>\s*',
      );
      if (re.hasMatch(xml)) {
        final rest = xml.replaceFirst(re, '');
        final hasOthers = RegExp(
          r'<(color|string|item|style|dimen|bool|integer)\b',
        ).hasMatch(rest);
        if (hasOthers) {
          ws.writeText(colors, rest);
        } else {
          ws.delete(colors);
        }
      }
    }

    // `android: "my_icon"` in flutter_launcher_icons config used a custom name.
    if (customName != null) {
      final n = RegExp.escape(customName);
      for (final f in ws.findFiles(res, RegExp('^$n\\.(png|webp|xml)\$'))) {
        ws.delete(f);
      }
      for (final f in ws.findFiles(
        res,
        RegExp('^${n}_foreground\\.(png|webp)\$'),
        dirPrefix: 'drawable',
      )) {
        ws.delete(f);
      }
    }
  }

  /// Warns when a configured flavor does not exist in Gradle: Android would
  /// silently ignore `src/<flavor>/res`.
  void _checkGradleFlavors(BrandingConfig c, Workspace ws, Reporter log) {
    if (c.flavors.isEmpty) return;
    final text =
        ws.readText('android/app/build.gradle') ??
        ws.readText('android/app/build.gradle.kts');
    if (text == null) return;
    final i = text.indexOf('productFlavors');
    if (i < 0) {
      log.warn(
        'Flavors are configured but android/app/build.gradle has no '
        'productFlavors block, so Android will ignore the flavor icons/names.',
      );
      return;
    }
    final block = text.substring(i);
    for (final f in c.flavors.keys) {
      final re = RegExp(
        r'''(?:^|[\s"'(])''' + RegExp.escape(f) + r'''(?:["'\s{)])''',
      );
      if (!re.hasMatch(block)) {
        log.warn(
          'Flavor "$f" was not found in productFlavors of '
          'android/app/build.gradle; its res folder will be ignored.',
        );
      }
    }
  }

  void _patchManifest(Workspace ws, Reporter log) {
    const path = 'android/app/src/main/AndroidManifest.xml';
    final xml = ws.readText(path);
    if (xml == null) {
      log.warn('$path not found; app name/icon references not patched.');
      return;
    }
    final m = RegExp(r'<application\b[^>]*>', dotAll: true).firstMatch(xml);
    if (m == null) {
      log.warn('$path has no <application> element.');
      return;
    }
    var tag = m.group(0)!;
    tag = _setAttr(tag, 'android:label', '@string/app_name');
    tag = _setAttr(tag, 'android:icon', '@mipmap/ic_launcher');
    // A leftover round icon would win on many launchers.
    tag = tag.replaceAll(RegExp(r'\s*android:roundIcon="[^"]*"'), '');
    ws.writeText(path, xml.replaceRange(m.start, m.end, tag));
  }

  String _setAttr(String tag, String attr, String value) {
    final re = RegExp('$attr="[^"]*"');
    if (re.hasMatch(tag)) {
      return tag.replaceFirstMapped(re, (_) => '$attr="$value"');
    }
    return tag.replaceFirst(
      '<application',
      '<application\n        $attr="$value"',
    );
  }

  void _setString(String path, String key, String value, Workspace ws) {
    final entry = '<string name="$key">${_escape(value)}</string>';
    final existing = ws.readText(path);
    if (existing == null) {
      ws.writeText(path, '''
<?xml version="1.0" encoding="utf-8"?>
<resources>
    $entry
</resources>
''');
      return;
    }
    final re = RegExp('<string\\s+name="$key"[^>]*>[^<]*</string>');
    if (re.hasMatch(existing)) {
      ws.writeText(path, existing.replaceFirstMapped(re, (_) => entry));
    } else {
      ws.writeText(
        path,
        existing.replaceFirst('</resources>', '    $entry\n</resources>'),
      );
    }
  }

  String _escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll("'", r"\'")
      .replaceAll('"', r'\"')
      .replaceFirstMapped(RegExp(r'^@'), (_) => r'\@');

  /// "pt-BR" / "pt_BR" -> "pt-rBR"; "hi" -> "hi".
  String _qualifier(String locale) {
    final parts = locale.split(RegExp('[-_]'));
    return parts.length == 2
        ? '${parts[0]}-r${parts[1].toUpperCase()}'
        : parts[0];
  }
}
