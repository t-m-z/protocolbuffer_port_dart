# protobuf_codec

A small, **dependency-free** Dart implementation of the
[Protocol Buffers binary wire format](https://protobuf.dev/programming-guides/encoding/):
varint/ZigZag helpers, a low-level `ProtoWriter`/`ProtoReader` for the wire
format itself, and a `ProtoMessage` base class for hand-written message
classes.

This library does **not** compile `.proto` files (there's no code
generator here) — it gives you the primitives to encode/decode messages by
hand, wire-compatible with the reference protobuf implementations (Java,
C++, Python, `package:protobuf`, ...). It's useful when you want full
control over the generated Dart types, or want protobuf-wire-format
encoding without adding `protoc` to your build.

## Contents

- `lib/src/varint.dart` — varint and ZigZag encode/decode.
- `lib/src/wire_format.dart` — `WireType`, field tag encode/decode.
- `lib/src/writer.dart` — `ProtoWriter`: append fields, get the encoded bytes.
- `lib/src/reader.dart` — `ProtoReader`: iterate tags, decode field values,
  skip unknown fields.
- `lib/src/message.dart` — `ProtoMessage` base class and a `decode()` helper.
- `lib/src/generic_decode.dart` — `decodeProtocolBuffer` /
  `decodeProtocolBufferFields` / `describeProtocolBuffer`: schema-less
  decoding of a hex/base64 string, with no `.proto` at all.
- `example/person_example.dart` — a hand-written "address book" message
  (`Person` / `Address` / `PhoneNumber`, including a nested message, a
  repeated message field and a packed repeated scalar field).
- `example/generic_decode.dart` — decodes an arbitrary hex/base64 string
  with `decodeProtocolBuffer` and prints its `json`/`detail` report.
- `test/protobuf_codec_test.dart` — a small dependency-free test suite.

## Usage

Declare a message by extending `ProtoMessage` and implementing `writeTo`/
`readFrom`:

```dart
import 'package:protobuf_codec/protobuf_codec.dart';

class Point extends ProtoMessage {
  Point({this.x = 0, this.y = 0, this.label = ''});

  int x;
  int y;
  String label;

  @override
  void writeTo(ProtoWriter writer) {
    // proto3 generated code only serializes non-default values.
    if (x != 0) writer.writeSint32(1, x);
    if (y != 0) writer.writeSint32(2, y);
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
          // Forward compatibility: skip fields you don't know about.
          reader.skipField(tag.wireType);
      }
    }
  }
}

void main() {
  final original = Point(x: -5, y: 10, label: 'origin');

  final bytes = original.toBuffer(); // Uint8List
  final decoded = decode(bytes, Point.new);

  print(decoded.x); // -5
}
```

Nested messages are just bytes: write them with `writeMessageField` and
read them with `readMessageField()` (which hands back a `ProtoReader`
scoped to exactly the nested message):

```dart
writer.writeMessageField(5, address.toBuffer());
...
address = Address()..readFrom(reader.readMessageField());
```

Repeated scalar fields are typically **packed** in proto3
(`writePackedVarint` / `readPackedVarint`, plus fixed32/fixed64 variants);
repeated message fields are just one `writeMessageField` call per element.

See `example/person_example.dart` for a complete, runnable example
(`dart run example/person_example.dart`).

## Decoding without a schema

If you don't have (or don't want to write) the message class,
`decodeProtocolBuffer` walks any Protocol Buffers byte string generically,
using only what the wire format itself guarantees — every field's number
and wire type, always — and returns a two-key report:

```dart
import 'package:protobuf_codec/protobuf_codec.dart';

void main() {
  // Accepts hex or base64 (auto-detected); whitespace/case in hex is fine.
  final report = decodeProtocolBuffer(
    '0a180a0a0a014e10251815209703120a0a0157107a180320c704'
    '122248616e6765722c20757020686967682c206e6f7420696e2076656765'
    '746174696f6e',
  );

  print(report['json']);   // a compact Message { ... } tree
  print(report['detail']); // one line per field, wire types and bytes spelled out
}
```

`report['json']` looks like this:

```
Message {
  1: Message {
    1: Message {
      1: "N"
      2: 37
      3: 21
      4: 407
    }
    2: Message {
      1: "W"
      2: 122
      3: 3
      4: 583
    }
  }
  2: "Hanger, up high, not in vegetation"
}
```

Note this is **field numbers, not field names** — the wire format never
carries names, so `decodeProtocolBuffer` can't know that field 1 here
"means" a coordinate, or annotate its sub-fields as
hemisphere/degrees/minutes/tenths-of-a-second. That kind of comment can
only come from the `.proto` schema (or a human who recognises the shape);
without one, the tree above — bytes, structure, and nothing else — is as
far as any generic decoder can go.

`report['detail']` is the same result as calling `describeProtocolBuffer`
directly (also exported, if you just want that string).

For programmatic access to the decoded tree itself (rather than either
string rendering), use `decodeProtocolBufferFields`, which returns a
`List<DecodedField>`. Since the wire format alone never says what a field
*means*, its `lengthDelimited` fields (wire type 2 — `string`, `bytes`,
embedded messages, and packed repeated scalars all share it) are
additionally, heuristically checked for:

- **`text`** — set if the bytes are valid, printable UTF-8 (the shape of a
  `string` field);
- **`message`** — set if the bytes, on their own, fully parse as a
  well-formed nested Protocol Buffers message with no leftover bytes (the
  shape of an embedded message field), decoded recursively so a whole tree
  of nested/repeated messages comes back at once. (`decodeProtocolBuffer`'s
  `json`/`detail` strings are both built from this same tree.)

Both are best-effort guesses, not proof — a `bytes` field or a packed
repeated field can coincidentally look like one of these, especially when
short (in `report['json']`, bytes that are neither fall back to a
`0x`-prefixed hex literal). `field.value` always carries the raw decoded
data (`int` for varint/fixed32/fixed64, `Uint8List` for length-delimited)
regardless. The deprecated `group` wire type is also handled, decoding its
inline fields into `message`.

See `example/generic_decode.dart` for a runnable version
(`dart run example/generic_decode.dart <hex-or-base64>`).

## Supported field types

| proto type                     | Writer method(s)                        | Reader method(s)                      |
|--------------------------------|------------------------------------------|----------------------------------------|
| `int32` / `int64`               | `writeInt32` / `writeInt64`               | `readInt32` / `readInt64`               |
| `uint32` / `uint64`             | `writeUint32` / `writeUint64`             | `readUint32` / `readUint64`             |
| `sint32` / `sint64`             | `writeSint32` / `writeSint64`             | `readSint32` / `readSint64`             |
| `bool`                          | `writeBool`                               | `readBool`                              |
| `enum`                          | `writeEnum`                               | `readEnum`                              |
| `fixed32` / `sfixed32` / `float`| `writeFixed32` / `writeSfixed32` / `writeFloat` | `readFixed32` / `readSfixed32` / `readFloat` |
| `fixed64` / `sfixed64` / `double`| `writeFixed64` / `writeSfixed64` / `writeDouble` | `readFixed64` / `readSfixed64` / `readDouble` |
| `string`                        | `writeString`                             | `readString`                            |
| `bytes`                         | `writeBytesField`                         | `readBytesField`                        |
| embedded message                | `writeMessageField`                       | `readMessageField`                      |
| packed `repeated` varint types  | `writePackedVarint`                       | `readPackedVarint`                      |
| packed `repeated` fixed32 types | `writePackedFixed32`                      | `readPackedFixed32`                     |
| packed `repeated` fixed64 types | `writePackedFixed64`                      | `readPackedFixed64`                     |

Unknown field numbers (e.g. written by a newer schema version) should be
passed to `ProtoReader.skipField(tag.wireType)`, which also knows how to
skip the deprecated `group` wire type.

## Notes / limitations

- **64-bit integers on the web**: Dart's `int` is a 64-bit two's complement
  value on the Dart VM / AOT, which is what this library relies on for
  varint math (e.g. shifting a negative number with `>>>`). Compiled to
  JavaScript (`dart compile js`, plain web without WASM), `int` loses
  precision above 2^53, so `int64`/`uint64`/`sint64`/`fixed64`/`sfixed64`
  values outside that range won't round-trip exactly. `int32`-range fields
  and everything else are unaffected. If you need exact 64-bit values on
  the web, encode/decode those specific fields via `BigInt` instead of
  relying on this library's `int`-based helpers.
- **`uint64`/`fixed64` values with the top bit set** come back as the
  equivalent *negative* Dart `int` (its bit pattern is correct, but you
  can't print it as the intended large positive number without converting,
  e.g. `value.toUnsigned(64)` won't help since `int` can't hold the result —
  use `BigInt.from(value).toUnsigned(64)` if you need the decimal value).
- No `.proto` parsing/code generation, no reflection, no JSON mapping —
  this is wire format only.

## Testing

```
dart pub get
dart analyze
dart test/protobuf_codec_test.dart
dart run example/person_example.dart
dart run example/generic_decode.dart
```

No dependency on `package:test` is required — the test file is a small,
self-contained script that exits non-zero on failure.
