import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'config.dart';

/// A problem found while validating the config (error or warning).
class Issue {
  const Issue.error(this.message) : isError = true;
  const Issue.warning(this.message) : isError = false;
  final bool isError;
  final String message;
}

/// Checks the config and every referenced image before anything is written.
List<Issue> validateConfig(BrandingConfig c, String root) {
  final out = <Issue>[];

  for (final pl in c.platforms) {
    if (!supportedPlatforms.contains(pl)) {
      out.add(
        Issue.error(
          'Unknown platform "$pl". Supported: ${supportedPlatforms.join(', ')}.',
        ),
      );
    }
  }

  final a = c.adaptive;
  if (a != null) {
    if (a.foreground == null) {
      out.add(const Issue.error('adaptive_icon.foreground is required.'));
    }
    if (a.background == null) {
      out.add(
        const Issue.error(
          'adaptive_icon.background is required (color like "#FFFFFF" or an image).',
        ),
      );
    }
  }

  final paths = <String>{
    if (c.icon != null) c.icon!,
    for (final f in c.flavors.values)
      if (f.icon != null) f.icon!,
    if (a != null) ...[
      if (a.foreground != null) a.foreground!,
      if (a.monochrome != null) a.monochrome!,
      if (a.background != null && !a.backgroundIsColor) a.background!,
    ],
  };

  for (final path in paths) {
    final file = File(p.join(root, path));
    if (!file.existsSync()) {
      out.add(Issue.error('Image not found: $path'));
      continue;
    }
    final im = img.decodeImage(file.readAsBytesSync());
    if (im == null) {
      out.add(Issue.error('Cannot decode $path (use PNG or JPG).'));
      continue;
    }
    if (im.width != im.height) {
      out.add(
        Issue.warning(
          '$path is ${im.width}x${im.height}, not square; it will be padded with transparency.',
        ),
      );
    }
    if (path == c.icon && im.width < 1024) {
      out.add(
        Issue.warning(
          '$path is ${im.width}px; 1024x1024 is recommended (iOS marketing icon is 1024).',
        ),
      );
    }
  }

  return out;
}
