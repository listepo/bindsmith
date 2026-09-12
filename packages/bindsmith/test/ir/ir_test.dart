import 'dart:convert';

import 'package:bindsmith/src/ir/ir.dart';
import 'package:test/test.dart';

const client = TypeDecl(
  id: 'com.example.sdk.Client',
  name: 'Client',
  platform: Platform.android,
  kind: TypeKind.klass,
  loc: SourceLoc('Client.kt', 12),
  docs: 'Talks to the service.',
  availability: Availability(since: '21'),
  supertypes: [TypeRef('Closeable', native: 'java.io.Closeable')],
  typeParams: ['T'],
  members: [
    Member('Client', kind: MemberKind.constructor),
    Member(
      'connect',
      kind: MemberKind.method,
      params: [
        Param('timeout', TypeRef('int', native: 'long')),
        Param(
          'options',
          TypeRef('Options', nullability: Nullability.nullable),
          optional: true,
        ),
      ],
      returns: TypeRef('Session'),
      async: Async.future,
      threading: Threading.main,
      docs: 'Opens a session.',
      markers: [Marker.verify('suspend mapped to Future')],
    ),
    Member(
      'events',
      kind: MemberKind.property,
      returns: TypeRef('Stream', args: [TypeRef('Event')]),
      async: Async.stream,
      isStatic: true,
    ),
  ],
  markers: [Marker.dropped('generic type parameter T erased')],
);

const connect = FunctionDecl(
  id: 'sdk_connect',
  name: 'sdkConnect',
  platform: Platform.linux,
  params: [
    Param('host', TypeRef('Pointer', args: [TypeRef('Utf8')])),
  ],
  returns: TypeRef('int', native: 'int32_t'),
  loc: SourceLoc('sdk.h'),
);

const version = VariableDecl(
  id: 'SDK_VERSION',
  name: 'sdkVersion',
  platform: Platform.web,
  type: TypeRef('String', native: 'string'),
  value: '"2.3.1"',
  isConst: true,
);

String encode(Object? json) => jsonEncode(json);

void main() {
  group('JSON round-trip', () {
    for (final decl in [client, connect, version]) {
      test(decl.id, () {
        final json = decl.toJson();
        final restored = Decl.fromJson(
          jsonDecode(encode(json)) as Map<String, Object?>,
        );
        expect(encode(restored.toJson()), encode(json));
        expect(restored.runtimeType, decl.runtimeType);
      });
    }

    test('list helpers are inverse', () {
      final decls = [client, connect, version];
      final json = jsonDecode(encode(irToJson(decls))) as List<Object?>;
      expect(encode(irToJson(irFromJson(json))), encode(irToJson(decls)));
    });

    test('Param.docs round-trips', () {
      const param = Param(
        'timeout',
        TypeRef('int', native: 'long'),
        docs: 'How long to wait.',
      );
      final json = param.toJson();
      expect(json['docs'], 'How long to wait.');
      expect(Param.fromJson(json).docs, param.docs);
    });

    test('defaults are omitted from JSON', () {
      final json = version.toJson();
      expect(json.keys, [
        'decl',
        'id',
        'name',
        'platform',
        'type',
        'value',
        'isConst',
      ]);
      final member = client.members.first.toJson();
      expect(member, {'name': 'Client', 'kind': 'constructor'});
    });

    test('unknown decl kind is a FormatException', () {
      expect(
        () => Decl.fromJson({'decl': 'macro'}),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('copyWith', () {
    test('keeps identity and untouched fields', () {
      final renamed = client.copyWith(name: 'SdkClient');
      expect(renamed.id, client.id);
      expect(renamed.name, 'SdkClient');
      expect(renamed.kind, TypeKind.klass);
      expect(renamed.members, same(client.members));
      expect(renamed.availability, same(client.availability));
      expect(client.name, 'Client', reason: 'original is untouched');
    });

    test('member copyWith preserves kind and static-ness', () {
      final events = client.members.last.copyWith(name: 'eventStream');
      expect(events.kind, MemberKind.property);
      expect(events.isStatic, isTrue);
      expect(events.async, Async.stream);
    });

    test('renaming keeps the binding identifier for the facade', () {
      final member = client.members.last;
      expect(member.binding, isNull, reason: 'same as name until renamed');
      final renamed = member.copyWith(name: 'eventStream');
      expect(renamed.binding, member.name);
      // A second rename still points at the original binding symbol.
      expect(renamed.copyWith(name: 'events').binding, member.name);
      // Copying without a rename adds nothing.
      expect(member.copyWith(docs: 'x').binding, isNull);
      expect(client.copyWith(name: 'SdkClient').binding, client.name);
      expect(connect.copyWith(name: 'open').binding, connect.name);
      expect(connect.copyWith(name: connect.name).binding, isNull);
    });

    test('isDropped reflects markers', () {
      expect(client.isDropped, isTrue);
      expect(connect.isDropped, isFalse);
      expect(client.members[1].isDropped, isFalse);
    });
  });
}
