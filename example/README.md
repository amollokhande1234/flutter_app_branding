# Example

1. Add the package to your Flutter app:

   ```bash
   flutter pub add --dev flutter_app_branding
   ```

2. Copy `flutter_app_branding.yaml` from this folder into your project root
   (or just run `dart run flutter_app_branding` once and it creates a
   pre-filled one for you), then point `icon:` at your own PNG.

3. Apply it:

   ```bash
   dart run flutter_app_branding --dry-run   # preview, changes nothing
   dart run flutter_app_branding             # apply
   ```
