import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'config.dart';

img.Image loadImage(String path) {
  final file = File(path);
  if (!file.existsSync()) throw BrandingException('Image not found: $path');
  final image = img.decodeImage(file.readAsBytesSync());
  if (image == null) {
    throw BrandingException('Cannot decode image (use PNG or JPG): $path');
  }
  return image.numChannels == 4 ? image : image.convert(numChannels: 4);
}

/// Pads a non-square image with transparency so resizing never distorts it.
img.Image toSquare(img.Image src) {
  if (src.width == src.height) return src;
  final side = math.max(src.width, src.height);
  final canvas = img.Image(width: side, height: side, numChannels: 4);
  img.compositeImage(
    canvas,
    src,
    dstX: (side - src.width) ~/ 2,
    dstY: (side - src.height) ~/ 2,
  );
  return canvas;
}

img.Image resizeTo(img.Image src, int size) => img.copyResize(
  src,
  width: size,
  height: size,
  interpolation: img.Interpolation.cubic,
);

Uint8List pngBytes(img.Image image) => Uint8List.fromList(img.encodePng(image));

({int r, int g, int b, int a}) parseHex(String hex) {
  var h = hex.replaceFirst('#', '');
  var a = 255;
  if (h.length == 8) {
    a = int.parse(h.substring(0, 2), radix: 16);
    h = h.substring(2);
  }
  return (
    r: int.parse(h.substring(0, 2), radix: 16),
    g: int.parse(h.substring(2, 4), radix: 16),
    b: int.parse(h.substring(4, 6), radix: 16),
    a: a,
  );
}

img.Image solid(int size, String hex) {
  final c = parseHex(hex);
  final im = img.Image(width: size, height: size, numChannels: 4);
  img.fill(im, color: img.ColorRgba8(c.r, c.g, c.b, c.a));
  return im;
}

/// iOS rejects icons with an alpha channel: composite onto [bgHex], drop alpha.
img.Image flattenOnto(img.Image src, {String bgHex = '#FFFFFF'}) {
  final canvas = solid(src.width, bgHex);
  img.compositeImage(canvas, src);
  return canvas.convert(numChannels: 3);
}

/// Icon shrunk to 80% and centred on a solid background (web maskable icons).
img.Image maskableIcon(img.Image src, int size, String bgHex) {
  final canvas = solid(size, bgHex);
  final inner = (size * 0.8).round();
  final off = (size - inner) ~/ 2;
  img.compositeImage(canvas, resizeTo(src, inner), dstX: off, dstY: off);
  return canvas;
}

/// Overlays a coloured ribbon with [text] along the bottom (DEV / BETA ...).
img.Image applyBadge(img.Image src, String text) {
  final out = src.clone();
  final w = out.width, h = out.height;
  final bandH = (h * 0.24).round();
  final y0 = h - bandH;
  img.fillRect(
    out,
    x1: 0,
    y1: y0,
    x2: w,
    y2: h,
    color: img.ColorRgba8(200, 30, 30, 230),
  );

  var label = img.Image(
    width: text.length * 34 + 16,
    height: 64,
    numChannels: 4,
  );
  img.drawString(
    label,
    text.toUpperCase(),
    font: img.arial48,
    x: 8,
    y: 4,
    color: img.ColorRgb8(255, 255, 255),
  );
  label = img.trim(label, mode: img.TrimMode.transparent);

  final targetH = (bandH * 0.55).round();
  final targetW = (label.width * targetH / label.height).round();
  final scaled = img.copyResize(
    label,
    width: targetW,
    height: targetH,
    interpolation: img.Interpolation.cubic,
  );
  img.compositeImage(
    out,
    scaled,
    dstX: (w - targetW) ~/ 2,
    dstY: y0 + (bandH - targetH) ~/ 2,
  );
  return out;
}

/// Masks to 'circle', 'rounded' or 'square' (used by `preview`).
img.Image maskShape(img.Image src, String shape) {
  final out = src.clone();
  final n = out.width;
  final r = shape == 'circle'
      ? n / 2
      : shape == 'rounded'
      ? n * 0.22
      : 0.0;
  if (r == 0) return out;
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      if (!_inside(x + 0.5, y + 0.5, n, r)) out.setPixelRgba(x, y, 0, 0, 0, 0);
    }
  }
  return out;
}

bool _inside(double x, double y, int n, double r) {
  final cx = x < r ? r : (x > n - r ? n - r : x);
  final cy = y < r ? r : (y > n - r ? n - r : y);
  final dx = x - cx, dy = y - cy;
  return dx * dx + dy * dy <= r * r;
}

/// Builds a multi-resolution .ico from PNG frames (size -> PNG bytes).
Uint8List buildIco(Map<int, Uint8List> frames) {
  final count = frames.length;
  final headerSize = 6 + 16 * count;
  final total = headerSize + frames.values.fold<int>(0, (a, b) => a + b.length);
  final data = ByteData(total);
  data.setUint16(0, 0, Endian.little);
  data.setUint16(2, 1, Endian.little); // type: icon
  data.setUint16(4, count, Endian.little);
  final out = data.buffer.asUint8List();
  var offset = headerSize;
  var i = 0;
  frames.forEach((size, bytes) {
    final e = 6 + i * 16;
    out[e] = size >= 256 ? 0 : size;
    out[e + 1] = size >= 256 ? 0 : size;
    data.setUint16(e + 4, 1, Endian.little); // planes
    data.setUint16(e + 6, 32, Endian.little); // bits per pixel
    data.setUint32(e + 8, bytes.length, Endian.little);
    data.setUint32(e + 12, offset, Endian.little);
    out.setRange(offset, offset + bytes.length, bytes);
    offset += bytes.length;
    i++;
  });
  return out;
}
