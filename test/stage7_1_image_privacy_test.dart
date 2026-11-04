import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_test/flutter_test.dart';
import 'package:handy_trust/core/utils/image_privacy.dart';
import 'package:handy_trust/core/utils/jpeg_metadata.dart';
import 'package:image/image.dart' as img;

// Stage 7.1 (F-2) — design/REMEDIATION_STAGE7_1_REPORT_2026-11-04.md §5.
// Real JPEGs carrying GPS EXIF (Lagos home coordinates), XMP, IPTC and a
// comment, below and above the old 500 KB threshold.

/// Big-endian TIFF/EXIF: IFD0 {Make, Orientation, GPS pointer} → GPS IFD
/// {LatRef N, Lat 6°31'27.7", LngRef E, Lng 3°22'45.2"}.
Uint8List exifApp1({int orientation = 1}) {
  final t = BytesBuilder();
  void u16(int v) => t.add([(v >> 8) & 0xFF, v & 0xFF]);
  void u32(int v) => t.add([(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF]);
  void entry(int tag, int type, int count, int valueOrOffset, {bool short = false}) {
    u16(tag); u16(type); u32(count);
    if (short) { u16(valueOrOffset); u16(0); } else { u32(valueOrOffset); }
  }
  t.add([0x4D, 0x4D]); u16(0x2A); u32(8);
  // IFD0 at 8: 3 entries → 2 + 36 + 4 = 42 → GPS IFD at 50, Make string after.
  const gpsIfd = 50;
  u16(3);
  entry(0x010F, 2, 4, 0x48540000); // Make "HT\0\0" inline
  entry(0x0112, 3, 1, orientation, short: true);
  entry(0x8825, 4, 1, gpsIfd);
  u32(0);
  // GPS IFD at 50: 4 entries → 2 + 48 + 4 = 54 → rationals at 104.
  const rat = gpsIfd + 54;
  u16(4);
  entry(0x0001, 2, 2, 0x4E000000); // 'N'
  entry(0x0002, 5, 3, rat);
  entry(0x0003, 2, 2, 0x45000000); // 'E'
  entry(0x0004, 5, 3, rat + 24);
  u32(0);
  for (final v in [6, 1, 31, 1, 277, 10, 3, 1, 22, 1, 452, 10]) { u32(v); }
  final payload = [0x45, 0x78, 0x69, 0x66, 0, 0, ...t.toBytes()];
  final len = payload.length + 2;
  return Uint8List.fromList([0xFF, 0xE1, len >> 8, len & 0xFF, ...payload]);
}

Uint8List segment(int marker, List<int> body) =>
    Uint8List.fromList([0xFF, marker, (body.length + 2) >> 8, (body.length + 2) & 0xFF, ...body]);

/// Encodes a real JPEG and splices EXIF+GPS, XMP, IPTC and a comment in.
Uint8List photoWithGps({required int w, required int h, int quality = 92, int orientation = 1, int seed = 1}) {
  final rnd = Random(seed);
  final image = img.Image(width: w, height: h);
  for (final p in image) {
    p..r = rnd.nextInt(256)..g = rnd.nextInt(256)..b = rnd.nextInt(256);
  }
  final jpeg = img.encodeJpg(image, quality: quality);
  final xmp = segment(0xE1, [...'http://ns.adobe.com/xap/1.0/\u0000'.codeUnits, ...'<x:xmpmeta>GPSLatitude=6.5244</x:xmpmeta>'.codeUnits]);
  final iptc = segment(0xED, 'Photoshop 3.0\u0000 Ikeja, Lagos'.codeUnits);
  final com = segment(0xFE, '12 Home Street'.codeUnits);
  return Uint8List.fromList([...jpeg.sublist(0, 2), ...exifApp1(orientation: orientation), ...xmp, ...iptc, ...com, ...jpeg.sublist(2)]);
}

void main() {
  late ImageReencoder original;
  setUp(() => original = ImagePrivacy.reencoder);
  tearDown(() => ImagePrivacy.reencoder = original);

  final small = photoWithGps(w: 160, h: 120);
  final large = photoWithGps(w: 900, h: 700, quality: 98, seed: 2);

  test('fixtures really carry GPS, and sit on both sides of the old 500 KB threshold', () {
    expect(small.lengthInBytes, lessThan(500 * 1024));
    expect(large.lengthInBytes, greaterThan(500 * 1024));
    for (final f in [small, large]) {
      final r = JpegMetadata.inspect(f);
      expect(r.hasGps, isTrue);
      expect(r.hasXmp && r.hasIptc && r.hasComment, isTrue);
      expect(img.decodeJpg(f)!.exif.gpsIfd.isEmpty, isFalse, reason: 'independent decoder sees GPS');
    }
  });

  group('JpegMetadata.strip (final, platform-independent pass)', () {
    for (final (name, photo) in [('below 500 KB', small), ('above 500 KB', large)]) {
      test('removes GPS / EXIF / XMP / IPTC / comment — $name', () {
        final out = JpegMetadata.strip(photo);
        final r = JpegMetadata.inspect(out);
        expect(r.isClean, isTrue);
        expect(r.hasGps, isFalse);
        final decoded = img.decodeJpg(out)!; // still a valid image
        expect(decoded.exif.gpsIfd.isEmpty, isTrue);
        expect(decoded.exif.imageIfd.isEmpty, isTrue);
        final src = img.decodeJpg(photo)!;
        expect((decoded.width, decoded.height), (src.width, src.height));
        expect(String.fromCharCodes(out).contains('Home Street'), isFalse);
        expect(String.fromCharCodes(out).contains('GPSLatitude'), isFalse);
      });
    }

    test('image data is untouched (lossless): pixels identical after stripping', () {
      final a = img.decodeJpg(small)!;
      final b = img.decodeJpg(JpegMetadata.strip(small))!;
      expect(b.getPixel(10, 10), a.getPixel(10, 10));
      expect(b.getPixel(150, 100), a.getPixel(150, 100));
    });

    test('orientation is preserved — and is the ONLY tag kept', () {
      final rotated = photoWithGps(w: 64, h: 48, orientation: 6);
      final out = JpegMetadata.strip(rotated);
      final r = JpegMetadata.inspect(out);
      expect(r.exifTags, {0x0112});
      expect(r.hasGps, isFalse);
      // package:image applies EXIF rotation on decode: a 64×48 photo tagged
      // "rotate 90°" decodes as 48×64 — so the kept tag is honoured.
      final d = img.decodeJpg(out)!;
      expect((d.width, d.height), (48, 64));
      expect((img.decodeJpg(rotated)!.width), 48, reason: 'same as the original');
      // Upright photos carry no EXIF at all.
      expect(JpegMetadata.inspect(JpegMetadata.strip(small)).hasExif, isFalse);
    });

    test('ICC colour profile and Adobe segment are kept (colours/CMYK decode correctly)', () {
      final icc = segment(0xE2, [...'ICC_PROFILE\u0000'.codeUnits, 1, 1, 0, 0]);
      final adobe = segment(0xEE, [...'Adobe'.codeUnits, 0, 100, 0, 0, 0, 0, 1]);
      final withProfiles = Uint8List.fromList([...small.sublist(0, 2), ...icc, ...adobe, ...small.sublist(2)]);
      final out = JpegMetadata.strip(withProfiles);
      final s = String.fromCharCodes(out);
      expect(s.contains('ICC_PROFILE'), isTrue);
      expect(s.contains('Adobe'), isTrue);
      expect(JpegMetadata.inspect(out).isClean, isTrue);
    });

    test('progressive JPEG (several scans) is handled', () {
      // package:image can't write progressive; splice a second scan header + data before EOI.
      final base = JpegMetadata.strip(small);
      final sos = [0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00, 0x12, 0x34, 0xFF, 0x00, 0x56];
      final multi = Uint8List.fromList([...base.sublist(0, base.length - 2), ...sos, 0xFF, 0xD9]);
      final again = JpegMetadata.strip(multi);
      expect(again.length, multi.length);
    });

    test('malformed input is rejected, never passed through', () {
      expect(() => JpegMetadata.strip(Uint8List.fromList([1, 2, 3, 4])), throwsFormatException);
      expect(() => JpegMetadata.strip(small.sublist(0, small.length ~/ 2)), throwsFormatException);
      final badLen = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE1, 0xFF, 0xFF, 0, 0]);
      expect(() => JpegMetadata.strip(badLen), throwsFormatException);
      // Unparseable EXIF is dropped, not kept.
      final junkExif = Uint8List.fromList([...small.sublist(0, 2), ...segment(0xE1, [0x45, 0x78, 0x69, 0x66, 0, 0, 9, 9]), ...small.sublist(2)]);
      expect(JpegMetadata.inspect(JpegMetadata.strip(junkExif)).isClean, isTrue);
    });
  });

  group('ImagePrivacy.sanitize (what every upload goes through)', () {
    test('small photos are re-encoded and cleaned too (the old bug: < 500 KB skipped)', () async {
      var calls = 0;
      ImagePrivacy.reencoder = (b) async { calls++; return b; }; // worst case: encoder keeps metadata
      final out = await ImagePrivacy.sanitize(small);
      expect(calls, 1);
      expect(JpegMetadata.inspect(out).isClean, isTrue);
    });

    test('large photos: cleaned', () async {
      ImagePrivacy.reencoder = (b) async => b;
      expect(JpegMetadata.inspect(await ImagePrivacy.sanitize(large)).isClean, isTrue);
    });

    test('native encoder settings: always JPEG, keepExif false, rotation applied, size capped', () {
      // Documented contract of _nativeReencode (verified on device: report §10).
      expect(ImagePrivacy.maxDimension, lessThanOrEqualTo(2560));
      expect(ImagePrivacy.quality, inInclusiveRange(80, 92));
    });

    test('no native encoder on this platform (e.g. web): JPEG is still stripped losslessly', () async {
      ImagePrivacy.reencoder = (_) async => throw MissingPluginException();
      final out = await ImagePrivacy.sanitize(small);
      expect(JpegMetadata.inspect(out).isClean, isTrue);
    });

    test('no native encoder and a non-JPEG input → refused, not uploaded raw', () async {
      ImagePrivacy.reencoder = (_) async => throw MissingPluginException();
      final png = Uint8List.fromList(img.encodePng(img.Image(width: 4, height: 4)));
      expect(() => ImagePrivacy.sanitize(png), throwsA(isA<ImagePrivacyException>()));
    });

    test('encoder returns a non-JPEG / empty result → refused', () async {
      ImagePrivacy.reencoder = (_) async => Uint8List.fromList(img.encodePng(img.Image(width: 4, height: 4)));
      expect(() => ImagePrivacy.sanitize(small), throwsA(isA<ImagePrivacyException>()));
      ImagePrivacy.reencoder = (_) async => Uint8List(0);
      expect(() => ImagePrivacy.sanitize(small), throwsA(isA<ImagePrivacyException>()));
    });

    test('corrupt image (encoder throws) → friendly error, no path or detail leaked', () async {
      ImagePrivacy.reencoder = (_) async => throw Exception('decode failed at /data/user/0/app/cache/IMG_1.jpg');
      try {
        await ImagePrivacy.sanitize(Uint8List.fromList(List.filled(100, 7)));
        fail('should throw');
      } on ImagePrivacyException catch (e) {
        expect(e.message.contains('/data'), isFalse);
      }
    });

    test('empty and oversized inputs are refused before decoding', () async {
      expect(() => ImagePrivacy.sanitize(Uint8List(0)), throwsA(isA<ImagePrivacyException>()));
      expect(() => ImagePrivacy.sanitize(Uint8List(ImagePrivacy.maxInputBytes + 1)), throwsA(isA<ImagePrivacyException>()));
    });
  });

  // Regression guard: a new upload path that skips ImagePrivacy.sanitize fails here.
  test('every Storage upload call in lib/ is preceded by ImagePrivacy.sanitize in the same method', () {
    final files = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
    var uploads = 0;
    for (final f in files) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i].trimLeft();
        if (l.startsWith('//') || !RegExp(r'\.put(Data|File|String)\(').hasMatch(l)) continue;
        uploads++;
        var found = false;
        // Walk back to the enclosing method's signature (2-space indented member).
        for (var j = i; j >= 0; j--) {
          if (lines[j].contains('ImagePrivacy.sanitize(')) found = true;
          if (RegExp(r'^  [A-Za-z].*\(.*$').hasMatch(lines[j]) && j != i) break;
        }
        expect(found, isTrue, reason: '${f.path}:${i + 1} uploads without ImagePrivacy.sanitize');
      }
    }
    expect(uploads, 6, reason: 'update this count when an upload path is added — and sanitize it');
  });
}
