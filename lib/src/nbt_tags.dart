import 'dart:convert';
import 'dart:typed_data';

import 'package:buffer/buffer.dart';

/// Constants for BigInt to 32-bit int conversion.
const int _int32Bits = 32;
final BigInt _bigIntFFFFFFFF =
    BigInt.from(0xFFFFFFFF); // Mask for lower 32 bits.

/// NBT (Named Binary Tag) tag types.
enum NbtTagType {
  endTag(0, 'TAG_End'),
  byteTag(1, 'TAG_Byte'),
  shortTag(2, 'TAG_Short'),
  intTag(3, 'TAG_Int'),
  longTag(4, 'TAG_Long'),
  floatTag(5, 'TAG_Float'),
  doubleTag(6, 'TAG_Double'),
  byteArrayTag(7, 'TAG_Byte_Array'),
  stringTag(8, 'TAG_String'),
  listTag(9, 'TAG_List'),
  compoundTag(10, 'TAG_Compound'),
  intArrayTag(11, 'TAG_Int_Array'),
  longArrayTag(12, 'TAG_Long_Array');

  /// Numerical ID for serialization.
  final int id;

  /// Standard NBT name (e.g., 'TAG_Byte').
  final String nbtName;

  const NbtTagType(this.id, this.nbtName);

  /// Gets the [NbtTagType] from its numerical ID.
  /// Throws [ArgumentError] if the ID is invalid.
  static NbtTagType fromId(int id) {
    for (final type in values) {
      if (type.id == id) {
        return type;
      }
    }
    throw ArgumentError('Invalid NBT tag type ID: $id');
  }
}

/// Abstract base for NBT tags.
/// Each tag has an optional [name], a [value] of type [T], and an [NbtTagType].
abstract class NbtTag<T> {
  /// Optional name. Null for list elements.
  String? name;

  /// The tag's data value.
  T value;

  /// The [NbtTagType] of this tag.
  NbtTagType get type;

  NbtTag({this.name, required this.value});

  /// Writes the tag's payload (value only) to the writer.
  void writePayload(ByteDataWriter writer);

  @override
  String toString() {
    final nameStr = name != null ? "'${name!}'" : '(in list)';
    String valueStr;
    if (value is List<NbtTag>) {
      final listValue = value as List<NbtTag>;
      valueStr = listValue.length > 3
          ? '[${listValue.length} ${type.name} elements]'
          : listValue.toString();
    } else if (value is BigInt) {
      valueStr = (value as BigInt).toString();
    } else {
      valueStr = value.toString();
    }
    return '${type.nbtName}$nameStr: $valueStr';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NbtTag &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          value == other.value;

  @override
  int get hashCode => name.hashCode ^ value.hashCode ^ runtimeType.hashCode;
}

// --- Concrete Tag Implementations ---

/// TAG_End: Marks end of [NbtCompound] or empty [NbtList] type. No name/payload.
class NbtEnd extends NbtTag<void> {
  NbtEnd() : super(name: null, value: null);

  @override
  NbtTagType get type => NbtTagType.endTag;

  /// No payload for TAG_End.
  @override
  void writePayload(ByteDataWriter writer) {}

  @override
  String toString() => type.nbtName;

  @override
  bool operator ==(Object other) => other is NbtEnd;

  @override
  int get hashCode => type.hashCode;
}

/// TAG_Byte: A signed 8-bit integer (-128 to 127).
class NbtByte extends NbtTag<int> {
  NbtByte({super.name, required super.value}) {
    if (value < -128 || value > 127) {
      throw ArgumentError(
          'Value for NbtByte must be between -128 and 127, got: $value');
    }
  }

  @override
  NbtTagType get type => NbtTagType.byteTag;

  @override
  void writePayload(ByteDataWriter writer) {
    writer.writeInt8(value);
  }
}

/// TAG_Short: A signed 16-bit integer (-32768 to 32767).
class NbtShort extends NbtTag<int> {
  NbtShort({super.name, required super.value}) {
    if (value < -32768 || value > 32767) {
      throw ArgumentError(
          'Value for NbtShort must be between -32768 and 32767, got: $value');
    }
  }

  @override
  NbtTagType get type => NbtTagType.shortTag;

  @override
  void writePayload(ByteDataWriter writer) {
    writer.writeInt16(value);
  }
}

/// TAG_Int: A signed 32-bit integer.
class NbtInt extends NbtTag<int> {
  NbtInt({super.name, required super.value}) {
    if (value < -2147483648 || value > 2147483647) {
      throw ArgumentError(
          'Value for NbtInt must be between -2147483648 and 2147483647, got: $value');
    }
  }

  @override
  NbtTagType get type => NbtTagType.intTag;

  @override
  void writePayload(ByteDataWriter writer) {
    writer.writeInt32(value);
  }
}

/// TAG_Long: A signed 64-bit integer, using [BigInt].
class NbtLong extends NbtTag<BigInt> {
  NbtLong({super.name, required super.value});

  @override
  NbtTagType get type => NbtTagType.longTag;

  @override
  void writePayload(ByteDataWriter writer) {
    final BigInt high = value >> _int32Bits;
    final BigInt low = value & _bigIntFFFFFFFF;
    writer.writeInt32(high.toSigned(32).toInt());
    writer.writeInt32(low.toSigned(32).toInt());
  }
}

/// TAG_Float: A 32-bit IEEE 754 floating-point number.
class NbtFloat extends NbtTag<double> {
  NbtFloat({super.name, required super.value});

  @override
  NbtTagType get type => NbtTagType.floatTag;

  @override
  void writePayload(ByteDataWriter writer) {
    writer.writeFloat32(value);
  }
}

/// TAG_Double: A 64-bit IEEE 754 floating-point number.
class NbtDouble extends NbtTag<double> {
  NbtDouble({super.name, required super.value});

  @override
  NbtTagType get type => NbtTagType.doubleTag;

  @override
  void writePayload(ByteDataWriter writer) {
    writer.writeFloat64(value);
  }
}

/// TAG_Byte_Array: Length-prefixed array of signed 8-bit integers ([Int8List]).
class NbtByteArray extends NbtTag<Int8List> {
  NbtByteArray({super.name, required super.value});

  @override
  NbtTagType get type => NbtTagType.byteArrayTag;

  @override
  void writePayload(ByteDataWriter writer) {
    writer.writeInt32(value.length);
    for (final byteValue in value) {
      writer.writeInt8(byteValue);
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! NbtByteArray ||
        name != other.name ||
        value.length != other.value.length) {
      return false;
    }
    for (int i = 0; i < value.length; i++) {
      if (value[i] != other.value[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => name.hashCode ^ Object.hashAll(value);
}

/// TAG_String: UTF-8 string, prefixed by its length in bytes (unsigned 16-bit).
class NbtString extends NbtTag<String> {
  NbtString({super.name, required super.value});

  @override
  NbtTagType get type => NbtTagType.stringTag;

  @override
  void writePayload(ByteDataWriter writer) {
    final bytes = utf8.encode(value);
    writer.writeUint16(bytes.length);
    for (final byteValue in bytes) {
      writer.writeUint8(byteValue);
    }
  }
}

/// TAG_List: A list of NBT tags of a single [elementType].
/// Tags in list are unnamed. Empty list has [elementType] TAG_End.
class NbtList<E extends NbtTag> extends NbtTag<List<E>> {
  late final NbtTagType elementType;

  /// Creates an [NbtList].
  /// All [value] elements must be of the same type. Their names are set to null.
  /// Throws [ArgumentError] for inconsistent element types.
  NbtList({super.name, required super.value}) {
    elementType = value.isEmpty ? NbtTagType.endTag : value.first.type;
    for (final tag in value) {
      if (tag.type != elementType) {
        throw ArgumentError(
            'All elements in NbtList must have the same type. Expected $elementType but found ${tag.type} for tag ${tag.name}.');
      }
      tag.name = null;
    }
  }

  @override
  NbtTagType get type => NbtTagType.listTag;

  @override
  void writePayload(ByteDataWriter writer) {
    writer.writeInt8(elementType.id);
    writer.writeInt32(value.length);
    for (final tag in value) {
      tag.writePayload(writer);
    }
  }

  /// Compares name, elementType, and ordered list content.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other.runtimeType != runtimeType) return false;
    if (other is NbtList) {
      if (name != other.name ||
          elementType != other.elementType ||
          value.length != other.value.length) {
        return false;
      }
      for (int i = 0; i < value.length; i++) {
        if (value[i] != other.value[i]) return false;
      }
      return true;
    }
    return false;
  }

  @override
  int get hashCode =>
      name.hashCode ^ elementType.hashCode ^ Object.hashAll(value);
}

/// TAG_Compound: A map-like collection of named NBT tags.
/// Order is preserved for serialization but ignored for equality.
/// Terminated by TAG_End during serialization.
class NbtCompound extends NbtTag<List<NbtTag>> {
  // Map for quick name-based lookup. `super.value` (List) maintains insertion order.
  final Map<String, NbtTag> _tags = {};

  NbtCompound({super.name, required List<NbtTag> value})
      : super(value: List<NbtTag>.from(value)) {
    for (final tag in super.value) {
      if (tag.name == null) {
        throw ArgumentError(
            'Tags directly within an NbtCompound must have names. Found a tag of type ${tag.type} with a null name.');
      }
      if (_tags.containsKey(tag.name!)) {
        throw ArgumentError(
            'Duplicate tag name "${tag.name!}" in NbtCompound.');
      }
      _tags[tag.name!] = tag;
    }
    super.value = List.unmodifiable(super.value);
  }

  /// Gets tag by [key] (name). Returns `null` if not found.
  NbtTag? operator [](String key) {
    return _tags[key];
  }

  /// Adds or replaces tag [key] with [tag].
  /// Preserves order if [key] exists, otherwise adds to end.
  void operator []=(String key, NbtTag tag) {
    tag.name = key;

    final currentOrderedList = List<NbtTag>.from(super.value);
    final existingIndex = currentOrderedList.indexWhere((t) => t.name == key);

    if (_tags.containsKey(key)) {
      if (existingIndex != -1) {
        currentOrderedList[existingIndex] = tag;
      } else {
        // This case (in _tags but not in currentOrderedList) implies inconsistency.
        // Should not happen if both are managed correctly.
        // For safety, remove any old one by name and add new one.
        currentOrderedList.removeWhere((t) => t.name == key);
        currentOrderedList.add(tag);
      }
    } else {
      if (existingIndex != -1) {
        // Also implies inconsistency if it's in list but not map
        currentOrderedList[existingIndex] = tag;
      } else {
        currentOrderedList.add(tag); // Add to end of ordered list
      }
    }

    _tags[key] = tag;
    super.value = List.unmodifiable(currentOrderedList);
  }

  /// Removes tag by [key]. Returns removed tag or `null`.
  NbtTag? remove(String key) {
    final removedTag = _tags.remove(key);
    if (removedTag != null) {
      final currentOrderedList = List<NbtTag>.from(super.value);
      currentOrderedList.removeWhere((tag) => tag.name == key);
      super.value = List.unmodifiable(currentOrderedList);
    }
    return removedTag;
  }

  /// Iterable of tag names (keys). Order not guaranteed for serialization.
  /// For serialization order, iterate `this.value.map((t) => t.name!)`.
  Iterable<String> get keys => _tags.keys;

  /// Iterable of tag values from the internal map. Order not guaranteed.
  /// For serialization order, use `this.value`.
  Iterable<NbtTag> get mapValues => _tags.values;

  /// Checks if a tag with [key] (name) exists.
  bool containsKey(String key) => _tags.containsKey(key);

  @override
  NbtTagType get type => NbtTagType.compoundTag;

  @override
  void writePayload(ByteDataWriter writer) {
    for (final tag in super.value) {
      writer.writeInt8(tag.type.id);
      final nameBytes = utf8.encode(tag.name!);
      writer.writeUint16(nameBytes.length);
      for (final byteValue in nameBytes) {
        writer.writeUint8(byteValue);
      }
      tag.writePayload(writer);
    }
    writer.writeInt8(NbtTagType.endTag.id);
  }

  /// Compares name and tag content (order-insensitive).
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! NbtCompound ||
        name != other.name ||
        _tags.length != other._tags.length) {
      return false;
    }
    // Order of tags in a compound does not matter for equality, so compare maps.
    for (final key in _tags.keys) {
      if (!other._tags.containsKey(key) || _tags[key] != other._tags[key]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode {
    int calculatedHash = name.hashCode;
    // Hash code should be order-independent for map entries.
    // Summing or XORing individual entry hashes is common.
    // Sorting keys before hashing ensures consistency if iterating map entries.
    final sortedKeys = _tags.keys.toList()..sort();
    for (final key in sortedKeys) {
      calculatedHash ^= key.hashCode ^ _tags[key].hashCode;
    }
    return calculatedHash ^ _tags.length.hashCode;
  }
}

/// TAG_Int_Array: Length-prefixed array of signed 32-bit integers ([Int32List]).
class NbtIntArray extends NbtTag<Int32List> {
  NbtIntArray({super.name, required super.value});

  @override
  NbtTagType get type => NbtTagType.intArrayTag;

  @override
  void writePayload(ByteDataWriter writer) {
    writer.writeInt32(value.length);
    for (final val in value) {
      writer.writeInt32(val);
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! NbtIntArray ||
        name != other.name ||
        value.length != other.value.length) {
      return false;
    }
    for (int i = 0; i < value.length; i++) {
      if (value[i] != other.value[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => name.hashCode ^ Object.hashAll(value);
}

/// TAG_Long_Array: Length-prefixed array of signed 64-bit integers ([BigInt] list).
class NbtLongArray extends NbtTag<List<BigInt>> {
  NbtLongArray({super.name, required super.value});

  @override
  NbtTagType get type => NbtTagType.longArrayTag;

  @override
  void writePayload(ByteDataWriter writer) {
    writer.writeInt32(value.length);
    for (final val in value) {
      final BigInt high = val >> _int32Bits;
      final BigInt low = val & _bigIntFFFFFFFF;
      writer.writeInt32(high.toSigned(32).toInt());
      writer.writeInt32(low.toSigned(32).toInt());
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! NbtLongArray ||
        name != other.name ||
        value.length != other.value.length) {
      return false;
    }
    for (int i = 0; i < value.length; i++) {
      if (value[i] != other.value[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => name.hashCode ^ Object.hashAll(value);
}
