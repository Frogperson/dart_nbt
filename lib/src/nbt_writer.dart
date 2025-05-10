import 'dart:convert';
import 'dart:typed_data';

import 'package:buffer/buffer.dart';
import 'package:dart_nbt/src/nbt_tags.dart';


/// A class responsible for writing NBT (Named Binary Tag) data to a byte stream.
///
/// It handles the serialization of NBT tags into the binary format
/// specified by the NBT specification, using big-endian byte order.
class NbtWriter {
  final ByteDataWriter _writer;

  NbtWriter() : _writer = ByteDataWriter(endian: Endian.big);

  /// Writes the root [NbtCompound] tag to the underlying byte stream and returns
  /// the resulting byte array.
  ///
  /// This method serializes the entire NBT structure starting from the
  /// provided [rootTag]. It follows the NBT specification:
  /// 1. Writes the type ID of the root tag (which must be an NbtCompound).
  /// 2. Writes the name of the root tag (UTF-8 encoded string prefixed by its length as a Uint16).
  ///    If the root tag has no name, an empty string is written.
  /// 3. Delegates to the [rootTag]'s `writePayload` method to serialize its contents.
  ///
  /// The [rootTag] must be an [NbtCompound] tag, as it's the only valid root tag type.
  ///
  /// Returns a [Uint8List] containing the complete NBT data.
  Uint8List writeRootTag(NbtCompound rootTag) {
    _writer.writeInt8(rootTag.type.id);

    final String rootName = rootTag.name ?? "";
    final nameBytes = utf8.encode(rootName);
    _writer.writeUint16(nameBytes.length);
    for (final byteValue in nameBytes) {
      _writer.writeUint8(byteValue);
    }

    rootTag.writePayload(_writer);

    return _writer.toBytes();
  }
}
