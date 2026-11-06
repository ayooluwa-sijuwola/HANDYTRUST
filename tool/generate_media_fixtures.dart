// Generates the SYNTHETIC image fixtures used by the RumptyCloud staging media
// tests (functions/test/media_*.test.js). No real or personal images.
//
//   dart run tool/generate_media_fixtures.dart
//
// Output: functions/test/fixtures/media/
import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;

img.Image _gradient(int w, int h) {
  final im = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      im.setPixelRgb(x, y, (x * 255) ~/ w, (y * 255) ~/ h, 160);
    }
  }
  return im;
}

void main() {
  final out = Directory('functions/test/fixtures/media')..createSync(recursive: true);
  void write(String name, List<int> bytes) {
    File('${out.path}/$name').writeAsBytesSync(bytes);
    stdout.writeln('$name  ${bytes.length} bytes');
  }

  final small = _gradient(64, 48);
  write('synthetic_64x48.png', img.encodePng(small));
  write('synthetic_64x48.jpg', img.encodeJpg(small, quality: 85));
  write('synthetic_600x400.png', img.encodePng(_gradient(600, 400))); // too large for a thumbnail

  // The image package cannot encode WebP. This is Google's published 1x1
  // lossy WebP feature-detection image; it must decode before it is used.
  final webp = base64Decode('UklGRiIAAABXRUJQVlA4IBYAAAAwAQCdASoBAAEADsD+JaQAA3AAAAAA');
  final decoded = img.decodeWebP(webp);
  if (decoded == null || decoded.width != 1 || decoded.height != 1) {
    stderr.writeln('WebP fixture failed to decode');
    exitCode = 1;
    return;
  }
  write('synthetic_1x1.webp', webp);

  // Every generated fixture must decode again.
  for (final f in out.listSync().whereType<File>()) {
    if (img.decodeImage(f.readAsBytesSync()) == null) {
      stderr.writeln('${f.path} does not decode');
      exitCode = 1;
    }
  }
}
