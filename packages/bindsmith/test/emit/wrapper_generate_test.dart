import 'package:bindsmith/bindsmith.dart';
import 'package:test/test.dart';

void main() {
  test('wrapper: off does not emit a Swift bridge body', () {
    final bridge = emitSwiftBridge(const []);
    expect(bridge.classes, isEmpty);
  });

  test('auto emits a Swift bridge with editable markers', () {
    final bridge = emitSwiftBridge([
      TypeDecl(
        id: 'w',
        name: 'GreeterWrapper',
        platform: Platform.ios,
        kind: TypeKind.klass,
      ),
      TypeDecl(
        id: 'g',
        name: 'Greeter',
        platform: Platform.ios,
        kind: TypeKind.klass,
        members: [
          Member(
            'greetAll',
            kind: MemberKind.method,
            params: [Param('names', TypeRef('NSArray'))],
            returns: TypeRef('NSArray'),
            markers: [Marker.dropped('swift2objc left it out')],
          ),
        ],
      ),
    ]);
    expect(bridge.source, contains(beginGenerated));
    expect(bridge.source, contains(endGenerated));
    expect(bridge.source, contains('GreeterBridge'));
  });
}
