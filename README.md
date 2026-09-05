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
- `example/person_example.dart` — a hand-written "address book" message
  (`Person` / `Address` / `PhoneNumber`, including a nested message, a
  repeated message field and a packed repeated scalar field).
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
```

No dependency on `package:test` is required — the test file is a small,
self-contained script that exits non-zero on failure.
