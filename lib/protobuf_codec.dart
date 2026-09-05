/// A small, dependency-free Dart implementation of the Protocol Buffers
/// binary wire format.
///
/// This library does not compile `.proto` files; instead it gives you the
/// primitives ([ProtoWriter], [ProtoReader], varint/ZigZag helpers) and a
/// [ProtoMessage] base class so you can hand-write encoders/decoders for
/// your own message shapes, wire-compatible with the reference protobuf
/// implementations.
library;

export 'src/generic_decode.dart'
    show
        ByteInputFormat,
        DecodedField,
        decodeProtocolBuffer,
        describeProtocolBuffer;
export 'src/message.dart' show ProtoMessage, decode;
export 'src/reader.dart' show ProtoReader;
export 'src/varint.dart'
    show
        VarintResult,
        maxVarintBytes,
        writeVarint,
        encodeVarint,
        readVarint,
        zigZagEncode,
        zigZagDecode;
export 'src/wire_format.dart'
    show WireType, FieldTag, makeTag, decodeTag, ProtoDecodeException;
export 'src/writer.dart' show ProtoWriter;
