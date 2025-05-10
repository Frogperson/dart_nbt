import 'dart:typed_data';

import 'package:dart_nbt/src/nbt_compression.dart';
import 'package:dart_nbt/src/nbt_reader.dart';
import 'package:dart_nbt/src/nbt_tags.dart';
import 'package:dart_nbt/src/nbt_writer.dart';

export 'package:dart_nbt/src/nbt_compression.dart'
    show NbtCompression, NbtDecoder;
export 'package:dart_nbt/src/nbt_tags.dart'
    show
        NbtTagType,
        NbtTag,
        NbtEnd,
        NbtByte,
        NbtShort,
        NbtInt,
        NbtLong,
        NbtFloat,
        NbtDouble,
        NbtByteArray,
        NbtString,
        NbtList,
        NbtCompound,
        NbtIntArray,
        NbtLongArray;

/// A utility class for reading and writing NBT (Named Binary Tag) data.
///
/// This class provides methods to parse NBT data from a byte array
/// and to serialize an NBT compound tag structure into a byte array.
/// It handles automatic decompression and compression of NBT data.
class Nbt {
  /// Reads NBT data from a [Uint8List] and returns the root [NbtCompound] tag.
  ///
  /// The input [bytes] are first decompressed (if necessary) and then parsed.
  ///
  /// Throws a [FormatException] if the [bytes] list is empty or if the
  /// NBT data is malformed.
  ///
  /// - Parameter [bytes]: The byte array containing the NBT data.
  /// - Returns: The root [NbtCompound] tag parsed from the NBT data.
  NbtCompound read(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw FormatException('Cannot read NBT from empty byte data.');
    }

    Uint8List decompressedBytes = NbtDecoder().decompress(bytes);
    final reader = NbtReader(decompressedBytes);
    return reader.readRootTag();
  }

  /// Writes an [NbtCompound] root tag to a [Uint8List].
  ///
  /// The [rootTag] is serialized into an uncompressed byte array,
  /// which is then compressed according to the specified [compression]
  /// method (or defaults to GZip if `null`).
  ///
  /// - Parameter [rootTag]: The root [NbtCompound] tag to serialize.
  /// - Parameter [compression]: The [NbtCompression] method to use.
  ///   Defaults to [NbtCompression.gzip] if `null`.
  /// - Returns: A [Uint8List] containing the serialized and compressed NBT data.
  Uint8List write(NbtCompound rootTag, {NbtCompression? compression}) {
    final writer = NbtWriter();
    final uncompressedBytes = writer.writeRootTag(rootTag);
    return NbtDecoder().compress(uncompressedBytes, compression: compression);
  }
}
