import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Represents the different compression formats that NBT data can use.
enum NbtCompression {
  gzip,
  zlib,
  none,
}

/// A utility class for detecting, decompressing, and compressing NBT data.
class NbtDecoder {
  /// Detects the compression format of the given [bytes].
  ///
  /// It checks for common magic numbers associated with GZip and Zlib.
  /// If no known compression format is detected, it defaults to [NbtCompression.none].
  ///
  /// - Parameter [bytes]: The byte data to inspect.
  /// - Returns: The detected [NbtCompression] type.
  /// - Throws: [FormatException] if [bytes] is empty.
  NbtCompression detectCompression(bytes) {
    if (bytes.isEmpty) {
      throw FormatException('Cannot read NBT from empty byte data.');
    }

    if (bytes.length >= 2 && bytes[0] == 0x1F && bytes[1] == 0x8B) {
      return NbtCompression.gzip;
    } else if (bytes.length >= 2 &&
        bytes[0] == 0x78 &&
        (bytes[1] == 0x01 ||
            bytes[1] == 0x5E ||
            bytes[1] == 0x9C ||
            bytes[1] == 0xDA)) {
      return NbtCompression.zlib;
    } else {
      return NbtCompression.none;
    }
  }

  /// Decompresses the given [bytes] based on its detected compression format.
  ///
  /// This method first calls [detectCompression] to determine the format
  /// and then uses the appropriate decoder from the `archive` package.
  /// If the data is not compressed ([NbtCompression.none]), it returns the
  /// original [bytes].
  ///
  /// - Parameter [bytes]: The byte data to decompress.
  /// - Returns: A [Uint8List] containing the decompressed data.
  /// - Throws: [FormatException] if [bytes] is empty or if decompression fails
  ///   (e.g., data is malformed for the detected compression type).
  Uint8List decompress(bytes) {
    if (bytes.isEmpty) {
      throw FormatException('Cannot read NBT from empty byte data.');
    }

    switch (detectCompression(bytes)) {
      case NbtCompression.gzip:
        try {
          final decodedBytes = GZipDecoder().decodeBytes(bytes, verify: true);
          return Uint8List.fromList(decodedBytes);
        } catch (e) {
          throw FormatException(
              'Data appears to be Gzip compressed, but decompression failed: $e');
        }
      case NbtCompression.zlib:
        try {
          final decodedBytes = ZLibDecoder().decodeBytes(bytes, verify: true);
          return Uint8List.fromList(decodedBytes);
        } catch (e) {
          throw FormatException(
              'Data appears to be Zlib compressed, but decompression failed: $e');
        }
      case NbtCompression.none:
        return bytes;
    }
  }

  /// Compresses the given [bytes] using the specified [compression] method.
  ///
  /// If [compression] is `null` or not provided, it defaults to [NbtCompression.gzip].
  /// If [NbtCompression.none] is specified, the original [bytes] are returned.
  ///
  /// - Parameter [bytes]: The byte data to compress.
  /// - Parameter [compression]: The [NbtCompression] method to use.
  ///   Defaults to [NbtCompression.gzip].
  /// - Returns: A [Uint8List] containing the compressed data.
  Uint8List compress(Uint8List bytes, {NbtCompression? compression}) {
    switch (compression = NbtCompression.gzip) {
      case NbtCompression.gzip:
        final List<int> compressed = GZipEncoder().encodeBytes(bytes);
        return Uint8List.fromList(compressed);
      case NbtCompression.zlib:
        final List<int> compressed = ZLibEncoder().encode(bytes);
        return Uint8List.fromList(compressed);
      case NbtCompression.none:
        return bytes;
    }
  }
}
