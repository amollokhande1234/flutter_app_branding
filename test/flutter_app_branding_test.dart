import 'dart:io';

import 'package:flutter_app_branding/flutter_app_branding.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _manifest = r'''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:label="old"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">
    </application>
</manifest>
''';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('branding_');
    final im = img.Image(width: 1024, height: 1024, numChannels: 4);
    img.fill(im, color: img.ColorRgba8(30, 100, 200, 255));
    File(p.join(dir.path, 'assets/icon/icon.png'))
      ..createSync(recursive: true)
      ..writeAsBytesSync(img.encodePng(im));
    File(p.join(dir.path, 'android/app/src/main/AndroidManifest.xml'))
      ..createSync(recursive: true)
      ..writeAsStringSync(_manifest);
    File(p.join(dir.path, 'flutter_app_branding.yaml')).writeAsStringSync('''
flutter_app_branding:
  name: "Demo App"
  icon: assets/icon/icon.png
  platforms: [android]
''');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('apply writes name and icons, second run is idempotent', () {
    final r1 = Reporter(silent: true);
    expect(runApply(root: dir.path, log: r1), 0);
    expect(r1.changes.any((c) => c.kind != ChangeKind.unchanged), isTrue);

    final strings = File(
      p.join(dir.path, 'android/app/src/main/res/values/strings.xml'),
    ).readAsStringSync();
    expect(strings, contains('Demo App'));
    expect(
      File(
        p.join(
          dir.path,
          'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
        ),
      ).existsSync(),
      isTrue,
    );

    final r2 = Reporter(silent: true);
    expect(runApply(root: dir.path, log: r2), 0);
    expect(r2.changes.every((c) => c.kind == ChangeKind.unchanged), isTrue);
  });

  test('dry run writes nothing', () {
    final r = Reporter(silent: true);
    runApply(root: dir.path, log: r, dryRun: true);
    expect(
      File(p.join(dir.path, 'android/app/src/main/res/values/strings.xml'))
          .existsSync(),
      isFalse,
    );
  });

  test('revert restores the original manifest', () {
    runApply(root: dir.path, log: Reporter(silent: true));
    revertLatest(dir.path);
    final manifest = File(
      p.join(dir.path, 'android/app/src/main/AndroidManifest.xml'),
    ).readAsStringSync();
    expect(manifest, _manifest);
  });

  test('missing icon is a validation error', () {
    File(p.join(dir.path, 'assets/icon/icon.png')).deleteSync();
    final r = Reporter(silent: true);
    expect(runApply(root: dir.path, log: r), 1);
    expect(r.errors.first, contains('Image not found'));
  });

  test(
    'removes stale flutter_launcher_icons adaptive files and can revert',
    () {
      const res = 'android/app/src/main/res';
      final oldXml =
          File(p.join(dir.path, '$res/mipmap-anydpi-v26/ic_launcher.xml'))
            ..createSync(recursive: true)
            ..writeAsStringSync(
              '<adaptive-icon>@drawable/ic_launcher_foreground</adaptive-icon>',
            );
      final oldFg =
          File(
              p.join(dir.path, '$res/drawable-hdpi/ic_launcher_foreground.png'),
            )
            ..createSync(recursive: true)
            ..writeAsBytesSync([1, 2, 3]);

      runApply(root: dir.path, log: Reporter(silent: true));

      expect(oldFg.existsSync(), isFalse);
      expect(
        oldXml.readAsStringSync(),
        contains('@mipmap/ic_launcher_foreground'),
      );

      revertLatest(dir.path);
      expect(oldFg.existsSync(), isTrue);
      expect(
        oldXml.readAsStringSync(),
        contains('@drawable/ic_launcher_foreground'),
      );
    },
  );

  test('--name/--icon bootstrap a config when none exists', () {
    File(p.join(dir.path, 'flutter_app_branding.yaml')).deleteSync();
    final r = Reporter(silent: true);
    expect(
      runApply(
        root: dir.path,
        log: r,
        name: 'Quick App',
        icon: 'assets/icon/icon.png',
      ),
      0,
    );
    expect(
      File(p.join(dir.path, 'flutter_app_branding.yaml')).existsSync(),
      isTrue,
    );
    expect(
      File(p.join(dir.path, 'android/app/src/main/res/values/strings.xml'))
          .readAsStringSync(),
      contains('Quick App'),
    );
  });

  test(
    'first run with no config creates a pre-filled flutter_app_branding.yaml',
    () {
      File(p.join(dir.path, 'flutter_app_branding.yaml')).deleteSync();
      final r = Reporter(silent: true);
      expect(runApply(root: dir.path, log: r), 0);
      final text = File(p.join(dir.path, 'flutter_app_branding.yaml'))
          .readAsStringSync();
      expect(text, contains('platforms: [android]'));
      expect(text, contains('icon: assets/icon/icon.png'));
      // nothing was applied yet
      expect(
        File(p.join(dir.path, 'android/app/src/main/res/values/strings.xml'))
            .existsSync(),
        isFalse,
      );
    },
  );

  String read(String rel) => File(p.join(dir.path, rel)).readAsStringSync();
  bool exists(String rel) => File(p.join(dir.path, rel)).existsSync();

  test('flavors and localized names are written', () {
    File(p.join(dir.path, 'flutter_app_branding.yaml')).writeAsStringSync('''
flutter_app_branding:
  name: "Demo App"
  icon: assets/icon/icon.png
  platforms: [android]
  localized_names:
    hi: "हिंदी"
    pt-BR: "Meu App"
  flavors:
    dev:
      name: "Demo Dev"
      badge: "DEV"
''');
    File(p.join(dir.path, 'android/app/build.gradle'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        'android { productFlavors { dev { dimension "env" } } }',
      );

    final r = Reporter(silent: true);
    expect(runApply(root: dir.path, log: r), 0);

    expect(
      read('android/app/src/dev/res/values/strings.xml'),
      contains('Demo Dev'),
    );
    expect(
      exists('android/app/src/dev/res/mipmap-hdpi/ic_launcher.png'),
      isTrue,
    );
    expect(
      read('android/app/src/main/res/values/strings.xml'),
      contains('Demo App'),
    );
    expect(
      read('android/app/src/main/res/values-hi/strings.xml'),
      contains('हिंदी'),
    );
    expect(
      read('android/app/src/main/res/values-pt-rBR/strings.xml'),
      contains('Meu App'),
    );
    expect(r.warnings.any((w) => w.contains('productFlavors')), isFalse);
  });

  test('warns when a flavor is missing from Gradle', () {
    File(p.join(dir.path, 'flutter_app_branding.yaml')).writeAsStringSync('''
flutter_app_branding:
  name: "Demo App"
  icon: assets/icon/icon.png
  platforms: [android]
  flavors:
    staging:
      name: "Demo Staging"
''');
    File(p.join(dir.path, 'android/app/build.gradle'))
      ..createSync(recursive: true)
      ..writeAsStringSync('android { productFlavors { dev { } } }');
    final r = Reporter(silent: true);
    runApply(root: dir.path, log: r);
    expect(r.warnings.any((w) => w.contains('"staging"')), isTrue);
  });

  test('flutter_launcher_icons leftovers: asks to remove, cleans files, '
      'never edits pubspec', () {
    const pubspec = '''
name: demo
dev_dependencies:
  flutter_launcher_icons: ^0.13.1

flutter_launcher_icons:
  android: "launcher_icon"
  image_path: "assets/icon/icon.png"
''';
    File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync(pubspec);
    const res = 'android/app/src/main/res';
    for (final f in [
      '$res/mipmap-hdpi/launcher_icon.png',
      '$res/mipmap-hdpi/ic_launcher.webp',
      '$res/drawable-hdpi/ic_launcher_foreground.png',
      '$res/mipmap-anydpi-v26/launcher_icon.xml',
    ]) {
      File(p.join(dir.path, f))
        ..createSync(recursive: true)
        ..writeAsStringSync('old');
    }
    File(p.join(dir.path, '$res/values/colors.xml'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        '<resources>\n'
        '    <color name="ic_launcher_background">#ffffff</color>\n'
        '</resources>\n',
      );

    expect(detectLegacy(dir.path).found, isTrue);
    expect(detectLegacy(dir.path).androidIconName, 'launcher_icon');

    final r = Reporter(silent: true);
    expect(runApply(root: dir.path, log: r), 0);

    expect(r.warnings.any((w) => w.contains('flutter_launcher_icons')), isTrue);
    for (final f in [
      '$res/mipmap-hdpi/launcher_icon.png',
      '$res/mipmap-hdpi/ic_launcher.webp',
      '$res/drawable-hdpi/ic_launcher_foreground.png',
      '$res/mipmap-anydpi-v26/launcher_icon.xml',
      '$res/values/colors.xml',
    ]) {
      expect(exists(f), isFalse);
    }
    expect(read('pubspec.yaml'), pubspec); // untouched
  });

  test('colors.xml with other colors keeps them', () {
    const res = 'android/app/src/main/res';
    File(p.join(dir.path, '$res/values/colors.xml'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        '<resources>\n'
        '    <color name="ic_launcher_background">#ffffff</color>\n'
        '    <color name="brand">#123456</color>\n'
        '</resources>\n',
      );
    runApply(root: dir.path, log: Reporter(silent: true));
    final xml = read('$res/values/colors.xml');
    expect(xml, contains('brand'));
    expect(xml.contains('ic_launcher_background'), false);
  });
}
