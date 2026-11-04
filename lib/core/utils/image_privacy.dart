import 'dart:typed_data';

import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_image_compress/flutter_image_compress.dart';

import 'jpeg_metadata.dart';

/// Re-encodes an image to JPEG. Replaceable in tests.
typedef ImageReencoder = Future<Uint8List> Function(Uint8List input);

class ImagePrivacyException implements Exception {
  const ImagePrivacyException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Stage 7.1 (F-2): every photo is passed through [sanitize] immediately
/// before upload (StorageService / ProfileService), regardless of size.
/// Previously metadata was removed only from images above 500 KB, so small
/// photos kept their GPS coordinates.
///
///  1. Re-encode natively to JPEG with `keepExif: false` and the EXIF
///     rotation applied (autoCorrectionAngle), capped at [maxDimension].
///  2. Final, platform-independent pass: [JpegMetadata.strip] removes every
///     metadata segment that survived (keeping only Orientation).
///  3. Verify the result; anything unexpected fails closed (no upload).
class ImagePrivacy {
  ImagePrivacy._();

  static const int maxInputBytes = 25 * 1024 * 1024;
  static const int maxDimension = 2560;
  static const int quality = 88;

  static ImageReencoder reencoder = _nativeReencode;

  static Future<Uint8List> _nativeReencode(Uint8List input) => FlutterImageCompress.compressWithList(
        input,
        minWidth: maxDimension,
        minHeight: maxDimension,
        quality: quality,
        format: CompressFormat.jpeg,
        keepExif: false,
        autoCorrectionAngle: true,
      );

  static Future<Uint8List> sanitize(Uint8List input) async {
    if (input.isEmpty) throw const ImagePrivacyException('This photo is empty. Please choose another one.');
    if (input.lengthInBytes > maxInputBytes) {
      throw const ImagePrivacyException('This photo is too large. Please choose a smaller one.');
    }
    Uint8List encoded;
    try {
      encoded = await reencoder(input);
    } on MissingPluginException {
      encoded = _requireJpeg(input); // no native encoder on this platform: strip losslessly
    } on UnimplementedError {
      encoded = _requireJpeg(input);
    } catch (_) {
      throw const ImagePrivacyException('This photo could not be processed. Please choose a different photo.');
    }
    if (encoded.isEmpty) {
      throw const ImagePrivacyException('This photo could not be processed. Please choose a different photo.');
    }
    final Uint8List clean;
    try {
      clean = JpegMetadata.strip(_requireJpeg(encoded));
      if (!JpegMetadata.inspect(clean).isClean) throw const FormatException('metadata survived');
    } on FormatException {
      throw const ImagePrivacyException('This photo could not be processed. Please choose a different photo.');
    }
    return clean;
  }

  static Uint8List _requireJpeg(Uint8List b) {
    if (!JpegMetadata.isJpeg(b)) {
      throw const ImagePrivacyException('This image format is not supported. Please choose a JPEG, PNG or HEIC photo.');
    }
    return b;
  }
}
