import 'package:bindsmith/src/ir/ir.dart';
import 'package:bindsmith/src/passes/fixups.dart';
import 'package:bindsmith/src/passes/passes.dart';
import 'package:test/test.dart';

const client = TypeDecl(
  id: 'com.example.sdk.Client',
  name: 'Client',
  platform: Platform.android,
  kind: TypeKind.klass,
  members: [
    Member(
      r'connect$2',
      kind: MemberKind.method,
      params: [Param('timeout', TypeRef('int'))],
      returns: TypeRef('Session', nullability: Nullability.unknown),
      markers: [Marker.verify('suspend mapped to Future')],
    ),
    Member('fetchLegacy', kind: MemberKind.method),
    Member('onEvent', kind: MemberKind.event),
  ],
);

const helper = FunctionDecl(
  id: 'sdk_helper',
  name: 'sdkHelper',
  platform: Platform.linux,
  params: [Param('p', TypeRef('Pointer', nullability: Nullability.unknown))],
);

const flag = VariableDecl(
  id: 'FLAG',
  name: 'flag',
  platform: Platform.web,
  type: TypeRef('bool'),
);

List<String> dropped(Iterable<Marker> markers) => [
  for (final m in markers)
    if (m.kind == MarkerKind.dropped) m.reason,
];

void main() {
  group('SymbolPattern', () {
    test('whole-symbol match by name or native id', () {
      expect(SymbolPattern.parse('Client').matchesDecl(client), isTrue);
      expect(
        SymbolPattern.parse('com.example.sdk.*').matchesDecl(client),
        isTrue,
      );
      expect(SymbolPattern.parse('Server').matchesDecl(client), isFalse);
    });

    test('member match with dot and hash spellings', () {
      final byDot = SymbolPattern.parse('Client.*Legacy*');
      final byHash = SymbolPattern.parse(r'com.example.sdk.Client#connect$2');
      expect(byDot.matchesDecl(client), isFalse);
      expect(byDot.matchesMember(client, client.members[1]), isTrue);
      expect(byDot.matchesMember(client, client.members[0]), isFalse);
      expect(byHash.matchesMember(client, client.members[0]), isTrue);
      expect(byHash.matchesMember(client, client.members[1]), isFalse);
    });

    test(r'$ and ? are handled', () {
      expect(
        SymbolPattern.parse(r'Client.connect$?')
            .matchesMember(client, client.members[0]),
        isTrue,
      );
      expect(() => SymbolPattern.parse(' '), throwsFormatException);
    });
  });

  group('includePass', () {
    test('drops declarations outside the pull list with a marker', () {
      final out = includePass(['Client'])([client, helper, flag]);
      expect(out, hasLength(3), reason: 'nothing disappears');
      expect(out[0].isDropped, isFalse);
      expect(dropped(out[1].markers), ['not in include list']);
      expect(dropped(out[2].markers), ['not in include list']);
    });

    test('member-level include keeps the type and drops other members', () {
      final out = includePass([r'Client.connect$2'])([client]);
      final type = out.single as TypeDecl;
      expect(type.isDropped, isFalse);
      expect(type.members[0].isDropped, isFalse);
      expect(type.members[1].isDropped, isTrue);
      expect(type.members[2].isDropped, isTrue);
    });
  });

  group('nullabilityPass', () {
    test('unknown becomes nullable plus a verify marker', () {
      final out = nullabilityPass()([client, helper, flag]);
      final connect = (out[0] as TypeDecl).members[0];
      expect(connect.returns.nullability, Nullability.nullable);
      expect(
        connect.markers.last.reason,
        'nullability unknown for return value; treated as nullable',
      );
      final fn = out[1] as FunctionDecl;
      expect(fn.params.single.type.nullability, Nullability.nullable);
      expect(fn.markers.single.reason, contains('for p;'));
      expect(out[2].markers, isEmpty);
    });
  });

  group('fixupsPass', () {
    test('rename, hide, threading, nullability, ack, platform filter', () {
      final pass = fixupsPass([
        Fixup(
          match: SymbolPattern.parse(r'com.example.sdk.Client#connect$2'),
          platform: Platform.android,
          rename: 'connectWithTimeout',
          returns: Nullability.nonNull,
          ack: true,
        ),
        Fixup(match: SymbolPattern.parse('Client.*Legacy*'), hide: true),
        Fixup(
          match: SymbolPattern.parse('Client.onEvent'),
          platform: Platform.ios,
          threading: Threading.main,
        ),
        Fixup(match: SymbolPattern.parse('sdkHelper'), rename: 'helper'),
      ]);
      final out = pass([client, helper]);
      final type = out[0] as TypeDecl;
      final connect = type.members[0];
      expect(connect.name, 'connectWithTimeout');
      expect(connect.returns.nullability, Nullability.nonNull);
      expect(connect.markers, isEmpty, reason: 'ack removed verify marker');
      expect(dropped(type.members[1].markers), [
        'hidden by fixup Client.*Legacy*',
      ]);
      expect(
        type.members[2].threading,
        Threading.any,
        reason: 'ios-only fixup does not touch android',
      );
      expect(out[1].name, 'helper');
      expect(client.members[0].name, r'connect$2', reason: 'input untouched');
    });

    test('decl-level threading applies to every member', () {
      final out = fixupsPass([
        Fixup(match: SymbolPattern.parse('Client'), threading: Threading.main),
      ])([client]);
      final type = out.single as TypeDecl;
      expect(
        type.members.map((m) => m.threading),
        everyElement(Threading.main),
      );
    });
  });

  test('runPasses composes in order', () {
    final out = runPasses(
      [client, helper],
      [
        includePass(['Client']),
        fixupsPass([
          Fixup(match: SymbolPattern.parse('Client'), rename: 'SdkClient'),
        ]),
      ],
    );
    expect(out[0].name, 'SdkClient');
    expect(out[1].isDropped, isTrue);
  });
}
