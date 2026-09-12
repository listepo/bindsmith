import 'package:bindsmith/src/ir/ir.dart';
import 'package:test/test.dart';

// Mirrors bindsmith's diff shape helpers in runner.dart — docs are not shape.
String _params(List<Param> params) => [
  for (final param in params)
    '${param.named ? '{' : ''}${param.type.name} ${param.name}'
        '${param.named ? '}' : ''}',
].join(', ');

String _returns(TypeRef type, Async async) => switch (async) {
  Async.future => 'Future<${type.name}>',
  Async.stream => 'Stream<${type.name}>',
  Async.callback => 'void (callback)',
  Async.none => type.name,
};

String shape(Decl decl) => switch (decl) {
  FunctionDecl() =>
    '${decl.name}(${_params(decl.params)}) -> ${_returns(decl.returns, decl.async)}',
  _ => decl.name,
};

String memberShape(Member member) =>
    '${member.name}(${_params(member.params)}) -> '
    '${_returns(member.returns, member.async)}';

void main() {
  test('Param.docs does not change diff shape', () {
    const bare = FunctionDecl(
      id: 'greet',
      name: 'greet',
      platform: Platform.web,
      params: [Param('delayMs', TypeRef('int'))],
      returns: TypeRef('String'),
    );
    const documented = FunctionDecl(
      id: 'greet',
      name: 'greet',
      platform: Platform.web,
      params: [Param('delayMs', TypeRef('int'), docs: 'How long to wait.')],
      returns: TypeRef('String'),
    );
    expect(shape(bare), shape(documented));

    const method = Member(
      'greet',
      kind: MemberKind.method,
      params: [Param('name', TypeRef('String'))],
      returns: TypeRef('String'),
    );
    const methodDocs = Member(
      'greet',
      kind: MemberKind.method,
      params: [Param('name', TypeRef('String'), docs: 'Who to greet.')],
      returns: TypeRef('String'),
    );
    expect(memberShape(method), memberShape(methodDocs));
  });
}
