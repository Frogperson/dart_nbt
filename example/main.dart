import 'dart:typed_data';
import 'package:dart_nbt/dart_nbt.dart';

void main() {
  final Nbt nbt = Nbt();

  // Create a root NbtCompound and add a few example tags.
  final root = NbtCompound(name: 'SimpleRoot', value: [
    NbtString(name: 'ExampleString', value: 'Hello NBT'),
    NbtInt(name: 'ExampleInt', value: 12),
  ]);

  // Serialize the NBT structure to a Gzip-compressed Uint8List .
  final Uint8List nbtBytes = nbt.write(root, compression: NbtCompression.gzip);

  // Deserialize the Uint8List back into an NbtCompound.
  // The readNbt function automatically handles decompression.
  final NbtCompound nbtCompound = nbt.read(nbtBytes);

  // Print all values in the NbtCompound.
  for (final NbtTag tag in nbtCompound.value) {
    print('${tag.name}: ${tag.value}');
  }
}
