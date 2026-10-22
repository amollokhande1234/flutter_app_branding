# flutter_app_branding

Change your Flutter app's **icon**, **name**, **localized names** and
**flavors** from **one YAML file** with **one command**.

```bash
dart run flutter_app_branding
```

- One file instead of two tools: set the name and the icon together.
- Android, iOS, web, Windows and macOS.
- Safe by default: `--dry-run` to preview, automatic backups, `revert` to undo.
- Already using `flutter_launcher_icons`? It cleans up after it. See
  [Coming from flutter_launcher_icons](#coming-from-flutter_launcher_icons).

> Early release (0.1.0). Please
> [report issues](https://github.com/YOUR_GITHUB_USERNAME/flutter_app_branding/issues)
> you run into.

## Quick start

**1. Install**

```bash
flutter pub add --dev flutter_app_branding
```

**2. Create the config.** Run the command once. It creates
`flutter_app_branding.yaml` in your project root, pre-filled with your app name,
a detected icon and only the platforms you have, then stops:

```bash
dart run flutter_app_branding
```

**3. Edit the file, then run the command again.**

```yaml
flutter_app_branding:
  name: "My App"
  icon: assets/icon.png      # square PNG, 1024x1024 recommended
  platforms: [android, ios]
```

```bash
dart run flutter_app_branding
```

That is the whole workflow. To change the icon or name later, edit the file (or
replace the image) and run the same command again.

Prefer no file? This also works and saves the file for next time:

```bash
dart run flutter_app_branding --name "My App" --icon assets/icon.png
```

## Configuration

You can keep the settings in `flutter_app_branding.yaml` or in a
`flutter_app_branding:` block inside `pubspec.yaml`.

| Key | Required | What it does |
|---|---|---|
| `name` | yes | The app name shown under the icon. |
| `icon` | recommended | Path to a square PNG or JPG (1024x1024 is best). |
| `platforms` | no | Any of `android`, `ios`, `web`, `windows`, `macos`. Default: all. Platforms without a folder are skipped. |
| `localized_names` | no | Name per language, for example `hi: "माय ऐप"`. Android only. |
| `flavors` | no | Per-flavor `name`, `icon` and `badge`. See [Flavors](#flavors). |
| `adaptive_icon` | no | Android adaptive icon `background` (color like `"#FFFFFF"` or image), `foreground` and `monochrome`. Built from `icon` automatically if omitted; set `adaptive_icon: false` to turn that off. |

Full example:

```yaml
flutter_app_branding:
  name: "My App"
  icon: assets/icon.png
  platforms: [android, ios, web, windows, macos]

  localized_names:
    hi: "माय ऐप"
    es: "Mi App"
    pt-BR: "Meu App"

  flavors:
    dev:
      name: "My App Dev"
      icon: assets/icon_dev.png
      badge: "DEV"
    prod:
      name: "My App"

  adaptive_icon:
    background: "#FFFFFF"
    foreground: assets/icon_foreground.png
    monochrome: assets/icon_monochrome.png
```

## Flavors

A flavor is a separate build of the same app (for example `dev` and `prod`)
with its own name and icon, so you can install both side by side.

**1. Define the flavors in Android.** Names must match your config exactly.
In `android/app/build.gradle`:

```groovy
android {
    flavorDimensions "env"
    productFlavors {
        dev  { dimension "env"; applicationIdSuffix ".dev" }
        prod { dimension "env" }
    }
}
```

(Kotlin `build.gradle.kts`: `create("dev") { dimension = "env"; applicationIdSuffix = ".dev" }`.)

**2. Add the flavors to the config** (see the example above). `badge: "DEV"`
draws a red ribbon on the icon so testers can tell builds apart.

**3. Apply and run each flavor:**

```bash
dart run flutter_app_branding
flutter run --flavor dev
flutter run --flavor prod
```

If a flavor is in your config but not in `build.gradle`, the tool warns you.

## Coming from flutter_launcher_icons

Nothing conflicts. When you run the command, the tool:

1. **Asks you to remove the old tool.** It tells you to delete
   `flutter_launcher_icons` from `dev_dependencies`, delete its config
   (the `flutter_launcher_icons:` block or `flutter_launcher_icons.yaml`) and
   run `flutter pub get`. It never edits your `pubspec.yaml`.
2. **Removes the Android files the old tool generated** that would override
   the new icon: the old adaptive icon XML, `drawable-*/ic_launcher_foreground`,
   `.webp` icons, round icons, the `ic_launcher_background` color, and icons
   under a custom name (`android: "my_icon"`). They are backed up first.
3. **Overwrites the shared icon files** (same names) with the new ones.

To convert your old settings into this format:

```bash
dart run flutter_app_branding migrate --write
```

The same applies to `rename_app` and similar name tools.

## Commands

| Command | What it does |
|---|---|
| `dart run flutter_app_branding` | Same as `apply`. |
| `apply --dry-run` | Shows exactly which files would change. Writes nothing. |
| `apply --clean` | Applies, then runs `flutter clean` and `flutter pub get`. |
| `apply -P android` | Only the listed platforms. |
| `revert` | Restores the files changed by the last `apply`. |
| `validate` | Checks the config and images only. |
| `doctor` | Finds missing platform folders, old tools and config problems. |
| `init` | Creates a pre-filled config. |
| `migrate [--write]` | Converts a `flutter_launcher_icons` config. |
| `preview` | Writes a contact sheet of your icon in circle, rounded and square masks to `.flutter_app_branding/preview.png`. |

Options that apply to every command: `--project/-p` (project folder),
`--config/-c` (config file), `--json` (machine-readable output and exit codes
for CI).

Running the command twice changes nothing the second time.

## What changes on each platform

| Platform | Name | Icon |
|---|---|---|
| Android | `strings.xml`, manifest label | All densities, adaptive + Android 13 themed icon |
| iOS | `Info.plist` display name | All required sizes (alpha removed automatically) |
| Web | page title, `manifest.json` | favicon, normal and maskable icons |
| Windows | window title, file properties | multi-size `app_icon.ico` |
| macOS | `PRODUCT_NAME` | all required sizes |

## Good to know

- **Localized names are Android only.** iOS needs Xcode project edits that this
  tool does not make.
- **iOS flavors:** icon sets are generated as `AppIcon-<flavor>`; point each
  build configuration at its set in Xcode (`ASSETCATALOG_COMPILER_APPICON_NAME`).
  Per-flavor iOS names are not automated.
- The flavor badge is drawn on the standard icon, not the Android adaptive
  foreground.
- Linux is not supported.
- Add `.flutter_app_branding/` to your `.gitignore` (backups and previews live
  there).

## Troubleshooting

**The icon did not change on my device.** Launchers cache icons. Uninstall the
app, then run `flutter clean` and run it again (or use `apply --clean`).

**Android still shows an old adaptive icon.** An older tool left a file that
overrides the new one. Run the command: it removes those leftovers. If you set
`adaptive_icon: false`, it also removes the old adaptive XML.

**Something went wrong.** Run `dart run flutter_app_branding revert`.

## License

MIT. See [LICENSE](LICENSE).
