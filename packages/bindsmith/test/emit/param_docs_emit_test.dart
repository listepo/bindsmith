import 'package:bindsmith/src/emit/facade.dart';
import 'package:bindsmith/src/emit/js_interop.dart';
import 'package:bindsmith/src/emit/kotlin_bridge.dart';
import 'package:bindsmith/src/emit/swift_bridge.dart';
import 'package:bindsmith/src/ir/ir.dart';
import 'package:test/test.dart';

const _method = Member(
  'greet',
  kind: MemberKind.method,
  params: [Param('name', TypeRef('String'), docs: 'The person to greet.')],
  returns: TypeRef('String'),
  docs: 'Greets someone.',
);

const _type = TypeDecl(
  id: 'Greeter',
  name: 'Greeter',
  platform: Platform.web,
  kind: TypeKind.jsObject,
  members: [_method],
);

void main() {
  test('facade lists parameter docs', () {
    final files = emitFacade(
      {
        Platform.android: [
          const TypeDecl(
            id: 'Greeter',
            name: 'Greeter',
            platform: Platform.android,
            kind: TypeKind.klass,
            members: [_method],
          ),
        ],
      },
      const FacadeOptions(
        library: 'greeter',
        bindings: {Platform.android: 'greeter.g.dart'},
      ),
    );
    expect(
      files.values.join('\n'),
      contains('/// - [name]: The person to greet.'),
    );
  });

  test('js_interop lists parameter docs', () {
    expect(
      emitJsInterop([_type]),
      contains('/// - [name]: The person to greet.'),
    );
  });

  test('kotlin_bridge writes @param', () {
    final out = emitKotlinBridge([
      TypeDecl(
        id: 'com.example.Greeter',
        name: 'Greeter',
        platform: Platform.android,
        kind: TypeKind.klass,
        members: [
          Member(
            'greet',
            kind: MemberKind.method,
            params: [
              Param(
                'name',
                TypeRef('String', native: 'java.lang.String'),
                docs: 'The person to greet.',
              ),
              Param(
                'volume',
                TypeRef('Volume', native: 'com.example.Volume'),
                optional: true,
              ),
            ],
            returns: TypeRef('String', native: 'java.lang.String'),
            docs: 'Greets [name].',
          ),
          Member(
            'greet\$default',
            kind: MemberKind.method,
            params: [
              Param('name', TypeRef('String', native: 'java.lang.String')),
              Param(
                'volume',
                TypeRef('Volume', native: 'com.example.Volume'),
                optional: true,
              ),
              Param('mask', TypeRef('int', native: 'int')),
              Param('marker', TypeRef('JObject', native: 'java.lang.Object')),
            ],
            returns: TypeRef('String', native: 'java.lang.String'),
          ),
        ],
      ),
    ], package: 'com.example').source;
    expect(out, contains('@param name The person to greet.'));
  });

  test('swift_bridge writes Parameter lines', () {
    final bridge = emitSwiftBridge([
      TypeDecl(
        id: 'Greeter',
        name: 'Greeter',
        platform: Platform.ios,
        kind: TypeKind.klass,
        members: [
          Member(
            'greetAll',
            kind: MemberKind.method,
            params: [
              Param(
                'names',
                TypeRef('[String]'),
                named: true,
                docs: 'Everyone to greet.',
              ),
            ],
            returns: TypeRef('[String]'),
            docs: 'Greets everyone.',
            native: 'func greetAll(names: [String]) -> [String]',
            markers: [Marker.dropped('test')],
          ),
        ],
      ),
    ]);
    expect(
      bridge.source,
      contains('/// - Parameter names: Everyone to greet.'),
    );
  });
}
