import 'dart:typed_data';

/// Stage 7.1 (F-2): lossless JPEG metadata removal. Pure Dart (no plugins),
/// so it runs identically on every platform and is unit-tested
/// (test/stage7_1_image_privacy_test.dart).
///
/// Kept: everything needed to decode and display the image — quantization
/// and Huffman tables, frame/scan headers, entropy-coded data, JFIF (APP0),
/// the ICC colour profile (APP2 "ICC_PROFILE") and Adobe colour transform
/// (APP14 "Adobe"). Dropped: EXIF (incl. GPS), XMP, IPTC/Photoshop, comments
/// and every other application segment. When [keepOrientation] is true, a
/// minimal EXIF block containing ONLY the Orientation tag is written back so
/// a photo that wasn't rotated by the encoder still displays upright.
class JpegMetadata {
  JpegMetadata._();

  static bool isJpeg(Uint8List b) => b.length >= 4 && b[0] == 0xFF && b[1] == 0xD8;

  static Uint8List strip(Uint8List src, {bool keepOrientation = true}) {
    final segments = _segments(src);
    final orientation = keepOrientation ? _orientationFrom(segments) : null;
    final out = BytesBuilder(copy: false)..add(const [0xFF, 0xD8]);
    var wroteOrientation = false;
    void writeOrientation() {
      if (orientation != null && orientation >= 2 && orientation <= 8 && !wroteOrientation) {
        out.add(_minimalOrientationApp1(orientation));
        wroteOrientation = true;
      }
    }

    var first = true;
    for (final s in segments) {
      if (first && s.marker != 0xE0) writeOrientation();
      first = false;
      if (_keep(s)) out.add(s.bytes);
      if (s.marker == 0xE0) writeOrientation(); // right after JFIF
    }
    return out.toBytes();
  }

  /// What metadata a JPEG carries. Used to verify [strip]'s output.
  static JpegMetadataReport inspect(Uint8List src) {
    final segs = _segments(src);
    final exifTags = <int>{};
    var hasGps = false;
    var hasExif = false;
    var hasXmp = false;
    var hasIptc = false;
    var hasComment = false;
    var otherApp = false;
    for (final s in segs) {
      if (s.marker == 0xE1 && _startsWith(s.payload, _exifId)) {
        hasExif = true;
        final tags = _ifd0Tags(s.payload.sublist(6));
        exifTags.addAll(tags);
        if (tags.contains(0x8825)) hasGps = true;
      } else if (s.marker == 0xE1) {
        hasXmp = true;
      } else if (s.marker == 0xED) {
        hasIptc = true;
      } else if (s.marker == 0xFE) {
        hasComment = true;
      } else if (s.marker >= 0xE0 && s.marker <= 0xEF && !_keep(s)) {
        otherApp = true;
      }
    }
    return JpegMetadataReport(
      hasExif: hasExif, exifTags: exifTags, hasGps: hasGps, hasXmp: hasXmp,
      hasIptc: hasIptc, hasComment: hasComment, hasOtherAppSegments: otherApp,
    );
  }

  static const _exifId = [0x45, 0x78, 0x69, 0x66, 0x00, 0x00]; // "Exif\0\0"
  static const _iccId = [0x49, 0x43, 0x43, 0x5F, 0x50, 0x52, 0x4F, 0x46, 0x49, 0x4C, 0x45, 0x00]; // ICC_PROFILE\0
  static const _adobeId = [0x41, 0x64, 0x6F, 0x62, 0x65]; // Adobe
  static const _jfifId = [0x4A, 0x46, 0x49, 0x46, 0x00]; // JFIF\0
  static const _jfxxId = [0x4A, 0x46, 0x58, 0x58, 0x00]; // JFXX\0

  static bool _keep(_Segment s) {
    final m = s.marker;
    if (m == 0xFE) return false; // COM
    if (m < 0xE0 || m > 0xEF) return true; // not an application segment
    if (m == 0xE0) return _startsWith(s.payload, _jfifId) || _startsWith(s.payload, _jfxxId);
    if (m == 0xE2) return _startsWith(s.payload, _iccId);
    if (m == 0xEE) return _startsWith(s.payload, _adobeId);
    return false; // APP1 (EXIF/XMP), APP13 (IPTC), MPF, maker data, …
  }

  static bool _startsWith(Uint8List b, List<int> prefix) {
    if (b.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (b[i] != prefix[i]) return false;
    }
    return true;
  }

  /// Splits into marker segments; entropy-coded data is attached to the
  /// segment before it (SOS), so progressive JPEGs with several scans work.
  static List<_Segment> _segments(Uint8List b) {
    if (!isJpeg(b)) throw const FormatException('Not a JPEG image');
    final segs = <_Segment>[];
    var i = 2;
    while (i < b.length) {
      if (b[i] != 0xFF) throw const FormatException('Malformed JPEG (expected a marker)');
      while (i < b.length && b[i] == 0xFF) {
        i++; // fill bytes
      }
      if (i >= b.length) throw const FormatException('Malformed JPEG (truncated marker)');
      final m = b[i];
      final start = i - 1;
      if (m == 0xD9) {
        segs.add(_Segment(m, Uint8List.sublistView(b, start, i + 1), Uint8List(0)));
        return segs;
      }
      if (m == 0x01 || (m >= 0xD0 && m <= 0xD7)) {
        segs.add(_Segment(m, Uint8List.sublistView(b, start, i + 1), Uint8List(0)));
        i++;
        continue;
      }
      if (i + 2 >= b.length) throw const FormatException('Malformed JPEG (truncated length)');
      final len = (b[i + 1] << 8) | b[i + 2];
      final end = i + 1 + len;
      if (len < 2 || end > b.length) throw const FormatException('Malformed JPEG (segment overruns file)');
      var segEnd = end;
      if (m == 0xDA) {
        // Entropy-coded data runs until the next real marker (not stuffing, not RSTn).
        var j = end;
        while (j + 1 < b.length) {
          if (b[j] == 0xFF && b[j + 1] != 0x00 && !(b[j + 1] >= 0xD0 && b[j + 1] <= 0xD7) && b[j + 1] != 0xFF) break;
          j++;
        }
        if (j + 1 >= b.length) throw const FormatException('Malformed JPEG (no end of image)');
        segEnd = j;
      }
      segs.add(_Segment(m, Uint8List.sublistView(b, start, segEnd), Uint8List.sublistView(b, i + 3, end)));
      i = segEnd;
    }
    throw const FormatException('Malformed JPEG (no end of image)');
  }

  static int? _orientationFrom(List<_Segment> segs) {
    for (final s in segs) {
      if (s.marker == 0xE1 && _startsWith(s.payload, _exifId)) {
        try {
          final tiff = s.payload.sublist(6);
          final r = _TiffReader(tiff);
          final ifd = r.u32(4);
          final n = r.u16(ifd);
          for (var k = 0; k < n; k++) {
            final e = ifd + 2 + k * 12;
            if (r.u16(e) == 0x0112) return r.u16(e + 8);
          }
        } catch (_) {
          return null; // unreadable EXIF: drop it, orientation unknown
        }
      }
    }
    return null;
  }

  static Set<int> _ifd0Tags(Uint8List tiff) {
    try {
      final r = _TiffReader(tiff);
      final ifd = r.u32(4);
      final n = r.u16(ifd);
      return {for (var k = 0; k < n; k++) r.u16(ifd + 2 + k * 12)};
    } catch (_) {
      return {-1}; // unparseable EXIF counts as "has tags"
    }
  }

  static Uint8List _minimalOrientationApp1(int orientation) {
    final tiff = <int>[
      0x4D, 0x4D, 0x00, 0x2A, 0x00, 0x00, 0x00, 0x08, // big-endian header, IFD0 at 8
      0x00, 0x01, // one entry
      0x01, 0x12, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01, // Orientation, SHORT, count 1
      (orientation >> 8) & 0xFF, orientation & 0xFF, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, // no next IFD
    ];
    final payload = [..._exifId, ...tiff];
    final len = payload.length + 2;
    return Uint8List.fromList([0xFF, 0xE1, (len >> 8) & 0xFF, len & 0xFF, ...payload]);
  }
}

class JpegMetadataReport {
  const JpegMetadataReport({
    required this.hasExif, required this.exifTags, required this.hasGps, required this.hasXmp,
    required this.hasIptc, required this.hasComment, required this.hasOtherAppSegments,
  });
  final bool hasExif;
  final Set<int> exifTags;
  final bool hasGps;
  final bool hasXmp;
  final bool hasIptc;
  final bool hasComment;
  final bool hasOtherAppSegments;

  /// True when nothing but (at most) an Orientation tag remains.
  bool get isClean =>
      !hasGps && !hasXmp && !hasIptc && !hasComment && !hasOtherAppSegments &&
      exifTags.difference({0x0112}).isEmpty;
}

class _Segment {
  _Segment(this.marker, this.bytes, this.payload);
  final int marker;
  final Uint8List bytes; // whole segment incl. marker (and scan data for SOS)
  final Uint8List payload; // segment body after the length field
}

class _TiffReader {
  _TiffReader(this.b) {
    if (b.length < 8) throw const FormatException('short TIFF');
    if (b[0] == 0x49 && b[1] == 0x49) {
      little = true;
    } else if (b[0] == 0x4D && b[1] == 0x4D) {
      little = false;
    } else {
      throw const FormatException('bad TIFF byte order');
    }
  }
  final Uint8List b;
  late final bool little;
  int u16(int o) {
    if (o < 0 || o + 2 > b.length) throw const FormatException('TIFF overrun');
    return little ? b[o] | (b[o + 1] << 8) : (b[o] << 8) | b[o + 1];
  }

  int u32(int o) {
    if (o < 0 || o + 4 > b.length) throw const FormatException('TIFF overrun');
    return little
        ? b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)
        : (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
  }
}
