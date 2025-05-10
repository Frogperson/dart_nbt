import 'dart:io';
import 'dart:typed_data';

import 'package:buffer/buffer.dart';
import 'package:dart_nbt/dart_nbt.dart';
import 'package:test/test.dart';

void main() {
  group('NBT Read/Write and Compression Preservation Tests', () {
    final inputDir = Directory('test/nbt_files/input');
    final outputDir = Directory('test/nbt_files/output');
    final nbtFileUtilDecoder = NbtDecoder();

    setUpAll(() async {
      if (!await inputDir.exists()) {
        await inputDir.create(recursive: true);
        print('Created input directory: ${inputDir.path}\n'
            '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n'
            'IMPORTANT: Please populate this directory with sample NBT files \n'
            '(e.g., .nbt, .dat) for the tests to run meaningfully.\n'
            '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!');
      }
      if (await outputDir.exists()) {
        await outputDir.delete(recursive: true);
      }
      await outputDir.create(recursive: true);
      print('Output directory cleaned and created: ${outputDir.path}');
    });

    test(
        'Process NBT files: Read, Rewrite with original compression, and Compare',
        () async {
      if (!await inputDir.exists() || inputDir.listSync().isEmpty) {
        print(
            'SKIPPING TEST: Input directory (${inputDir.path}) is empty or does not exist.');
        markTestSkipped(
            'Input directory is empty. Populate it with NBT files.');
        return;
      }

      print('Scanning for files in ${inputDir.path}...');
      int filesProcessed = 0;

      await for (final fileEntity in inputDir.list()) {
        if (fileEntity is File) {
          filesProcessed++;
          final inputFile = fileEntity;
          final fileName = inputFile.path.split(Platform.pathSeparator).last;
          final outputFile =
              File('${outputDir.path}${Platform.pathSeparator}$fileName');

          print('--------------------------------------------------');
          print('Processing file: ${inputFile.path}');

          Uint8List originalBytes;
          try {
            originalBytes = await inputFile.readAsBytes();
            if (originalBytes.isEmpty) {
              print('Skipping empty file: ${inputFile.path}');
              continue;
            }
            print('Read ${originalBytes.length} bytes from original file.');
          } catch (e) {
            print('Error reading file ${inputFile.path}: $e');
            fail('Failed to read input file ${inputFile.path}: $e');
          }

          NbtCompression originalCompression;
          try {
            originalCompression =
                nbtFileUtilDecoder.detectCompression(originalBytes);
            print(
                'Detected original compression for $fileName: $originalCompression');
          } catch (e) {
            print(
                'Could not detect compression for $fileName: $e. Assuming NbtCompression.none for reading.');
            originalCompression = NbtCompression.none;
          }

          NbtCompound rootTag;
          try {
            rootTag = Nbt().read(originalBytes);
            print('Successfully parsed NBT data from $fileName.');
          } catch (e) {
            print('Failed to read/parse NBT from ${inputFile.path}: $e');
            fail('Failed to read/parse NBT from ${inputFile.path}: $e');
          }

          Uint8List writtenBytes;
          try {
            print(
                'Attempting to write NBT data with compression: $originalCompression');
            writtenBytes = Nbt().write(rootTag, compression: originalCompression);
            print('Successfully wrote NBT data to byte array for $fileName.');
          } catch (e) {
            print('Failed to write NBT for ${outputFile.path}: $e');
            fail('Failed to write NBT for ${outputFile.path}: $e');
          }

          try {
            await outputFile.writeAsBytes(writtenBytes);
            print('Written NBT data to output file: ${outputFile.path}');
          } catch (e) {
            print('Failed to write output file ${outputFile.path}: $e');
            fail('Failed to write output file ${outputFile.path}: $e');
          }

          print('Comparing file content for $fileName.');
          if (originalCompression == NbtCompression.gzip ||
              originalCompression == NbtCompression.zlib) {
            Uint8List decompressedOriginal;
            Uint8List decompressedWritten;
            try {
              decompressedOriginal =
                  nbtFileUtilDecoder.decompress(originalBytes);
              decompressedWritten = nbtFileUtilDecoder.decompress(writtenBytes);
            } catch (e) {
              fail('Failed to decompress files for comparison $fileName: $e');
            }

            expect(
              decompressedWritten,
              orderedEquals(decompressedOriginal),
              reason:
                  'Decompressed byte content for $fileName should be identical. '
                  'Original (decompressed) size: ${decompressedOriginal.length}, '
                  'New (decompressed) size: ${decompressedWritten.length}',
            );
          } else {
            expect(
              writtenBytes,
              orderedEquals(originalBytes),
              reason:
                  'Byte content for uncompressed $fileName should be identical. '
                  'Original size: ${originalBytes.length}, New size: ${writtenBytes.length}',
            );
          }
          print('File comparison successful for $fileName.');
          print('--------------------------------------------------');
        }
      }
      if (filesProcessed == 0) {
        print('No files found to process in ${inputDir.path}.');
        markTestSkipped(
            'No files were found in the input directory to process.');
      } else {
        print('\nFinished processing $filesProcessed file(s).');
      }
    });
  });

  group('Individual NBT Tag Read/Write Tests', () {
    // Helper function to compare two NbtList instances with detailed checks
    // to handle potential generic type differences after deserialization.
    void _compareNbtLists(
        NbtList originalList, NbtList deserializedList, String tagName,
        {String path = ''}) {
      final currentPath = path.isEmpty
          ? tagName
          : '$path -> $tagName (element type: ${originalList.elementType})';
      expect(deserializedList.name, originalList.name,
          reason: 'NbtList name should match for "$currentPath"');
      expect(deserializedList.elementType, originalList.elementType,
          reason: 'NbtList elementType should match for "$currentPath"');
      expect(deserializedList.value.length, originalList.value.length,
          reason: 'NbtList length should match for "$currentPath"');

      for (int i = 0; i < originalList.value.length; i++) {
        final originalElement = originalList.value[i];
        final deserializedElement = deserializedList.value[i];
        final elementPath = '$currentPath[$i]';

        if (originalElement is NbtList && deserializedElement is NbtList) {
          // Recursively compare if the element is also an NbtList
          _compareNbtLists(originalElement, deserializedElement, 'element',
              path: elementPath);
        } else if (originalElement is NbtFloat &&
            deserializedElement is NbtFloat) {
          if (originalElement.value.isNaN) {
            expect(deserializedElement.value.isNaN, isTrue,
                reason: 'Deserialized float should be NaN for "$elementPath".');
          } else if (originalElement.value.isInfinite) {
            expect(deserializedElement.value.isInfinite, isTrue,
                reason:
                    'Deserialized float should be infinite for "$elementPath".');
            expect(deserializedElement.value.sign, originalElement.value.sign,
                reason:
                    'Sign of infinite float should match for "$elementPath".');
          } else {
            expect(
                deserializedElement.value, closeTo(originalElement.value, 1e-5),
                reason: 'NbtFloat value should be close for "$elementPath"');
          }
        } else if (originalElement is NbtDouble &&
            deserializedElement is NbtDouble) {
          if (originalElement.value.isNaN) {
            expect(deserializedElement.value.isNaN, isTrue,
                reason:
                    'Deserialized double should be NaN for "$elementPath".');
          } else if (originalElement.value.isInfinite) {
            expect(deserializedElement.value.isInfinite, isTrue,
                reason:
                    'Deserialized double should be infinite for "$elementPath".');
            expect(deserializedElement.value.sign, originalElement.value.sign,
                reason:
                    'Sign of infinite double should match for "$elementPath".');
          } else {
            expect(
                deserializedElement.value, closeTo(originalElement.value, 1e-9),
                reason: 'NbtDouble value should be close for "$elementPath"');
          }
        } else {
          // Use default equality for other tag types
          expect(deserializedElement, equals(originalElement),
              reason:
                  'NbtList element at index $i should match for "$elementPath"');
        }
      }
    }

    NbtTag _testTagCycle(NbtTag tagToTest, {String tagName = 'testTag'}) {
      if (tagToTest is! NbtEnd) {
        tagToTest.name = tagName;
      }

      final NbtCompound rootCompoundForTest =
          NbtCompound(name: 'rootTestCompound', value: [tagToTest]);
      final Uint8List writtenBytes =
      Nbt().write(rootCompoundForTest, compression: NbtCompression.none);
      final NbtCompound deserializedRoot = Nbt().read(writtenBytes);
      final NbtTag? deserializedTag = deserializedRoot[tagName];

      expect(deserializedTag, isNotNull,
          reason:
              'Deserialized tag "$tagName" from root "rootTestCompound" should not be null.');

      if (tagToTest is NbtFloat) {
        expect(deserializedTag, isA<NbtFloat>());
        final originalValue = tagToTest.value;
        final deserializedValue = (deserializedTag as NbtFloat).value;
        if (originalValue.isNaN) {
          expect(deserializedValue.isNaN, isTrue,
              reason: 'Deserialized float should be NaN for "$tagName".');
        } else if (originalValue.isInfinite) {
          expect(deserializedValue.isInfinite, isTrue,
              reason: 'Deserialized float should be infinite for "$tagName".');
          expect(deserializedValue.sign, originalValue.sign,
              reason: 'Sign of infinite float should match for "$tagName".');
        } else {
          expect(deserializedValue, closeTo(originalValue, 1e-5),
              reason:
                  'Deserialized NbtFloat value should be close to original for "$tagName"');
        }
      } else if (tagToTest is NbtDouble) {
        expect(deserializedTag, isA<NbtDouble>());
        final originalValue = tagToTest.value;
        final deserializedValue = (deserializedTag as NbtDouble).value;
        if (originalValue.isNaN) {
          expect(deserializedValue.isNaN, isTrue,
              reason: 'Deserialized double should be NaN for "$tagName".');
        } else if (originalValue.isInfinite) {
          expect(deserializedValue.isInfinite, isTrue,
              reason: 'Deserialized double should be infinite for "$tagName".');
          expect(deserializedValue.sign, originalValue.sign,
              reason: 'Sign of infinite double should match for "$tagName".');
        } else {
          expect(deserializedValue, closeTo(originalValue, 1e-9),
              reason:
                  'Deserialized NbtDouble value should be close to original for "$tagName"');
        }
      } else if (tagToTest is NbtList) {
        expect(deserializedTag, isA<NbtList>(),
            reason: 'Deserialized tag should be NbtList for "$tagName"');
        _compareNbtLists(tagToTest, deserializedTag as NbtList, tagName);
      } else {
        expect(deserializedTag, equals(tagToTest),
            reason:
                'Deserialized tag "$tagName" should be equal to the original.');
      }
      return deserializedTag!;
    }

    test('NbtByte', () {
      _testTagCycle(NbtByte(value: 42), tagName: 'myByte');
      _testTagCycle(NbtByte(value: -128), tagName: 'minByte');
      _testTagCycle(NbtByte(value: 127), tagName: 'maxByte');
    });

    test('NbtShort', () {
      _testTagCycle(NbtShort(value: 30000), tagName: 'myShort');
      _testTagCycle(NbtShort(value: -32768), tagName: 'minShort');
      _testTagCycle(NbtShort(value: 32767), tagName: 'maxShort');
    });

    test('NbtInt', () {
      _testTagCycle(NbtInt(value: 1234567890), tagName: 'myInt');
      _testTagCycle(NbtInt(value: -2147483648), tagName: 'minInt');
      _testTagCycle(NbtInt(value: 2147483647), tagName: 'maxInt');
    });

    test('NbtLong', () {
      _testTagCycle(NbtLong(value: BigInt.from(9000000000000000000)),
          tagName: 'myLong');
      _testTagCycle(NbtLong(value: BigInt.parse('-9223372036854775808')),
          tagName: 'minLong');
      _testTagCycle(NbtLong(value: BigInt.parse('9223372036854775807')),
          tagName: 'maxLong');
    });

    test('NbtFloat', () {
      _testTagCycle(NbtFloat(value: 3.14159), tagName: 'myFloat');
      _testTagCycle(NbtFloat(value: double.nan), tagName: 'nanFloat');
      _testTagCycle(NbtFloat(value: double.infinity), tagName: 'infFloat');
      _testTagCycle(NbtFloat(value: double.negativeInfinity),
          tagName: 'negInfFloat');
      _testTagCycle(NbtFloat(value: 0.0), tagName: 'zeroFloat');
      _testTagCycle(NbtFloat(value: -0.0), tagName: 'negZeroFloat');
    });

    test('NbtDouble', () {
      _testTagCycle(NbtDouble(value: 2.718281828459045), tagName: 'myDouble');
      _testTagCycle(NbtDouble(value: double.nan), tagName: 'nanDouble');
      _testTagCycle(NbtDouble(value: double.infinity), tagName: 'infDouble');
      _testTagCycle(NbtDouble(value: double.negativeInfinity),
          tagName: 'negInfDouble');
      _testTagCycle(NbtDouble(value: 0.0), tagName: 'zeroDouble');
      _testTagCycle(NbtDouble(value: -0.0), tagName: 'negZeroDouble');
    });

    test('NbtByteArray', () {
      _testTagCycle(NbtByteArray(value: Int8List.fromList([10, 20, 30, -10])),
          tagName: 'myByteArray');
      _testTagCycle(NbtByteArray(value: Int8List(0)),
          tagName: 'emptyByteArray');
      _testTagCycle(
          NbtByteArray(
              value: Int8List.fromList(List.generate(256, (i) => i - 128))),
          tagName: 'fullRangeByteArray');
    });

    test('NbtString', () {
      _testTagCycle(NbtString(value: 'Hello, NBT!'), tagName: 'myString');
      _testTagCycle(NbtString(value: ''), tagName: 'emptyString');
      _testTagCycle(NbtString(value: 'Minecraftia över Världen! £€\$'),
          tagName: 'specialCharString');
      _testTagCycle(NbtString(value: '  Leading and trailing spaces  '),
          tagName: 'spaceString');
      _testTagCycle(NbtString(value: '\t\n\rOnly whitespace\n\r\t'),
          tagName: 'whitespaceOnlyString');
      _testTagCycle(NbtString(value: '😂👍💯'), tagName: 'emojiString');
    });

    test('NbtIntArray', () {
      _testTagCycle(
          NbtIntArray(value: Int32List.fromList([100, 200, 300, -5000])),
          tagName: 'myIntArray');
      _testTagCycle(NbtIntArray(value: Int32List(0)), tagName: 'emptyIntArray');
    });

    test('NbtLongArray', () {
      _testTagCycle(
          NbtLongArray(value: [BigInt.from(12345), BigInt.from(67890)]),
          tagName: 'myLongArray');
      _testTagCycle(NbtLongArray(value: []), tagName: 'emptyLongArray');
    });

    group('NbtList', () {
      test('empty list (TAG_End elements, type inferred during write)', () {
        _testTagCycle(NbtList<NbtEnd>(value: []), tagName: 'emptyList');
      });

      test('list of NbtByte', () {
        _testTagCycle(
            NbtList<NbtByte>(value: [NbtByte(value: 1), NbtByte(value: 2)]),
            tagName: 'byteList');
      });

      test('list of NbtString', () {
        _testTagCycle(
            NbtList<NbtString>(value: [
              NbtString(value: 'a'),
              NbtString(value: 'b'),
              NbtString(value: '😂')
            ]),
            tagName: 'stringList');
      });

      test('list of NbtByteArray', () {
        _testTagCycle(
            NbtList<NbtByteArray>(value: [
              NbtByteArray(value: Int8List.fromList([1, 2, 3])),
              NbtByteArray(value: Int8List.fromList([4, 5, 6])),
            ]),
            tagName: 'listOfByteArray');
      });

      test('list of NbtIntArray', () {
        _testTagCycle(
            NbtList<NbtIntArray>(value: [
              NbtIntArray(value: Int32List.fromList([10, 20, 30])),
              NbtIntArray(value: Int32List.fromList([40, 50, 60])),
            ]),
            tagName: 'listOfIntArray');
      });

      test('list of NbtLongArray', () {
        _testTagCycle(
            NbtList<NbtLongArray>(value: [
              NbtLongArray(value: [BigInt.from(100), BigInt.from(200)]),
              NbtLongArray(value: [BigInt.from(300), BigInt.from(400)]),
            ]),
            tagName: 'listOfLongArray');
      });

      test('list of NbtCompound', () {
        _testTagCycle(
            NbtList<NbtCompound>(value: [
              NbtCompound(
                  name: null, value: [NbtInt(name: 'item1', value: 10)]),
              NbtCompound(
                  name: null, value: [NbtString(name: 'item2', value: 'test')])
            ]),
            tagName: 'compoundList');
      });

      test('list of empty NbtCompound', () {
        _testTagCycle(
            NbtList<NbtCompound>(value: [
              NbtCompound(name: null, value: []),
              NbtCompound(name: null, value: [])
            ]),
            tagName: 'listOfEmptyCompound');
      });

      test('list of empty NbtList (List<List<TAG_End>>)', () {
        _testTagCycle(
            NbtList<NbtList<NbtEnd>>(value: [
              NbtList<NbtEnd>(value: []),
              NbtList<NbtEnd>(value: [])
            ]),
            tagName: 'listListOfEmptyList');
      });

      test('deeply nested list (List<List<List<NbtInt>>>)', () {
        _testTagCycle(
            NbtList<NbtList<NbtList<NbtInt>>>(value: [
              NbtList<NbtList<NbtInt>>(value: [
                NbtList<NbtInt>(value: [NbtInt(value: 1), NbtInt(value: 2)]),
                NbtList<NbtInt>(value: [NbtInt(value: 3)])
              ]),
              NbtList<NbtList<NbtInt>>(value: [NbtList<NbtInt>(value: [])])
            ]),
            tagName: 'deeplyNestedList');
      });
    });

    group('NbtCompound', () {
      test('simple compound', () {
        _testTagCycle(
            NbtCompound(value: [
              NbtInt(name: 'intValue', value: 123),
              NbtString(name: 'stringValue', value: 'test')
            ]),
            tagName: 'simpleCompound');
      });

      test('compound with empty string name for a child tag', () {
        _testTagCycle(
            NbtCompound(value: [
              NbtInt(name: '', value: 789),
              NbtString(name: 'anotherTag', value: 'valid')
            ]),
            tagName: 'compoundWithEmptyChildName');
      });

      test('nested compound', () {
        _testTagCycle(
            NbtCompound(value: [
              NbtInt(name: 'level1Int', value: 1),
              NbtCompound(name: 'level2Compound', value: [
                NbtString(name: 'level2String', value: 'nested'),
                NbtByte(name: 'level2Byte', value: 5),
                NbtList<NbtShort>(
                    name: 'level2List', value: [NbtShort(value: 100)])
              ])
            ]),
            tagName: 'nestedCompound');
      });

      test('empty compound', () {
        _testTagCycle(NbtCompound(value: []), tagName: 'emptyCompound');
      });

      test('compound containing (almost) all tag types', () {
        final allTypesCompound = NbtCompound(value: [
          NbtByte(name: 'aByte', value: 1),
          NbtShort(name: 'aShort', value: 2),
          NbtInt(name: 'anInt', value: 3),
          NbtLong(name: 'aLong', value: BigInt.from(4)),
          NbtFloat(name: 'aFloat', value: 5.0),
          NbtDouble(name: 'aDouble', value: 6.0),
          NbtByteArray(name: 'aByteArray', value: Int8List.fromList([7, 8])),
          NbtString(name: 'aString', value: 'nine'),
          NbtList<NbtInt>(
              name: 'aList', value: [NbtInt(value: 10), NbtInt(value: 11)]),
          NbtCompound(
              name: 'aNestedCompound',
              value: [NbtByte(name: 'nestedByte', value: 12)]),
          NbtIntArray(name: 'anIntArray', value: Int32List.fromList([13, 14])),
          NbtLongArray(
              name: 'aLongArray', value: [BigInt.from(15), BigInt.from(16)]),
        ]);
        _testTagCycle(allTypesCompound, tagName: 'allTypesCompound');
      });

      test('NbtCompound tag order preservation', () {
        final originalTags = <NbtTag>[
          NbtString(name: 'second', value: 'I am second'),
          NbtInt(name: 'first', value: 1),
          NbtByte(name: 'third', value: 3),
        ];
        final compound = NbtCompound(
            name: 'orderedCompoundRoot', value: List.from(originalTags));

        final deserializedCompound =
            _testTagCycle(compound, tagName: 'orderedCompoundRoot')
                as NbtCompound;

        expect(deserializedCompound.name, compound.name);
        expect(deserializedCompound.value.length, originalTags.length,
            reason: "Number of tags should match");

        for (int i = 0; i < originalTags.length; i++) {
          expect(deserializedCompound.value[i].name, originalTags[i].name,
              reason: "Tag name at index $i should match original order");
          expect(deserializedCompound.value[i], originalTags[i],
              reason: "Tag at index $i should match original order");
        }
      });
    });
  });

  group('Malformed Data and Error Handling Tests', () {
    void expectReadNbtError(Uint8List bytes, {String? reason}) {
      expect(() => Nbt().read(bytes), throwsA(isA<FormatException>()),
          reason: reason);
    }

    test('Empty byte array', () {
      expectReadNbtError(Uint8List(0), reason: 'Should fail on empty input.');
    });

    test('Root tag is TAG_End', () {
      final writer = ByteDataWriter(endian: Endian.big);
      writer.writeInt8(NbtTagType.endTag.id);
      expectReadNbtError(writer.toBytes(),
          reason: 'Root tag cannot be TAG_End.');
    });

    test('Root tag is not TAG_Compound', () {
      final writer = ByteDataWriter(endian: Endian.big);
      writer.writeInt8(NbtTagType.byteTag.id);
      writer.writeUint16(0);
      writer.writeInt8(0);
      expectReadNbtError(writer.toBytes(),
          reason: 'Root tag must be TAG_Compound.');
    });

    test('Unexpected EOF: Truncated root compound name length', () {
      final writer = ByteDataWriter(endian: Endian.big);
      writer.writeInt8(NbtTagType.compoundTag.id);
      writer.writeInt8(0);
      expectReadNbtError(writer.toBytes(),
          reason: 'EOF before root name length fully read.');
    });

    test('Unexpected EOF: Truncated root compound name', () {
      final writer = ByteDataWriter(endian: Endian.big);
      writer.writeInt8(NbtTagType.compoundTag.id);
      writer.writeUint16(5);
      writer.write('Ro'.codeUnits);
      expectReadNbtError(writer.toBytes(),
          reason: 'EOF before root name fully read.');
    });

    test('Unexpected EOF: No TAG_End for empty root compound', () {
      final writer = ByteDataWriter(endian: Endian.big);
      writer.writeInt8(NbtTagType.compoundTag.id);
      writer.writeUint16(4);
      writer.write('root'.codeUnits);
      expectReadNbtError(writer.toBytes(),
          reason: 'EOF: Missing TAG_End for empty root compound.');
    });

    test('Unexpected EOF: Truncated TAG_Int payload', () {
      final writer = ByteDataWriter(endian: Endian.big);
      writer.writeInt8(NbtTagType.compoundTag.id);
      writer.writeUint16(0);
      writer.writeInt8(NbtTagType.intTag.id);
      writer.writeUint16(3);
      writer.write('val'.codeUnits);
      writer.writeInt16(12345);
      expectReadNbtError(writer.toBytes(),
          reason: 'EOF: Truncated TAG_Int payload.');
    });

    test('Invalid tag ID', () {
      final writer = ByteDataWriter(endian: Endian.big);
      writer.writeInt8(NbtTagType.compoundTag.id);
      writer.writeUint16(0);
      writer.writeInt8(0xFF);
      expect(() => Nbt().read(writer.toBytes()), throwsA(isA<ArgumentError>()),
          reason:
              'Invalid tag ID 0xFF (read as -1) should throw ArgumentError from NbtTagType.fromId.');
    });

    test('Negative length for TAG_String', () {
      final writer = ByteDataWriter(endian: Endian.big);
      writer.writeInt8(NbtTagType.compoundTag.id);
      writer.writeUint16(0);
      writer.writeInt8(NbtTagType.stringTag.id);
      writer.writeUint16(3);
      writer.write('str'.codeUnits);
      writer.writeInt16(-1, Endian.big);
      expectReadNbtError(writer.toBytes(),
          reason: 'Negative length for TAG_String.');
    });

    test('Unexpected EOF: Truncated TAG_String content', () {
      final writer = ByteDataWriter(endian: Endian.big);
      writer.writeInt8(NbtTagType.compoundTag.id);
      writer.writeUint16(0);
      writer.writeInt8(NbtTagType.stringTag.id);
      writer.writeUint16(3);
      writer.write('str'.codeUnits);
      writer.writeUint16(5);
      writer.write('val'.codeUnits);
      expectReadNbtError(writer.toBytes(),
          reason: 'EOF: Truncated TAG_String content.');
    });

    test('Negative size for TAG_List', () {
      final writer = ByteDataWriter(endian: Endian.big);
      writer.writeInt8(NbtTagType.compoundTag.id);
      writer.writeUint16(0);
      writer.writeInt8(NbtTagType.listTag.id);
      writer.writeUint16(4);
      writer.write('list'.codeUnits);
      writer.writeInt8(NbtTagType.byteTag.id);
      writer.writeInt32(-1, Endian.big);
      expectReadNbtError(writer.toBytes(),
          reason: 'Negative size for TAG_List.');
    });

    test('TAG_List with size > 0 but element type TAG_End', () {
      final writer = ByteDataWriter(endian: Endian.big);
      writer.writeInt8(NbtTagType.compoundTag.id);
      writer.writeUint16(0);
      writer.writeInt8(NbtTagType.listTag.id);
      writer.writeUint16(4);
      writer.write('list'.codeUnits);
      writer.writeInt8(NbtTagType.endTag.id);
      writer.writeInt32(5, Endian.big);
      expectReadNbtError(writer.toBytes(),
          reason: 'TAG_List size > 0 but element TAG_End.');
    });

    test('Unexpected EOF: Truncated TAG_List elements', () {
      final writer = ByteDataWriter(endian: Endian.big);
      writer.writeInt8(NbtTagType.compoundTag.id);
      writer.writeUint16(0);
      writer.writeInt8(NbtTagType.listTag.id);
      writer.writeUint16(4);
      writer.write('list'.codeUnits);
      writer.writeInt8(NbtTagType.byteTag.id);
      writer.writeInt32(5, Endian.big);
      writer.writeInt8(1);
      writer.writeInt8(2);
      expectReadNbtError(writer.toBytes(),
          reason: 'EOF: Truncated TAG_List elements.');
    });

    test('Negative size for TAG_Byte_Array', () {
      final writer = ByteDataWriter(endian: Endian.big);
      writer.writeInt8(NbtTagType.compoundTag.id);
      writer.writeUint16(0);
      writer.writeInt8(NbtTagType.byteArrayTag.id);
      writer.writeUint16(5);
      writer.write('bytes'.codeUnits);
      writer.writeInt32(-1, Endian.big);
      expectReadNbtError(writer.toBytes(),
          reason: 'Negative size for TAG_Byte_Array.');
    });

    test('Unexpected EOF: Truncated TAG_Int_Array elements', () {
      final writer = ByteDataWriter(endian: Endian.big);
      writer.writeInt8(NbtTagType.compoundTag.id);
      writer.writeUint16(0);
      writer.writeInt8(NbtTagType.intArrayTag.id);
      writer.writeUint16(4);
      writer.write('ints'.codeUnits);
      writer.writeInt32(3, Endian.big);
      writer.writeInt32(100);
      writer.writeInt16(200);
      expectReadNbtError(writer.toBytes(),
          reason: 'EOF: Truncated TAG_Int_Array elements.');
    });
  });
}
