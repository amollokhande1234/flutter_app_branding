import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Thrown for problems the user can fix: bad config, missing images, etc.
class BrandingException implements Exception {
  BrandingException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Thrown when no config exists yet (lets `apply --name --icon` bootstrap one).
class MissingConfigException extends BrandingException {
  MissingConfigException(super.message);
}

/// Platforms this package can brand.
const supportedPlatforms = ['android', 'ios', 'web', 'windows', 'macos'];

/// Android adaptive-icon layers (Android 8+, plus the Android 13 themed icon).
class AdaptiveIcon {
  const AdaptiveIcon({this.background, this.foreground, this.monochrome});

  /// "#RRGGBB" / "#AARRGGBB" or a path to an image.
  final String? background;
  final String? foreground;
  final String? monochrome;

  static final _hex = RegExp(r'^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$');
  bool get backgroundIsColor =>
      background != null && _hex.hasMatch(background!);
}

/// One concrete name + icon combination (the main app, or a flavor).
class Variant {
  const Variant({this.flavor, required this.name, this.icon, this.badge});
  final String? flavor;
  final String name;
  final String? icon;
  final String? badge;
}

/// The parsed `flutter_app_branding` configuration.
class BrandingConfig {
  BrandingConfig({
    required this.name,
    this.icon,
    this.adaptive,
    this.platforms = supportedPlatforms,
    this.flavors = const {},
    this.localizedNames = const {},
    this.autoAdaptive = true,
  });

  final String name;
  final String? icon;
  final AdaptiveIcon? adaptive;
  final List<String> platforms;
  final Map<String, Variant> flavors;
  final Map<String, String> localizedNames;

  /// Build an Android adaptive icon automatically when none is configured.
  /// Disable with `adaptive_icon: false`.
  final bool autoAdaptive;

  BrandingConfig copyWith({String? name, String? icon}) => BrandingConfig(
    name: name ?? this.name,
    icon: icon ?? this.icon,
    adaptive: adaptive,
    platforms: platforms,
    flavors: flavors,
    localizedNames: localizedNames,
    autoAdaptive: autoAdaptive,
  );

  /// Main variant first, then flavors.
  List<Variant> get variants => [
    Variant(name: name, icon: icon),
    ...flavors.values,
  ];

  factory BrandingConfig.fromMap(Map<String, dynamic> m) {
    String? s(dynamic v) => v?.toString();

    final name = s(m['name']);
    if (name == null || name.trim().isEmpty) {
      throw BrandingException('flutter_app_branding: "name" is required.');
    }

    AdaptiveIcon? adaptive;
    final a = m['adaptive_icon'];
    if (a is Map) {
      adaptive = AdaptiveIcon(
        background: s(a['background']),
        foreground: s(a['foreground']),
        monochrome: s(a['monochrome']),
      );
    }

    final platforms =
        (m['platforms'] as List?)
            ?.map((e) => e.toString().toLowerCase())
            .toList() ??
        List<String>.from(supportedPlatforms);

    final flavors = <String, Variant>{};
    final f = m['flavors'];
    if (f is Map) {
      f.forEach((key, value) {
        final fm = value is Map ? value : const {};
        flavors['$key'] = Variant(
          flavor: '$key',
          name: s(fm['name']) ?? name,
          icon: s(fm['icon']) ?? s(m['icon']),
          badge: s(fm['badge']),
        );
      });
    }

    final locales = <String, String>{};
    final l = m['localized_names'];
    if (l is Map) {
      l.forEach((k, v) => locales['$k'] = '$v');
    }

    return BrandingConfig(
      name: name,
      icon: s(m['icon']),
      adaptive: adaptive,
      platforms: platforms,
      flavors: flavors,
      localizedNames: locales,
      autoAdaptive: m['adaptive_icon'] != false,
    );
  }

  /// Looks for [file], else flutter_app_branding.yaml, else an `flutter_app_branding:` block
  /// in pubspec.yaml.
  static BrandingConfig load(String root, {String? file}) {
    final path = file != null
        ? (p.isAbsolute(file) ? file : p.join(root, file))
        : p.join(root, 'flutter_app_branding.yaml');
    final f = File(path);
    if (f.existsSync()) {
      final doc = _plain(loadYaml(f.readAsStringSync()));
      if (doc is! Map) {
        throw BrandingException('$path: expected a YAML map.');
      }
      final section = doc['flutter_app_branding'] is Map
          ? Map<String, dynamic>.from(doc['flutter_app_branding'] as Map)
          : Map<String, dynamic>.from(doc);
      return BrandingConfig.fromMap(section);
    }
    if (file != null) {
      throw BrandingException('Config file not found: $path');
    }

    final pubspec = File(p.join(root, 'pubspec.yaml'));
    if (pubspec.existsSync()) {
      final doc = _plain(loadYaml(pubspec.readAsStringSync()));
      if (doc is Map && doc['flutter_app_branding'] is Map) {
        return BrandingConfig.fromMap(
          Map<String, dynamic>.from(doc['flutter_app_branding'] as Map),
        );
      }
    }
    throw MissingConfigException(
      'No configuration found. Run: dart run flutter_app_branding --name "My App" '
      '--icon assets/icon.png   (or `init`, or add an "flutter_app_branding:" block '
      'to pubspec.yaml).',
    );
  }
}

dynamic _plain(dynamic v) {
  if (v is YamlMap) {
    return {for (final e in v.entries) e.key.toString(): _plain(e.value)};
  }
  if (v is YamlList) return [for (final e in v) _plain(e)];
  return v;
}
