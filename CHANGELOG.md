## 0.1.0

First release.

- One config file (`flutter_app_branding.yaml` or a block in `pubspec.yaml`) and one command.
- App name and icons for Android, iOS, web, Windows and macOS.
- Android adaptive icon (built automatically) and Android 13 themed icon.
- Flavors with their own name, icon and optional badge (Android; iOS icon sets).
- Localized app names (Android).
- Detects `flutter_launcher_icons` / `rename_app`, asks you to remove them, and
  cleans up the Android files they generated.
- `--dry-run`, automatic backups with `revert`, `validate`, `doctor`, `init`,
  `migrate`, `preview`, and `--json` output for CI.
