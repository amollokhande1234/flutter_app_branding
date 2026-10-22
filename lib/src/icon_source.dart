import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'config.dart';
import 'image_utils.dart';

/// Loads each source image once and applies per-variant badges.
class IconSource {
  IconSource(this.root);
  final String root;
  final Map<String, img.Image> _cache = {};

  img.Image load(String relPath) => _cache.putIfAbsent(
    relPath,
    () => toSquare(loadImage(p.join(root, relPath))),
  );

  img.Image? forVariant(Variant v) {
    if (v.icon == null) return null;
    var image = load(v.icon!);
    if (v.badge != null) image = applyBadge(image, v.badge!);
    return image;
  }
}
