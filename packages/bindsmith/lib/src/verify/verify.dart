/// `bindsmith verify` (plan P6-5): does the generated code still need a human?
///
/// Every answer is read out of the generated Dart that is committed, not out
/// of a fresh run: `generate --check` is the command that says whether what is
/// on disk is *current*, and this one says whether what is on disk is *done*.
/// So verify needs no libclang, no JDK and no network, which is what lets it
/// be the cheap gate that runs on every push.
///
/// Reading the file rather than the IR is also the only reading that matches
/// how a marker is acknowledged. A `fixups: … ack: true` entry drops the
/// marker before any emitter sees it, and a human may delete the annotation
/// outright; either way what is left in the file is the whole answer.
///
/// Everything here is a pure function of source text, the way a pass is: the
/// command finds the files, this decides what is wrong with them.
library;

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

/// One thing a human still has to look at, with the place to look.
typedef Finding = ({String file, int line, String what});

/// Every `@BindsmithVerify` still in [source], in file order.
///
/// A file that does not parse is one finding rather than an exception: it is
/// exactly the state a generated file is in after a bad hand-edit, which is
/// what verify exists to catch.
List<Finding> findMarkers(String file, String source) {
  final parsed = parseString(
    content: source,
    path: file,
    throwIfDiagnostics: false,
  );
  if (parsed.errors.isNotEmpty) {
    final first = parsed.errors.first;
    return [
      (
        file: file,
        line: parsed.lineInfo.getLocation(first.offset).lineNumber,
        what: 'does not parse: ${first.message}',
      ),
    ];
  }
  final found = <Finding>[];
  parsed.unit.accept(_Markers(file, parsed.lineInfo, found));
  return found;
}

/// The public API [source] declares, as `Client.greet` →
/// `String greet(String? who)`.
///
/// This is what the io and web facade groups have to agree on, and reading the
/// Dart back is the only way to compare them: the two are emitted from
/// different platform sets, so nothing upstream of the emitter holds both
/// shapes at once. A signature is the declaration's own source with the body
/// left off, so a difference reads as the two lines a caller would see. Field
/// and variable initializers are left off with it — a `const` whose value
/// differs per platform is the point of the facade, not a defect.
Map<String, String> publicApi(String source) {
  final unit = parseString(
    content: source,
    path: 'facade.g.dart',
    throwIfDiagnostics: false,
  ).unit;
  final api = <String, String>{};
  for (final declaration in unit.declarations) {
    switch (declaration) {
      case ClassDeclaration(:final namePart, :final body):
        final name = namePart.typeName.lexeme;
        if (_isPrivate(name)) continue;
        api[name] = _upTo(source, declaration, body.offset);
        _members(api, source, name, body.members);
      case EnumDeclaration(:final namePart, :final body):
        final name = namePart.typeName.lexeme;
        if (_isPrivate(name)) continue;
        api[name] = _upTo(source, declaration, body.offset);
        for (final constant in body.constants) {
          api['$name.${constant.name.lexeme}'] = constant.name.lexeme;
        }
        _members(api, source, name, body.members);
      case FunctionDeclaration(:final name, :final functionExpression):
        if (_isPrivate(name.lexeme)) continue;
        api[name.lexeme] = _upTo(
          source,
          declaration,
          functionExpression.body.offset,
        );
      case TopLevelVariableDeclaration(:final variables):
        _variables(api, source, declaration, variables, prefix: '');
      default:
        continue;
    }
  }
  return api;
}

/// What the io and web facade groups disagree about, one line each.
List<String> facadeDrift(Map<String, String> io, Map<String, String> web) => [
  for (final name in ({...io.keys, ...web.keys}.toList()..sort()))
    if (io[name] != web[name])
      switch ((io[name], web[name])) {
        (null, _) => '$name is declared on web only',
        (_, null) => '$name is declared on io only',
        (final a, final b) => '$name is "$a" on io and "$b" on web',
      },
];

/// Lines of generated code, which is what a `size_budget` caps. Windows line
/// endings count the same as Unix ones (rule 8).
int countLines(String source) =>
    '\n'.allMatches(source.replaceAll('\r\n', '\n')).length;

void _members(
  Map<String, String> api,
  String source,
  String type,
  List<ClassMember> members,
) {
  for (final member in members) {
    switch (member) {
      case ConstructorDeclaration(:final name, :final body):
        // An unnamed constructor is `Type.new` to a caller.
        final called = name?.lexeme ?? 'new';
        if (_isPrivate(called)) continue;
        api['$type.$called'] = _upTo(source, member, body.offset);
      case MethodDeclaration(:final name, :final body):
        if (_isPrivate(name.lexeme)) continue;
        api['$type.${name.lexeme}'] = _upTo(source, member, body.offset);
      case FieldDeclaration(:final fields):
        _variables(api, source, member, fields, prefix: '$type.');
      default:
        continue;
    }
  }
}

/// The declaration around a [VariableDeclarationList] is what carries `static`
/// and `external`, so it and not the list is where a signature starts.
void _variables(
  Map<String, String> api,
  String source,
  AnnotatedNode declaration,
  VariableDeclarationList variables, {
  required String prefix,
}) {
  for (final variable in variables.variables) {
    if (_isPrivate(variable.name.lexeme)) continue;
    api['$prefix${variable.name.lexeme}'] = _upTo(
      source,
      declaration,
      variable.name.end,
    );
  }
}

/// [node]'s own source up to [end], without the doc comment and annotations
/// above it — those are prose and markers, not API.
String _upTo(String source, AnnotatedNode node, int end) =>
    source.substring(node.firstTokenAfterCommentAndMetadata.offset, end).trim();

/// A leading underscore is Dart's whole notion of private, so it is this
/// file's too.
bool _isPrivate(String name) => name.startsWith('_');

final class _Markers extends RecursiveAstVisitor<void> {
  _Markers(this._file, this._lines, this._into);

  final String _file;
  final LineInfo _lines;
  final List<Finding> _into;

  @override
  void visitAnnotation(Annotation node) {
    if (node.name.name != 'BindsmithVerify') return;
    final arguments = node.arguments?.arguments;
    final reason = arguments == null || arguments.isEmpty
        ? null
        : arguments.first.argumentExpression;
    _into.add((
      file: _file,
      line: _lines.getLocation(node.offset).lineNumber,
      what: reason is SimpleStringLiteral ? reason.value : node.toSource(),
    ));
  }
}
