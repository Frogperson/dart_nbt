# dart_nbt

A Dart library for reading and writing Minecraft NBT (Named Binary Tag) data, designed for cross-platform compatibility (including web).

## Usage

### Reading NBT Data

```dart
void main() async {
  try {
    // Read bytes from a file (e.g., level.dat)
    final bytes = await File('path/to/your/level.dat').readAsBytes();

    // Parse the NBT data (auto-detects compression)
    final NbtCompound rootTag = Nbt().read(bytes);

    // Access data (NbtCompound provides a lookup by name)
    final dataTag = rootTag['Data'] as NbtCompound?;
    final levelName = dataTag?['LevelName'] as NbtString?;

    print('Level Name: ${levelName?.value}');

    // Access other tags similarly...
    final player = dataTag?['Player'] as NbtCompound?;
    final motion = player?['Motion'] as NbtList<NbtDouble>?;
    if (motion != null) {
      print('Player Motion: ${motion.value.map((tag) => tag.value).toList()}');
    }

  } catch (e) {
    print('Error reading NBT: $e');
  }
}
```
### Writing NBT Data

```dart
void main() async {
  // Create an NBT structure
  final myData = NbtCompound(name: '', value: [
    NbtCompound(name: 'Data', value: [
      NbtString(name: 'LevelName', value: 'My Awesome World'),
      NbtCompound(name: 'Player', value: [
        NbtShort(name: 'Health', value: 20),
        NbtList<NbtCompound>(name: 'Inventory', value: [
          NbtCompound(name: null, value: [
            NbtString(name: 'id', value: 'minecraft:diamond_sword'),
            NbtByte(name: 'Count', value: 1),
          ]),
          NbtCompound(name: null, value: [
            NbtString(name: 'id', value: 'minecraft:apple'),
            NbtByte(name: 'Count', value: 64),
          ]),
        ]),
        NbtInt(name: 'SpawnX', value: 100),
        NbtInt(name: 'SpawnY', value: 64),
        NbtInt(name: 'SpawnZ', value: -50),
        NbtFloat(name: 'Experience', value: 123.45),
        NbtLong(name: 'UUID', value: BigInt.parse('1234567890123456789')),
      ]),
      NbtLong(name: 'RandomSeed', value: BigInt.parse('-987654321098765432')),
      NbtList<NbtString>(name: 'EnabledFeatures', value: [
        NbtString(name: null, value: 'feature_one'),
        NbtString(name: null, value: 'feature_two'),
      ]),
    ]),
  ]);

  try {
    // Write the data to bytes (compressed by default with GZip)
    final bytes = Nbt().write(myData);

    // Save to a file
    await File('level.dat').writeAsBytes(bytes);
    print('Successfully wrote NBT data.');

  } catch (e) {
    print('Error writing NBT: $e');
  }
}
```
### Tag Types
The library provides classes for all standard NBT tags:
- NbtEndTag
- NbtByteTag (int: -128 to 127)
- NbtShortTag (int: -32768 to 32767)
- NbtIntTag (int: -2^31 to 2^31-1)
- NbtLongTag (BigInt)
- NbtFloatTag (double)
- NbtDoubleTag (double)
- NbtByteArrayTag (Int8List)
- NbtStringTag (String)
- NbtListTag<E extends NbtTag> (List)
- NbtCompoundTag (Map<String, NbtTag>)
- NbtIntArrayTag (Int32List