// Hand-written equivalent of a classic protobuf "address book" schema:
//
//   enum PhoneType { MOBILE = 0; HOME = 1; WORK = 2; }
//
//   message PhoneNumber {
//     string number = 1;
//     PhoneType type = 2;
//   }
//
//   message Address {
//     string city = 1;
//     string zip_code = 2;
//   }
//
//   message Person {
//     string name = 1;
//     int32 id = 2;
//     string email = 3;
//     repeated PhoneNumber phones = 4;
//     Address address = 5;
//     repeated int32 lucky_numbers = 6; // packed by default in proto3
//   }
//
// This is written by hand against the low-level ProtoWriter/ProtoReader
// API -- there is no `.proto` compiler involved, which is the point of
// this package.

import 'package:protobuf_codec/protobuf_codec.dart';

enum PhoneType {
  mobile(0),
  home(1),
  work(2);

  const PhoneType(this.value);
  final int value;

  static PhoneType fromValue(int value) => switch (value) {
        0 => PhoneType.mobile,
        1 => PhoneType.home,
        2 => PhoneType.work,
        _ => PhoneType.mobile, // unknown enum values fall back to the default
      };
}

class PhoneNumber extends ProtoMessage {
  PhoneNumber({this.number = '', this.type = PhoneType.mobile});

  String number;
  PhoneType type;

  @override
  void writeTo(ProtoWriter writer) {
    if (number.isNotEmpty) writer.writeString(1, number);
    if (type != PhoneType.mobile) writer.writeEnum(2, type.value);
  }

  @override
  void readFrom(ProtoReader reader) {
    while (!reader.isAtEnd) {
      final tag = reader.readTag();
      switch (tag.fieldNumber) {
        case 1:
          number = reader.readString();
        case 2:
          type = PhoneType.fromValue(reader.readEnum());
        default:
          reader.skipField(tag.wireType);
      }
    }
  }

  @override
  String toString() => 'PhoneNumber(number: $number, type: $type)';
}

class Address extends ProtoMessage {
  Address({this.city = '', this.zipCode = ''});

  String city;
  String zipCode;

  @override
  void writeTo(ProtoWriter writer) {
    if (city.isNotEmpty) writer.writeString(1, city);
    if (zipCode.isNotEmpty) writer.writeString(2, zipCode);
  }

  @override
  void readFrom(ProtoReader reader) {
    while (!reader.isAtEnd) {
      final tag = reader.readTag();
      switch (tag.fieldNumber) {
        case 1:
          city = reader.readString();
        case 2:
          zipCode = reader.readString();
        default:
          reader.skipField(tag.wireType);
      }
    }
  }

  @override
  String toString() => 'Address(city: $city, zipCode: $zipCode)';
}

class Person extends ProtoMessage {
  Person({
    this.name = '',
    this.id = 0,
    this.email = '',
    List<PhoneNumber>? phones,
    this.address,
    List<int>? luckyNumbers,
  })  : phones = phones ?? [],
        luckyNumbers = luckyNumbers ?? [];

  String name;
  int id;
  String email;
  List<PhoneNumber> phones;
  Address? address;
  List<int> luckyNumbers;

  @override
  void writeTo(ProtoWriter writer) {
    if (name.isNotEmpty) writer.writeString(1, name);
    if (id != 0) writer.writeInt32(2, id);
    if (email.isNotEmpty) writer.writeString(3, email);
    for (final phone in phones) {
      writer.writeMessageField(4, phone.toBuffer());
    }
    final address = this.address;
    if (address != null) {
      writer.writeMessageField(5, address.toBuffer());
    }
    if (luckyNumbers.isNotEmpty) {
      writer.writePackedVarint(6, luckyNumbers);
    }
  }

  @override
  void readFrom(ProtoReader reader) {
    while (!reader.isAtEnd) {
      final tag = reader.readTag();
      switch (tag.fieldNumber) {
        case 1:
          name = reader.readString();
        case 2:
          id = reader.readInt32();
        case 3:
          email = reader.readString();
        case 4:
          phones.add(PhoneNumber()..readFrom(reader.readMessageField()));
        case 5:
          address = Address()..readFrom(reader.readMessageField());
        case 6:
          luckyNumbers.addAll(reader.readPackedVarint());
        default:
          reader.skipField(tag.wireType);
      }
    }
  }

  @override
  String toString() => 'Person(name: $name, id: $id, email: $email, '
      'phones: $phones, address: $address, luckyNumbers: $luckyNumbers)';
}

void main() {
  final original = Person(
    name: 'Ada Lovelace',
    id: 1815,
    email: 'ada@example.com',
    phones: [
      PhoneNumber(number: '+1-555-0100', type: PhoneType.mobile),
      PhoneNumber(number: '+1-555-0101', type: PhoneType.work),
    ],
    address: Address(city: 'London', zipCode: 'W1A'),
    luckyNumbers: [7, 42, 1815],
  );

  final bytes = original.toBuffer();
  print('Encoded ${bytes.length} bytes: $bytes');

  final decoded = decode(bytes, Person.new);
  print('Decoded: $decoded');

  assert('$decoded' == '$original');
  print('Round trip OK');
}
