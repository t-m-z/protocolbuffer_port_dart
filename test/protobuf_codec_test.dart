// A tiny, dependency-free test harness so this package doesn't need
// `package:test` (and therefore no network access) just to verify itself.
// Run with: dart test/protobuf_codec_test.dart

import 'dart:typed_data';

import 'package:protobuf_codec/protobuf_codec.dart';

int _failures = 0;
int _checks = 0;

void expect(Object? actual, Object? expected, String label) {
  _checks++;
  final ok = switch (actual) {
    Uint8List a when expected is List<int> => _listEquals(a, expected),
    List a when expected is List => _listEquals(a, expected),
    _ => actual == expected,
  };
  if (!ok) {
    _failures++;
    // ignore: avoid_print
    print('FAIL: $label\n  expected: $expected\n  actual:   $actual');
  }
}

void expectThrows(void Function() body, String label) {
  _checks++;
  try {
    body();
    _failures++;
    // ignore: avoid_print
    print('FAIL: $label (expected an exception, none was thrown)');
  } on ProtoDecodeException {
    // expected
  }
}

bool _listEquals(List a, List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void group(String name, void Function() body) {
  // ignore: avoid_print
  print('-- $name --');
  body();
}

// ---------------------------------------------------------------------
// A small hand-written message used to exercise ProtoWriter/ProtoReader
// together, independent of the address-book example.
// ---------------------------------------------------------------------

class Point extends ProtoMessage {
  Point({this.x = 0, this.y = 0, this.label = ''});

  int x;
  int y;
  String label;

  @override
  void writeTo(ProtoWriter writer) {
    writer.writeSint32(1, x);
    writer.writeSint32(2, y);
    if (label.isNotEmpty) writer.writeString(3, label);
  }

  @override
  void readFrom(ProtoReader reader) {
    while (!reader.isAtEnd) {
      final tag = reader.readTag();
      switch (tag.fieldNumber) {
        case 1:
          x = reader.readSint32();
        case 2:
          y = reader.readSint32();
        case 3:
          label = reader.readString();
        default:
          reader.skipField(tag.wireType);
      }
    }
  }
}

void main() {
  group('varint round trip', () {
    for (final v in [0, 1, 127, 128, 300, 16384, 1 << 40, -1, -2147483648]) {
      final out = BytesBuilder();
      writeVarint(out, v);
      final bytes = out.toBytes();
      final result = readVarint(bytes, 0);
      expect(result.value, v, 'varint round trip for $v');
      expect(result.bytesRead, bytes.length, 'varint bytesRead for $v');
    }
  });

  group('known varint encodings', () {
    expect(encodeVarint(1), [0x01], 'encode 1');
    expect(
        encodeVarint(150), [0x96, 0x01], 'encode 150 (protobuf docs example)');
    expect(
      encodeVarint(-1),
      [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01],
      'encode int64 -1 as 10 bytes',
    );
  });

  group('zigzag encoding', () {
    final cases = {0: 0, -1: 1, 1: 2, -2: 3, 2: 4, 2147483647: 4294967294};
    cases.forEach((n, expected) {
      expect(zigZagEncode(n), expected, 'zigZagEncode($n)');
      expect(zigZagDecode(expected), n, 'zigZagDecode($expected)');
    });
  });

  group('tag encode/decode', () {
    final tag = makeTag(5, WireType.lengthDelimited);
    final decoded = decodeTag(tag);
    expect(decoded.fieldNumber, 5, 'field number round trips');
    expect(decoded.wireType, WireType.lengthDelimited, 'wire type round trips');
  });

  group('writer/reader scalar fields', () {
    final writer = ProtoWriter();
    writer.writeInt32(1, -42);
    writer.writeUint32(2, 4000000000);
    writer.writeBool(3, true);
    writer.writeFixed32(4, 0xCAFEBABE);
    writer.writeFloat(5, 1.5);
    writer.writeDouble(6, 2.5);
    writer.writeString(7, 'hello');
    writer.writeBytesField(8, [1, 2, 3]);
    final bytes = writer.toBytes();

    final reader = ProtoReader(bytes);
    while (!reader.isAtEnd) {
      final tag = reader.readTag();
      switch (tag.fieldNumber) {
        case 1:
          expect(reader.readInt32(), -42, 'int32 field');
        case 2:
          expect(reader.readUint32(), 4000000000, 'uint32 field');
        case 3:
          expect(reader.readBool(), true, 'bool field');
        case 4:
          expect(reader.readFixed32(), 0xCAFEBABE, 'fixed32 field');
        case 5:
          expect(reader.readFloat(), 1.5, 'float field');
        case 6:
          expect(reader.readDouble(), 2.5, 'double field');
        case 7:
          expect(reader.readString(), 'hello', 'string field');
        case 8:
          expect(reader.readBytesField(), [1, 2, 3], 'bytes field');
        default:
          reader.skipField(tag.wireType);
      }
    }
  });

  group('packed repeated varint field', () {
    final writer = ProtoWriter();
    writer.writePackedVarint(1, [1, 2, 3, 300]);
    final reader = ProtoReader(writer.toBytes());
    final tag = reader.readTag();
    expect(tag.fieldNumber, 1, 'packed field number');
    expect(reader.readPackedVarint(), [1, 2, 3, 300], 'packed values');
  });

  group('nested message', () {
    final inner = Point(x: -5, y: 10, label: 'origin');
    final writer = ProtoWriter();
    writer.writeMessageField(1, inner.toBuffer());
    final reader = ProtoReader(writer.toBytes());
    final tag = reader.readTag();
    expect(tag.wireType, WireType.lengthDelimited, 'nested message wire type');
    final decoded = Point()..readFrom(reader.readMessageField());
    expect(decoded.x, -5, 'nested x');
    expect(decoded.y, 10, 'nested y');
    expect(decoded.label, 'origin', 'nested label');
  });

  group('ProtoMessage.toBuffer / decode round trip', () {
    final original = Point(x: 123, y: -456, label: 'p1');
    final decoded = decode(original.toBuffer(), Point.new);
    expect(decoded.x, original.x, 'decode x');
    expect(decoded.y, original.y, 'decode y');
    expect(decoded.label, original.label, 'decode label');
  });

  group('unknown fields are skipped for forward compatibility', () {
    // Simulate a message from a "newer" schema with an extra field 99 that
    // Point doesn't know about, mixed with fields it does know (matching
    // Point's actual field types: sint32 x=1, string label=3).
    final writer = ProtoWriter();
    writer.writeSint32(1, 7);
    writer.writeInt32(99, 12345); // unknown to Point's schema
    writer.writeString(3, 'still-works');
    final bytes = writer.toBytes();

    final p = Point()..readFrom(ProtoReader(bytes));
    expect(p.x, 7, 'field before an unknown field is read');
    expect(p.label, 'still-works', 'field after an unknown field is read');
  });

  group('truncated input raises ProtoDecodeException', () {
    expectThrows(
      () => readVarint([0x80], 0),
      'truncated varint (continuation bit with no more bytes)',
    );
    expectThrows(
      () {
        final reader = ProtoReader(Uint8List.fromList([0x0A, 0x05, 1, 2]));
        reader.readTag();
        reader.readBytesField(); // claims length 5 but only 2 bytes remain
      },
      'length-delimited field longer than remaining buffer',
    );
  });

  // ignore: avoid_print
  print('$_checks checks, $_failures failures');
  if (_failures > 0) {
    // ignore: avoid_print
    print('FAILED');
    // Throwing gives this script a non-zero exit code, so it plugs into CI.
    throw StateError('$_failures test check(s) failed');
  } else {
    // ignore: avoid_print
    print('All tests passed.');
  }
}
