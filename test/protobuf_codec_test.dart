// A tiny, dependency-free test harness so this package doesn't need
// `package:test` (and therefore no network access) just to verify itself.
// Run with: dart test/protobuf_codec_test.dart

import 'dart:convert';
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
  } on Exception {
    // expected (covers ProtoDecodeException and FormatException alike)
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

  group('decodeProtocolBufferFields (generic, no .proto)', () {
    // Same bytes as the "writer/reader scalar fields" message above, built
    // independently to also double as a schema-less decode check.
    final writer = ProtoWriter();
    writer.writeInt32(1, -42);
    writer.writeString(2, 'hello');
    final nested = ProtoWriter();
    nested.writeSint32(1, 5);
    writer.writeMessageField(3, nested.toBytes());
    final bytes = writer.toBytes();

    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final fields = decodeProtocolBufferFields(hex);

    expect(fields.length, 3, 'top-level field count');
    expect(fields[0].fieldNumber, 1, 'field 1 number');
    expect(fields[0].wireType, WireType.varint, 'field 1 wire type');
    expect(fields[0].value, -42, 'field 1 raw varint value');

    expect(fields[1].fieldNumber, 2, 'field 2 number');
    expect(fields[1].text, 'hello', 'field 2 recognised as text');

    expect(fields[2].fieldNumber, 3, 'field 3 number');
    final innerMessage = fields[2].message;
    expect(innerMessage != null, true, 'field 3 recognised as nested message');
    expect(innerMessage!.length, 1, 'nested message field count');
    expect(innerMessage[0].fieldNumber, 1, 'nested field number');

    // Whitespace-separated hex (as it's often pasted/copied) and upper case
    // both work.
    final spaced = hex
        .toUpperCase()
        .replaceAllMapped(RegExp('.{2}'), (m) => '${m.group(0)} ');
    expect(
      decodeProtocolBufferFields(spaced).length,
      3,
      'whitespace-padded, uppercase hex decodes the same',
    );

    // base64 input is also accepted (auto-detected).
    final b64 = base64Encode(bytes);
    expect(
      decodeProtocolBufferFields(b64).length,
      3,
      'base64 input decodes the same',
    );
    expect(
      decodeProtocolBufferFields(b64, format: ByteInputFormat.base64).length,
      3,
      'explicit ByteInputFormat.base64 works',
    );

    expectThrows(
      () => decodeProtocolBufferFields('not valid hex or base64!!'),
      'garbage input raises FormatException',
    );

    // A real-world example: the lat/lon-ish message from earlier.
    final person = decodeProtocolBufferFields(
      '0a180a0a0a014e10251815209703120a0a0157107a180320c704'
      '122248616e6765722c20757020686967682c206e6f7420696e2076656765'
      '746174696f6e',
    );
    expect(person.length, 2, 'address-example top-level field count');
    expect(person[1].text, 'Hanger, up high, not in vegetation',
        'address-example string field');
    final coords = person[0].message;
    expect(coords != null, true, 'address-example nested message decoded');
    expect(coords!.length, 2, 'address-example has two coordinate groups');
    expect(coords[0].message![1].value, 37, 'first coordinate degrees field');
  });

  group('decodeProtocolBufferFields handles deprecated groups', () {
    final writer = ProtoWriter();
    writer.writeTag(1, WireType.startGroup);
    writer.writeInt32(2, 99);
    writer.writeTag(1, WireType.endGroup);
    final bytes = writer.toBytes();
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    final fields = decodeProtocolBufferFields(hex);
    expect(fields.length, 1, 'one top-level group field');
    expect(fields[0].wireType, WireType.startGroup, 'group wire type');
    expect(fields[0].message!.length, 1, 'group contains one inner field');
    expect(fields[0].message![0].value, 99, 'inner field value');
  });

  group('decodeProtocolBuffer returns a {json, detail} report', () {
    const addressExampleHex = '0a180a0a0a014e10251815209703120a0a0157107a'
        '180320c704122248616e6765722c20757020686967682c206e6f7420696e207665'
        '6765746174696f6e';

    final report = decodeProtocolBuffer(addressExampleHex);
    expect(report.keys.toList()..sort(), ['detail', 'json'],
        'report has exactly json+detail keys');

    expect(
      report['detail'],
      describeProtocolBuffer(addressExampleHex),
      "'detail' matches describeProtocolBuffer's output",
    );

    const expectedJson = 'Message {\n'
        '  1: Message {\n'
        '    1: Message {\n'
        '      1: "N"\n'
        '      2: 37\n'
        '      3: 21\n'
        '      4: 407\n'
        '    }\n'
        '    2: Message {\n'
        '      1: "W"\n'
        '      2: 122\n'
        '      3: 3\n'
        '      4: 583\n'
        '    }\n'
        '  }\n'
        '  2: "Hanger, up high, not in vegetation"\n'
        '}';
    expect(report['json'], expectedJson,
        "'json' matches the expected pseudo-JSON tree");

    // A field whose bytes are neither printable text nor a parseable nested
    // message falls back to a hex literal in the 'json' rendering.
    final writer = ProtoWriter();
    writer.writeBytesField(1, [0xff, 0x00, 0x01]);
    final hex =
        writer.toBytes().map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    expect(
      decodeProtocolBuffer(hex)['json'],
      'Message {\n  1: 0xff0001\n}',
      'raw (non-text, non-message) bytes render as a 0x-prefixed hex literal',
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
