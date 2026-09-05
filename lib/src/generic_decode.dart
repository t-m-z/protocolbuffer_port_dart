import 'dart:convert';
import 'dart:typed_data';

import 'reader.dart';
import 'wire_format.dart';

/// How the input string passed to [decodeProtocolBuffer] encodes the raw
/// message bytes.
enum ByteInputFormat {
  /// Try hex first, then fall back to base64. This is almost always the
  /// right choice: hex and base64 alphabets barely overlap in practice
  /// (base64 uses `+`, `/`, `=`, and mixed case beyond `a-f`/`A-F`).
  auto,

  /// A hex string, e.g. `"0a0568656c6c6f"`. Whitespace between/around bytes
  /// is tolerated and stripped; case-insensitive.
  hex,

  /// A standard (RFC 4648) base64 string.
  base64,
}

/// One decoded field from a Protocol Buffers message, read without any
/// `.proto` schema.
///
/// The wire format always tells you a field's number and wire type
/// unambiguously; it never tells you what the field *means* (its intended
/// name or scalar type). For `lengthDelimited` fields in particular, the
/// same bytes on the wire represent a `string`, `bytes`, an embedded
/// message, or a packed repeated scalar -- there's no way to tell which
/// without the schema. [text] and [message] carry best-effort guesses for
/// the first two cases; [value] always carries the raw decoded data.
class DecodedField {
  DecodedField({
    required this.fieldNumber,
    required this.wireType,
    required this.value,
    this.text,
    this.message,
  });

  /// The field number recovered from the tag.
  final int fieldNumber;

  /// The wire type recovered from the tag.
  final WireType wireType;

  /// The raw decoded value:
  /// - `varint`: an [int] (the 64-bit two's complement bit pattern; this is
  ///   the right value whether the field is really an `int32`/`int64`,
  ///   `uint32`/`uint64`, `sint32`/`sint64` (still ZigZag-encoded here),
  ///   `bool`, or `enum` -- telling those apart needs the schema)
  /// - `fixed32`/`fixed64`: an [int] (the unsigned bit pattern; could
  ///   likewise be a `float`/`double` bit pattern, or `sfixed*`)
  /// - `lengthDelimited`: the raw [Uint8List] payload
  /// - `startGroup`: the `List<DecodedField>` of fields found inside the
  ///   (deprecated) group, same as [message]
  final Object value;

  /// Set when a `lengthDelimited` field's bytes are valid, printable UTF-8
  /// -- the shape of a `string` field.
  final String? text;

  /// Set when a `lengthDelimited` field's bytes, taken on their own, fully
  /// parse as a well-formed Protocol Buffers message (every byte consumed,
  /// no invalid tags) -- the shape of an embedded message field. This is a
  /// heuristic: some byte strings that are not actually submessages
  /// (arbitrary binary blobs, some `bytes`/packed-scalar fields) can still
  /// happen to parse this way, especially when short.
  final List<DecodedField>? message;

  /// A multi-line, indented rendering of this field for humans inspecting
  /// an unknown payload -- includes the raw value plus any [text]/[message]
  /// guesses.
  String describe({int indent = 0}) {
    final pad = '  ' * indent;
    final buffer = StringBuffer();
    switch (wireType) {
      case WireType.varint:
        buffer.writeln('${pad}field $fieldNumber (varint) = $value');
      case WireType.fixed32:
        buffer.writeln('${pad}field $fieldNumber (fixed32) = $value');
      case WireType.fixed64:
        buffer.writeln('${pad}field $fieldNumber (fixed64) = $value');
      case WireType.lengthDelimited:
        final bytes = value as Uint8List;
        buffer.writeln(
          '${pad}field $fieldNumber (length-delimited, ${bytes.length} '
          'bytes) = ${_hex(bytes)}',
        );
        final text = this.text;
        if (text != null) {
          buffer.writeln('$pad  as string: ${jsonEncode(text)}');
        }
        final nested = message;
        if (nested != null && nested.isNotEmpty) {
          buffer.writeln('$pad  as nested message:');
          for (final field in nested) {
            buffer.write(field.describe(indent: indent + 2));
          }
        }
      case WireType.startGroup:
        buffer.writeln('${pad}field $fieldNumber (group):');
        for (final field in message ?? const []) {
          buffer.write(field.describe(indent: indent + 1));
        }
      case WireType.endGroup:
        // Never produced standalone by decodeProtocolBuffer.
        buffer.writeln('${pad}field $fieldNumber (end group)');
    }
    return buffer.toString();
  }

  @override
  String toString() => describe();
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Decodes [input] -- a string holding raw Protocol Buffers message bytes,
/// hex- or base64-encoded (see [format]) -- into its top-level fields,
/// without needing a `.proto` schema.
///
/// Every field's number and wire type is always recovered exactly; see
/// [DecodedField] for what can (and can't) be inferred beyond that.
/// `lengthDelimited` fields are recursively decoded the same way for the
/// [DecodedField.message] guess, so nested/repeated embedded messages come
/// back as a full tree.
///
/// Throws [FormatException] if [input] isn't valid hex/base64, or
/// [ProtoDecodeException] if the decoded bytes aren't a well-formed
/// sequence of protobuf tag/value pairs.
List<DecodedField> decodeProtocolBuffer(
  String input, {
  ByteInputFormat format = ByteInputFormat.auto,
}) {
  final bytes = _stringToBytes(input, format);
  return _decodeFields(ProtoReader(bytes));
}

/// Convenience wrapper around [decodeProtocolBuffer] that renders the
/// result as a human-readable, indented multi-line string (see
/// [DecodedField.describe]) instead of a [DecodedField] tree.
String describeProtocolBuffer(
  String input, {
  ByteInputFormat format = ByteInputFormat.auto,
}) {
  final fields = decodeProtocolBuffer(input, format: format);
  return fields.map((f) => f.describe()).join();
}

List<DecodedField> _decodeFields(ProtoReader reader,
    {bool insideGroup = false}) {
  final fields = <DecodedField>[];
  while (!reader.isAtEnd) {
    final tag = reader.readTag();
    if (tag.wireType == WireType.endGroup) {
      if (insideGroup) return fields;
      throw ProtoDecodeException('Unexpected standalone end-group marker');
    }
    switch (tag.wireType) {
      case WireType.varint:
        fields.add(DecodedField(
          fieldNumber: tag.fieldNumber,
          wireType: tag.wireType,
          value: reader.readInt64(),
        ));
      case WireType.fixed32:
        fields.add(DecodedField(
          fieldNumber: tag.fieldNumber,
          wireType: tag.wireType,
          value: reader.readFixed32(),
        ));
      case WireType.fixed64:
        fields.add(DecodedField(
          fieldNumber: tag.fieldNumber,
          wireType: tag.wireType,
          value: reader.readFixed64(),
        ));
      case WireType.lengthDelimited:
        final data = reader.readBytesField();
        fields.add(DecodedField(
          fieldNumber: tag.fieldNumber,
          wireType: tag.wireType,
          value: data,
          text: _tryDecodeText(data),
          message: _tryDecodeNested(data),
        ));
      case WireType.startGroup:
        // Deprecated groups have no length prefix: their fields are inline
        // in the same byte stream, terminated by a matching end-group tag.
        final groupFields = _decodeFields(reader, insideGroup: true);
        fields.add(DecodedField(
          fieldNumber: tag.fieldNumber,
          wireType: tag.wireType,
          value: groupFields,
          message: groupFields,
        ));
      case WireType.endGroup:
        break; // unreachable: handled above before the switch
    }
  }
  if (insideGroup) {
    throw ProtoDecodeException('Truncated group: missing end-group tag');
  }
  return fields;
}

List<DecodedField>? _tryDecodeNested(Uint8List bytes) {
  if (bytes.isEmpty) return null;
  try {
    // _decodeFields only returns once the reader is fully consumed (or
    // throws), so success here already means every byte parsed cleanly.
    return _decodeFields(ProtoReader(bytes));
  } on ProtoDecodeException {
    return null;
  }
}

String? _tryDecodeText(Uint8List bytes) {
  if (bytes.isEmpty) return null;
  String text;
  try {
    text = utf8.decode(bytes, allowMalformed: false);
  } on FormatException {
    return null;
  }
  final printable = text.runes.every(
    (r) => (r >= 0x20 && r < 0x7f) || r == 0x09 || r == 0x0a || r == 0x0d,
  );
  return printable ? text : null;
}

Uint8List _stringToBytes(String input, ByteInputFormat format) {
  switch (format) {
    case ByteInputFormat.hex:
      return _hexToBytes(input);
    case ByteInputFormat.base64:
      return base64.decode(_stripWhitespace(input));
    case ByteInputFormat.auto:
      if (_looksLikeHex(input)) {
        return _hexToBytes(input);
      }
      try {
        return base64.decode(_stripWhitespace(input));
      } on FormatException {
        throw FormatException(
          'Input is neither a valid hex string nor valid base64',
          input,
        );
      }
  }
}

String _stripWhitespace(String s) => s.replaceAll(RegExp(r'\s+'), '');

bool _looksLikeHex(String s) {
  final clean = _stripWhitespace(s);
  if (clean.isEmpty || clean.length.isOdd) return false;
  return RegExp(r'^[0-9a-fA-F]+$').hasMatch(clean);
}

Uint8List _hexToBytes(String s) {
  final clean = _stripWhitespace(s);
  if (clean.isEmpty || clean.length.isOdd) {
    throw FormatException(
      'Hex string must be non-empty with an even number of digits',
      s,
    );
  }
  final out = Uint8List(clean.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    final byteStr = clean.substring(i * 2, i * 2 + 2);
    final byte = int.tryParse(byteStr, radix: 16);
    if (byte == null) {
      throw FormatException('Invalid hex byte "$byteStr"', s, i * 2);
    }
    out[i] = byte;
  }
  return out;
}
