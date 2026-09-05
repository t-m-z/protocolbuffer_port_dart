import 'dart:typed_data';

import 'reader.dart';
import 'writer.dart';

/// Base class for hand-written Protocol Buffers messages.
///
/// Unlike `package:protobuf`, this library does not generate code from
/// `.proto` files: subclasses declare their own fields as plain Dart
/// members and implement [writeTo]/[readFrom] using [ProtoWriter]/
/// [ProtoReader]. See `example/person_example.dart` for a full message.
abstract class ProtoMessage {
  /// Serializes this message's fields into [writer]. Only write fields that
  /// should appear on the wire (proto3 generated code omits default-valued
  /// fields; whether to follow that convention is up to the subclass).
  void writeTo(ProtoWriter writer);

  /// Populates this message's fields by reading from [reader] until
  /// [ProtoReader.isAtEnd]. Implementations should `switch` on
  /// `tag.fieldNumber` and call [ProtoReader.skipField] for unrecognised
  /// field numbers so decoding stays forward-compatible.
  void readFrom(ProtoReader reader);

  /// Encodes this message to its binary wire format representation.
  Uint8List toBuffer() {
    final writer = ProtoWriter();
    writeTo(writer);
    return writer.toBytes();
  }

  /// Decodes [bytes] into this message, discarding any previously set
  /// field values only insofar as [readFrom] overwrites them.
  void mergeFromBuffer(List<int> bytes) {
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    readFrom(ProtoReader(data));
  }
}

/// Decodes [bytes] into a fresh message created by [create].
///
/// Example:
/// ```dart
/// final person = decode(bytes, Person.new);
/// ```
T decode<T extends ProtoMessage>(List<int> bytes, T Function() create) {
  final message = create();
  message.mergeFromBuffer(bytes);
  return message;
}
