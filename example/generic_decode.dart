// Demonstrates decodeProtocolBuffer/describeProtocolBuffer: decoding raw
// Protocol Buffers bytes with no .proto schema at all, just from a
// hex/base64 string.
//
// Usage: dart run example/generic_decode.dart <hex or base64 string>

import 'package:protobuf_codec/protobuf_codec.dart';

void main(List<String> args) {
  final input = args.isNotEmpty
      ? args[0]
      : '0a180a0a0a014e10251815209703120a0a0157107a180320c704'
          '122248616e6765722c20757020686967682c206e6f7420696e2076656765'
          '746174696f6e';

  print(describeProtocolBuffer(input));
}
