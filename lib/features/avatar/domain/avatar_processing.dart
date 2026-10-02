import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

/// Client-side avatar preparation (US-22): decode, apply EXIF orientation, centre-crop to a square,
/// shrink to at most [avatarMaxSide] px, re-encode as JPEG q~80. Re-encoding into a NEW image drops
/// every metadata block (EXIF/GPS/thumbnail/ICC), so nothing about where the photo was taken is uploaded.
const avatarMaxSide = 512;
const avatarMinSide = 256;

/// Target size (client); the server limit is 512 KB (bucket file_size_limit, 0009).
const avatarTargetBytes = 300 * 1024;
const avatarHardMaxBytes = 512 * 1024;

/// Refuses absurd inputs before decoding (memory): 25 MB.
const avatarMaxInputBytes = 25 * 1024 * 1024;

enum AvatarErrorKind { notImage, tooLarge, tooSmall, unsupported }

class AvatarException implements Exception {
  const AvatarException(this.kind);
  final AvatarErrorKind kind;
  @override
  String toString() => 'AvatarException($kind)';
}

class ProcessedAvatar {
  const ProcessedAvatar(this.bytes, this.width, this.height);
  final Uint8List bytes;
  final int width;
  final int height;
}

bool _looksLikeHeic(Uint8List b) {
  if (b.length < 16) return false;
  final brand = String.fromCharCodes(b.sublist(4, 12));
  return brand.startsWith('ftyp') &&
      (brand.contains('heic') || brand.contains('heix') || brand.contains('mif1') || brand.contains('heif'));
}

/// Synchronous core (unit-testable). Throws [AvatarException].
ProcessedAvatar processAvatarSync(Uint8List input) {
  if (input.length > avatarMaxInputBytes) throw const AvatarException(AvatarErrorKind.tooLarge);
  if (_looksLikeHeic(input)) throw const AvatarException(AvatarErrorKind.unsupported);
  img.Image? decoded;
  try {
    decoded = img.decodeImage(input);
  } catch (_) {
    decoded = null;
  }
  if (decoded == null) throw const AvatarException(AvatarErrorKind.notImage);
  var image = img.bakeOrientation(decoded);
  final shortSide = image.width < image.height ? image.width : image.height;
  if (shortSide < avatarMinSide) throw const AvatarException(AvatarErrorKind.tooSmall);

  // centre square
  final side = shortSide;
  image = img.copyCrop(image, x: (image.width - side) ~/ 2, y: (image.height - side) ~/ 2, width: side, height: side);
  if (side > avatarMaxSide) {
    image = img.copyResize(image, width: avatarMaxSide, height: avatarMaxSide, interpolation: img.Interpolation.average);
  }

  // Flatten transparency onto white and drop every metadata block by building a fresh image.
  final flat = img.Image(width: image.width, height: image.height, numChannels: 3);
  img.fill(flat, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(flat, image);

  var out = Uint8List(0);
  for (final q in const [80, 70, 60, 50, 40]) {
    out = Uint8List.fromList(img.encodeJpg(flat, quality: q));
    if (out.length <= avatarTargetBytes) break;
  }
  if (out.length > avatarHardMaxBytes) throw const AvatarException(AvatarErrorKind.tooLarge);
  return ProcessedAvatar(out, flat.width, flat.height);
}

/// Runs [processAvatarSync] off the UI thread.
Future<ProcessedAvatar> processAvatar(Uint8List input) => compute(processAvatarSync, input);
