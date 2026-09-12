import 'package:bindsmith/src/emit/facade.dart';
import 'package:bindsmith/src/ir/ir.dart';
import 'package:test/test.dart';

import '../golden.dart';

const _string = TypeRef('String');
const _nullableString = TypeRef('String', nullability: Nullability.nullable);
const _int = TypeRef('int');

/// One SDK seen through three drivers. Android has the widest surface; iOS
/// lacks the async `connect` and `legacy`; web disagrees on `count` and drops
/// `legacy` through an include list.
final _ir = <Platform, List<Decl>>{
  Platform.android: [
    TypeDecl(
      id: 'com.example.sdk.Client',
      name: 'Client',
      platform: Platform.android,
      kind: TypeKind.klass,
      docs: 'Talks to the SDK.',
      members: [
        const Member(
          '',
          kind: MemberKind.constructor,
          params: [Param('name', _string)],
        ),
        const Member(
          'greet',
          kind: MemberKind.method,
          params: [Param('who', _nullableString)],
          returns: _string,
          docs: 'Greets [who].',
        ),
        const Member('connect', kind: MemberKind.method, async: Async.future),
        const Member(
          'count',
          kind: MemberKind.method,
          params: [Param('n', _int)],
          returns: _int,
        ),
        const Member('legacy', kind: MemberKind.method),
        const Member(
          'reset',
          kind: MemberKind.method,
          threading: Threading.main,
        ),
        const Member(
          'version',
          kind: MemberKind.property,
          returns: _string,
          isStatic: true,
        ),
        const Member(
          'other',
          kind: MemberKind.method,
          params: [Param('peer', TypeRef('Client'))],
          returns: TypeRef('Client', nullability: Nullability.nullable),
        ),
      ],
    ),
    const FunctionDecl(
      id: 'createClient',
      name: 'createClient',
      platform: Platform.android,
      params: [Param('name', _string)],
      returns: TypeRef('Client'),
    ),
    const VariableDecl(
      id: 'VERSION',
      name: 'VERSION',
      platform: Platform.android,
      type: _string,
      value: "'2.3.1'",
      isConst: true,
    ),
  ],
  Platform.ios: [
    TypeDecl(
      id: 'SDKClient',
      name: 'Client',
      platform: Platform.ios,
      binding: 'SDKClient',
      kind: TypeKind.klass,
      members: const [
        Member(
          '',
          kind: MemberKind.constructor,
          binding: 'alloc().initWithName_',
          params: [Param('name', _string)],
        ),
        Member(
          'greet',
          kind: MemberKind.method,
          binding: 'greetWithWho_',
          params: [Param('who', _nullableString)],
          returns: _string,
        ),
        Member(
          'count',
          kind: MemberKind.method,
          binding: 'count_',
          params: [Param('n', _int)],
          returns: _int,
        ),
        Member('reset', kind: MemberKind.method),
        Member(
          'version',
          kind: MemberKind.property,
          returns: _string,
          isStatic: true,
        ),
        Member(
          'other',
          kind: MemberKind.method,
          binding: 'other_',
          params: [Param('peer', TypeRef('Client'))],
          returns: TypeRef('Client', nullability: Nullability.nullable),
        ),
      ],
    ),
    const FunctionDecl(
      id: 'SDKCreateClient',
      name: 'createClient',
      platform: Platform.ios,
      binding: 'SDKCreateClient',
      params: [Param('name', _string)],
      returns: TypeRef('Client'),
    ),
    const VariableDecl(
      id: 'SDKVersion',
      name: 'VERSION',
      platform: Platform.ios,
      binding: 'SDKVersion',
      type: _string,
      value: "'2.3.1'",
      isConst: true,
    ),
  ],
  Platform.web: [
    TypeDecl(
      id: 'Client',
      name: 'Client',
      platform: Platform.web,
      kind: TypeKind.jsObject,
      members: const [
        Member(
          '',
          kind: MemberKind.constructor,
          params: [Param('name', _string)],
        ),
        Member(
          'greet',
          kind: MemberKind.method,
          params: [Param('who', _nullableString)],
          returns: _string,
        ),
        Member('connect', kind: MemberKind.method, async: Async.future),
        Member(
          'count',
          kind: MemberKind.method,
          params: [Param('n', TypeRef('double'))],
          returns: TypeRef('double'),
        ),
        Member(
          'legacy',
          kind: MemberKind.method,
          markers: [Marker.dropped('not in include list')],
        ),
        Member('reset', kind: MemberKind.method),
        Member(
          'version',
          kind: MemberKind.property,
          returns: _string,
          isStatic: true,
        ),
        Member(
          'other',
          kind: MemberKind.method,
          params: [Param('peer', TypeRef('Client'))],
          returns: TypeRef('Client', nullability: Nullability.nullable),
        ),
        Member(
          'fetchName',
          kind: MemberKind.method,
          returns: _string,
          async: Async.future,
        ),
      ],
    ),
    const FunctionDecl(
      id: 'createClient',
      name: 'createClient',
      platform: Platform.web,
      params: [Param('name', _string)],
      returns: TypeRef('Client'),
    ),
    const VariableDecl(
      id: 'VERSION',
      name: 'VERSION',
      platform: Platform.web,
      type: _string,
      value: "'2.3.1'",
      isConst: true,
    ),
  ],
};

const _options = FacadeOptions(
  library: 'sdk',
  bindings: {
    Platform.android: 'android.g.dart',
    Platform.ios: 'ios.g.dart',
    Platform.web: 'web.g.dart',
  },
);

void main() {
  final files = emitFacade(_ir, _options);

  test('emits an entry file and one file per platform group', () {
    expect(files.keys, ['sdk.g.dart', 'sdk_io.g.dart', 'sdk_web.g.dart']);
    expect(
      files['sdk.g.dart'],
      contains(
        "export 'sdk_io.g.dart' if (dart.library.js_interop) 'sdk_web.g.dart';",
      ),
    );
  });

  test('goldens', () {
    for (final MapEntry(key: name, value: source) in files.entries) {
      expectGolden('test/emit/goldens/$name', source);
    }
  });

  test('members missing on a platform throw BindsmithUnsupported', () {
    final ioSrc = files['sdk_io.g.dart']!;
    expect(
      ioSrc,
      contains(
        'BindsmithPlatform.android => (_impl as android.Client).connect()',
      ),
    );
    expect(
      ioSrc,
      contains(
        "throw BindsmithUnsupported('Client.connect', bindsmithPlatform)",
      ),
    );
    expect(files['sdk_web.g.dart'], contains('void legacy() {'));
  });

  test('signature mismatch and unmapped shapes become verify annotations', () {
    final webSrc = files['sdk_web.g.dart']!;
    expect(
      webSrc,
      containsCode(
        "@BindsmithVerify('signature differs: (double) -> double on web vs "
        "(int) -> int on android (facade uses android)')",
      ),
    );
    expect(webSrc, contains('// Not emitted by the facade'));
    expect(webSrc, contains('//   web Client.legacy — not in include list'));
  });

  test('marshalling follows the platform binding style', () {
    final ioSrc = files['sdk_io.g.dart']!;
    expect(
      ioSrc,
      containsCode(
        '.greet(who?.toJString()).toDartString(releaseOriginal: true)',
      ),
    );
    expect(
      ioSrc,
      containsCode('.greetWithWho_(_n(who, NSString.new)).toDartString()'),
    );
    expect(
      ioSrc,
      containsCode('ios.SDKClient.alloc().initWithName_(NSString(name))'),
    );
    expect(
      ioSrc,
      containsCode(
        '_n((_impl as android.Client).other((peer._impl as android.Client)), Client._)',
      ),
    );
    expect(ioSrc, contains("import 'package:jni/jni.dart';"));
    expect(ioSrc, contains("import 'package:objective_c/objective_c.dart';"));
    expect(
      files['sdk_web.g.dart'],
      containsCode('fetchName().toDart.then((v) => v.toDart)'),
    );
    expect(files['sdk_web.g.dart'], contains("import 'dart:js_interop';"));
  });

  test('omit policy removes symbols missing anywhere and lists them', () {
    final omitted = emitFacade(
      _ir,
      const FacadeOptions(
        library: 'sdk',
        bindings: {Platform.android: 'a.dart', Platform.ios: 'i.dart'},
        unsupported: Unsupported.omit,
      ),
    )['sdk_io.g.dart']!;
    expect(omitted, isNot(contains('connect(')));
    expect(omitted, contains('//   Client.connect — omitted: missing on ios'));
    expect(omitted, contains('//   Client.legacy — omitted: missing on ios'));
  });

  test('stub policy returns a completed future or does nothing', () {
    final stubbed = emitFacade(
      _ir,
      const FacadeOptions(
        library: 'sdk',
        bindings: {Platform.android: 'a.dart', Platform.ios: 'i.dart'},
        unsupported: Unsupported.stub,
      ),
    )['sdk_io.g.dart']!;
    expect(stubbed, containsCode('_ => Future<void>.value()'));
    expect(stubbed, containsCode('default: return;'));
  });

  test('a name used for different declaration kinds is reported', () {
    final clash = emitFacade({
      Platform.android: const [
        TypeDecl(
          id: 'X',
          name: 'X',
          platform: Platform.android,
          kind: TypeKind.klass,
        ),
      ],
      Platform.web: const [
        FunctionDecl(id: 'X', name: 'X', platform: Platform.web),
      ],
    }, _options);
    expect(clash['sdk_web.g.dart'], isNot(contains('void X()')));
    expect(
      clash['sdk_web.g.dart'],
      contains('declared as a function but X is already a type'),
    );
  });
}
