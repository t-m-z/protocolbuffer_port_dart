/// The wire types defined by the Protocol Buffers binary encoding.
///
/// See: https://protobuf.dev/programming-guides/encoding/#structure
enum WireType {
  /// int32, int64, uint32, uint64, sint32, sint64, bool, enum
  varint(0),

  /// fixed64, sfixed64, double
  fixed64(1),

  /// string, bytes, embedded messages, packed repeated fields
  lengthDelimited(2),

  /// groups (deprecated, kept only so unknown fields can be skipped)
  startGroup(3),

  /// groups (deprecated, kept only so unknown fields can be skipped)
  endGroup(4),

  /// fixed32, sfixed32, float
  fixed32(5);

  const WireType(this.value);

  /// The 3-bit value stored in the low bits of a field tag.
  final int value;

  static WireType fromValue(int value) {
    switch (value) {
      case 0:
        return WireType.varint;
      case 1:
        return WireType.fixed64;
      case 2:
        return WireType.lengthDelimited;
      case 3:
        return WireType.startGroup;
      case 4:
        return WireType.endGroup;
      case 5:
        return WireType.fixed32;
      default:
        throw ProtoDecodeException('Unknown wire type: $value');
    }
  }
}

/// A decoded field tag: the field number together with its wire type.
typedef FieldTag = ({int fieldNumber, WireType wireType});

/// Combines a field number and wire type into the varint-encoded tag that
/// precedes every field in the wire format.
int makeTag(int fieldNumber, WireType wireType) {
  if (fieldNumber <= 0) {
    throw ArgumentError.value(
      fieldNumber,
      'fieldNumber',
      'Field numbers must be positive',
    );
  }
  return (fieldNumber << 3) | wireType.value;
}

/// Splits a raw tag value back into its field number and wire type.
FieldTag decodeTag(int tag) {
  final wireType = WireType.fromValue(tag & 0x7);
  final fieldNumber = tag >>> 3;
  return (fieldNumber: fieldNumber, wireType: wireType);
}

/// Thrown when a byte sequence cannot be interpreted as valid Protocol
/// Buffers wire format data.
class ProtoDecodeException implements Exception {
  ProtoDecodeException(this.message);

  final String message;

  @override
  String toString() => 'ProtoDecodeException: $message';
}
