import 'package:bindsmith/bindsmith.dart';
import 'package:test/test.dart';

void main() {
  test('merge keeps a user line outside the generated region', () {
    const user = '// keep me\n';
    const body = 'import Foundation\nclass X {}\n';
    final first = mergeEditableRegion(body: body);
    final second = mergeEditableRegion(
      body: 'import Foundation\nclass Y {}\n',
      existing: first.replaceFirst(beginGenerated, '$user$beginGenerated'),
    );
    expect(second, contains(user));
    expect(second, contains('class Y'));
    expect(second, isNot(contains('class X')));
  });

  test('wrapGenerated adds begin and end markers', () {
    final out = wrapGenerated('line\n');
    expect(out, contains(beginGenerated));
    expect(out, contains(endGenerated));
  });
}
