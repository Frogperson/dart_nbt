import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_nbt/src/nbt_tags.dart';

/// Constants for BigInt to 32-bit int conversion.
const int _int32Bits = 32;
final BigInt _bigIntFFFFFFFF =
    BigInt.from(0xFFFFFFFF); // Mask for lower 32 bits.

/// A class responsible for reading NBT (Named Binary Tag) data from a byte stream.
///
/// It parses the binary data according to the NBT specification and constructs
/// a tree of [NbtTag] objects.
class NbtReader {
  final ByteData _byteData;
  int _offset = 0;

  NbtReader(Uint8List decompressedBytes)
      : _byteData = _createByteDataView(decompressedBytes);

  static ByteData _createByteDataView(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw FormatException('Cannot create NbtReader from empty byte list.');
    }
    return ByteData.view(
        bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes);
  }

  /// Reads the root NBT tag from the byte stream.
  ///
  /// The NBT specification requires the root tag to be an [NbtCompound].
  /// Throws a [FormatException] if the root tag is not an [NbtCompound]
  /// or if the data is malformed.
  NbtCompound readRootTag() {
    _offset = 0;
    final NbtTag rootTag = _readTag();

    if (rootTag is! NbtCompound) {
      throw FormatException(
          'Root NBT tag must be TAG_Compound, but found ${rootTag.type.nbtName}');
    }
    return rootTag;
  }

  /// Reads a single NBT tag from the current offset in the byte stream.
  ///
  /// This method first reads the tag type ID, then the tag name (if not TAG_End),
  /// and finally the tag's payload.
  ///
  /// Throws a [FormatException] if the data is malformed, such as an invalid
  /// tag type ID, negative name length, or if a root tag is TAG_End.
  NbtTag _readTag() {
    final typeId = _readByte();
    final type = NbtTagType.fromId(typeId);

    if (type == NbtTagType.endTag) {
      return NbtEnd();
    }

    final nameLength = _readShort();
    if (nameLength < 0) {
      throw FormatException(
          'Invalid negative tag name length: $nameLength at offset ${_offset - 2}');
    }
    final nameBytes = _readBytes(nameLength);
    final String name = nameLength == 0 ? "" : utf8.decode(nameBytes);

    return _readPayload(type, name);
  }

  /// Reads the payload of an NBT tag based on its [type] and [name].
  ///
  /// Throws a [FormatException] if the payload data is malformed (e.g.,
  /// negative array/list sizes, invalid list element types).
  /// Throws a [StateError] if called with [NbtTagType.endTag], as TAG_End
  /// has no payload and should be handled by [_readTag].
  NbtTag _readPayload(NbtTagType type, String name) {
    switch (type) {
      case NbtTagType.byteTag:
        return NbtByte(name: name, value: _readByte());
      case NbtTagType.shortTag:
        return NbtShort(name: name, value: _readShort());
      case NbtTagType.intTag:
        return NbtInt(name: name, value: _readInt());
      case NbtTagType.longTag:
        return NbtLong(name: name, value: _readLong());
      case NbtTagType.floatTag:
        return NbtFloat(name: name, value: _readFloat());
      case NbtTagType.doubleTag:
        return NbtDouble(name: name, value: _readDouble());
      case NbtTagType.stringTag:
        final length = _readShort();
        if (length < 0) {
          throw FormatException(
              'Invalid negative TAG_String length: $length at offset ${_offset - 2}');
        }
        final bytes = _readBytes(length);
        return NbtString(name: name, value: utf8.decode(bytes));
      case NbtTagType.byteArrayTag:
        final size = _readInt();
        if (size < 0) {
          throw FormatException(
              'Invalid negative TAG_Byte_Array size: $size at offset ${_offset - 4}');
        }
        return NbtByteArray(
            name: name, value: Int8List.fromList(_readBytes(size)));
      case NbtTagType.intArrayTag:
        final size = _readInt();
        if (size < 0) {
          throw FormatException(
              'Invalid negative TAG_Int_Array size: $size at offset ${_offset - 4}');
        }
        final ints = Int32List(size);
        for (int i = 0; i < size; i++) {
          ints[i] = _readInt();
        }
        return NbtIntArray(name: name, value: ints);
      case NbtTagType.longArrayTag:
        final size = _readInt();
        if (size < 0) {
          throw FormatException(
              'Invalid negative TAG_Long_Array size: $size at offset ${_offset - 4}');
        }
        final longs = List<BigInt>.filled(size, BigInt.zero);
        for (int i = 0; i < size; i++) {
          longs[i] = _readLong();
        }
        return NbtLongArray(name: name, value: longs);
      case NbtTagType.listTag:
        final elementTypeId = _readByte();
        final elementType = NbtTagType.fromId(elementTypeId);
        final listSize = _readInt();
        if (listSize < 0) {
          throw FormatException(
              'Invalid negative TAG_List size: $listSize at offset ${_offset - 4}');
        }
        if (listSize > 0 && elementType == NbtTagType.endTag) {
          throw FormatException(
              'TAG_List with size $listSize > 0 cannot have TAG_End as element type at offset ${_offset - 5}');
        }

        final List<NbtTag> rawListElements = [];
        for (int i = 0; i < listSize; i++) {
          // List elements are unnamed according to the NBT specification.
          rawListElements.add(_readPayload(elementType, ''));
        }

        switch (elementType) {
          case NbtTagType.endTag:
            // An empty list can be declared with TAG_End as its type.
            return NbtList<NbtEnd>(name: name, value: <NbtEnd>[]);
          case NbtTagType.byteTag:
            return NbtList<NbtByte>(
                name: name,
                value: List<NbtByte>.from(
                    rawListElements.map((t) => t as NbtByte)));
          case NbtTagType.shortTag:
            return NbtList<NbtShort>(
                name: name,
                value: List<NbtShort>.from(
                    rawListElements.map((t) => t as NbtShort)));
          case NbtTagType.intTag:
            return NbtList<NbtInt>(
                name: name,
                value:
                    List<NbtInt>.from(rawListElements.map((t) => t as NbtInt)));
          case NbtTagType.longTag:
            return NbtList<NbtLong>(
                name: name,
                value: List<NbtLong>.from(
                    rawListElements.map((t) => t as NbtLong)));
          case NbtTagType.floatTag:
            return NbtList<NbtFloat>(
                name: name,
                value: List<NbtFloat>.from(
                    rawListElements.map((t) => t as NbtFloat)));
          case NbtTagType.doubleTag:
            return NbtList<NbtDouble>(
                name: name,
                value: List<NbtDouble>.from(
                    rawListElements.map((t) => t as NbtDouble)));
          case NbtTagType.byteArrayTag:
            return NbtList<NbtByteArray>(
                name: name,
                value: List<NbtByteArray>.from(
                    rawListElements.map((t) => t as NbtByteArray)));
          case NbtTagType.stringTag:
            return NbtList<NbtString>(
                name: name,
                value: List<NbtString>.from(
                    rawListElements.map((t) => t as NbtString)));
          case NbtTagType.listTag:
            return NbtList<NbtList>(
                name: name,
                value: List<NbtList>.from(
                    rawListElements.map((t) => t as NbtList)));
          case NbtTagType.compoundTag:
            return NbtList<NbtCompound>(
                name: name,
                value: List<NbtCompound>.from(
                    rawListElements.map((t) => t as NbtCompound)));
          case NbtTagType.intArrayTag:
            return NbtList<NbtIntArray>(
                name: name,
                value: List<NbtIntArray>.from(
                    rawListElements.map((t) => t as NbtIntArray)));
          case NbtTagType.longArrayTag:
            return NbtList<NbtLongArray>(
                name: name,
                value: List<NbtLongArray>.from(
                    rawListElements.map((t) => t as NbtLongArray)));
        }

      case NbtTagType.compoundTag:
        final tags = <NbtTag>[];
        while (true) {
          final tag = _readTag();
          if (tag is NbtEnd) {
            break; // TAG_End signifies the end of the compound tag.
          }
          // Tags within a compound tag must have names.
          if (tag.name == null) {
            throw FormatException(
                'Tag of type ${tag.type.nbtName} inside NbtCompound "$name" is missing a name at offset $_offset.');
          }
          tags.add(tag);
        }
        return NbtCompound(name: name, value: tags);
      case NbtTagType.endTag:
        // This case should ideally not be reached if _readTag handles TAG_End correctly.
        throw StateError('Internal error: _readPayload called with TAG_End.');
    }
  }

  /// Ensures that there are at least [numBytes] available to read from the
  /// current offset.
  ///
  /// Throws a [FormatException] if reading [numBytes] would exceed the
  /// buffer's bounds.
  void _ensureReadableBytes(int numBytes) {
    if (_offset + numBytes > _byteData.lengthInBytes) {
      throw FormatException(
          'Unexpected end of NBT data: tried to read $numBytes bytes at offset $_offset with buffer size ${_byteData.lengthInBytes}.');
    }
  }

  /// Reads a single signed byte (8 bits) from the current offset and advances
  /// the offset by 1.
  int _readByte() {
    _ensureReadableBytes(1);
    final value = _byteData.getInt8(_offset);
    _offset += 1;
    return value;
  }

  /// Reads a signed short (16 bits, big-endian) from the current offset and
  /// advances the offset by 2.
  int _readShort() {
    _ensureReadableBytes(2);
    final value = _byteData.getInt16(_offset, Endian.big);
    _offset += 2;
    return value;
  }

  /// Reads a signed integer (32 bits, big-endian) from the current offset and
  /// advances the offset by 4.
  int _readInt() {
    _ensureReadableBytes(4);
    final value = _byteData.getInt32(_offset, Endian.big);
    _offset += 4;
    return value;
  }

  /// Reads a signed long (64 bits, big-endian) as a [BigInt] from the current
  /// offset and advances the offset by 8.
  BigInt _readLong() {
    _ensureReadableBytes(8);
    // Read as two 32-bit integers and combine them.
    final high = _byteData.getInt32(_offset, Endian.big);
    final low = _byteData.getInt32(_offset + 4, Endian.big);
    _offset += 8;
    return (BigInt.from(high) << _int32Bits) |
        (BigInt.from(low) & _bigIntFFFFFFFF);
  }

  /// Reads a single-precision float (32 bits, big-endian) from the current
  /// offset and advances the offset by 4.
  double _readFloat() {
    _ensureReadableBytes(4);
    final value = _byteData.getFloat32(_offset, Endian.big);
    _offset += 4;
    return value;
  }

  /// Reads a double-precision float (64 bits, big-endian) from the current
  /// offset and advances the offset by 8.
  double _readDouble() {
    _ensureReadableBytes(8);
    final value = _byteData.getFloat64(_offset, Endian.big);
    _offset += 8;
    return value;
  }

  /// Reads [length] bytes from the current offset into a [Uint8List] and
  /// advances the offset by [length].
  ///
  /// Throws a [FormatException] if [length] is negative.
  /// Returns an empty [Uint8List] if [length] is 0.
  Uint8List _readBytes(int length) {
    if (length < 0) {
      throw FormatException("Cannot read negative number of bytes: $length");
    }
    if (length == 0) return Uint8List(0);
    _ensureReadableBytes(length);
    final bytes = Uint8List.fromList(_byteData.buffer
        .asUint8List(_byteData.offsetInBytes + _offset, length));
    _offset += length;
    return bytes;
  }
}
