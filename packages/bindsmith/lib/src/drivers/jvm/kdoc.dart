/// KDoc reader: a lexer over Kotlin source that maps qualified names to
/// documentation. jnigen summarizes compiled classes, which carry no comments.
library;

import '../../ir/ir.dart';

/// Documentation extracted from one KDoc block.
final class KDoc {
  const KDoc({
    this.memberDocs,
    this.paramDocs = const {},
    this.propertyDocs = const {},
    this.constructorDocs,
    this.availability,
  });

  final String? memberDocs;
  final Map<String, String> paramDocs;
  final Map<String, String> propertyDocs;
  final String? constructorDocs;
  final Availability? availability;
}

/// Reads every `/** … */` in [source] and keys it for IR lookup.
///
/// Keys:
/// - a type: `<package>.<Class>` (`$` between nested classes, as on the JVM);
/// - a function: `<package>.<Class>.<member>(<param names>)`;
/// - a property: `<package>.<Class>.<property>`.
///
/// Top-level declarations in `Foo.kt` use `FooKt` unless `@file:JvmName` names
/// the file facade differently. [fileName] defaults to `File.kt`.
Map<String, KDoc> kdocs(String source, {String fileName = 'File.kt'}) =>
    _Scanner(source, fileName).scan();

/// Splits a KDoc body into member prose, parameter docs, and availability.
KDoc splitKDoc(
  String raw, {
  Set<String> paramNames = const {},
  Set<String> propertyNames = const {},
}) {
  final text = _stripGutter(raw);
  if (text.isEmpty) {
    return const KDoc();
  }

  final paramDocs = <String, String>{};
  final propertyDocs = <String, String>{};
  String? constructorDocs;
  String? since;
  String? deprecated;
  final kept = <String>[];

  final tag = RegExp(r'^@(\w+)(?:\s+(.*))?$');
  for (final line in text.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      kept.add('');
      continue;
    }
    final m = tag.matchAsPrefix(trimmed);
    if (m == null) {
      kept.add(trimmed);
      continue;
    }
    final name = m.group(1)!;
    final body = (m.group(2) ?? '').trim();
    switch (name) {
      case 'param':
        final space = body.indexOf(RegExp(r'\s'));
        if (space < 0) {
          kept.add(trimmed);
          break;
        }
        final param = body.substring(0, space).trim();
        final docs = body.substring(space).trim();
        if (paramNames.contains(param)) {
          paramDocs[param] = docs;
        } else {
          kept.add('`$param`: $docs');
        }
      case 'property':
        final space = body.indexOf(RegExp(r'\s'));
        if (space < 0) {
          kept.add(trimmed);
          break;
        }
        final prop = body.substring(0, space).trim();
        final docs = body.substring(space).trim();
        if (propertyNames.contains(prop)) {
          propertyDocs[prop] = docs;
        } else {
          kept.add('@property $body');
        }
      case 'constructor':
        constructorDocs = [
          if (constructorDocs != null) constructorDocs!,
          body,
        ].join('\n');
      case 'return' || 'returns':
        kept.add(body.isEmpty ? 'Returns.' : 'Returns $body');
      case 'throws' || 'exception':
        kept.add(body.isEmpty ? 'Throws.' : 'Throws $body');
      case 'since':
        since = body;
      case 'deprecated':
        deprecated = body.isEmpty ? 'deprecated' : body;
      case 'suppress':
        break;
      default:
        kept.add(body.isEmpty ? '@$name' : '@$name $body');
    }
  }

  final member = kept.join('\n').trim();
  final availability = since == null && deprecated == null
      ? null
      : Availability(since: since, deprecated: deprecated);

  return KDoc(
    memberDocs: member.isEmpty ? null : member,
    paramDocs: paramDocs,
    propertyDocs: propertyDocs,
    constructorDocs: constructorDocs?.trim().isEmpty ?? true
        ? null
        : constructorDocs!.trim(),
    availability: availability,
  );
}

String _stripGutter(String raw) {
  var text = raw.trim();
  if (text.startsWith('/**')) text = text.substring(3);
  if (text.endsWith('*/')) text = text.substring(0, text.length - 2);
  return [
    for (final line in text.split('\n'))
      line.replaceFirst(RegExp(r'^\s*\*\s?'), '').trimRight(),
  ].join('\n').trim();
}

final class _Scanner {
  _Scanner(this.source, this.fileName);

  final String source;
  final String fileName;
  final out = <String, KDoc>{};

  var i = 0;
  String? packageName;
  String? fileJvmName;
  final classStack = <String>[];
  var companionDepth = -1;
  String? pendingClass;
  var bodyDepth = 0;

  Map<String, KDoc> scan() {
    while (i < source.length) {
      _skipSpace();
      if (i >= source.length) break;

      if (_at('package ')) {
        packageName = _readPackage();
        continue;
      }
      if (_at('@file:')) {
        _readFileAnnotation();
        continue;
      }

      if (_at('/**')) {
        final raw = _readKDocBlock();
        if (raw != null) _attach(raw);
        continue;
      }

      if (_startsCommentOrString()) {
        _skipToken();
        continue;
      }

      if (_handleBrace()) continue;
      if (_trackStructure()) continue;
      i++;
    }
    return out;
  }

  void _attach(String raw) {
    _skipSpace();
    final annotations = _consumeAnnotations();
    final suppressed = annotations.any((a) => a.startsWith('@Suppress'));

    final decl = _readDecl(annotations: annotations);
    if (decl == null || suppressed) return;

    switch (decl.kind) {
      case _DeclKind.type:
        pendingClass = decl.name;
        final key = _typeKey(decl.name);
        final split = splitKDoc(
          raw,
          propertyNames: decl.primaryProperties.toSet(),
        );
        out[key] = KDoc(
          memberDocs: split.memberDocs,
          availability: split.availability,
        );
        for (final MapEntry(key: name, value: docs)
            in split.propertyDocs.entries) {
          out['$key.$name'] = KDoc(memberDocs: docs);
        }
        if (split.constructorDocs != null || split.paramDocs.isNotEmpty) {
          out['$key.<init>(${decl.primaryParams.join(',')})'] = KDoc(
            memberDocs: split.constructorDocs,
            paramDocs: split.paramDocs,
            availability: split.availability,
          );
        }
      case _DeclKind.function:
        out[_memberKey(decl.name, decl.params, onOuter: decl.onOuter)] =
            splitKDoc(raw, paramNames: decl.params.toSet());
      case _DeclKind.property:
        out['${_owner(onOuter: decl.onOuter)}.${decl.name}'] = splitKDoc(raw);
      case _DeclKind.companion:
        pendingClass = 'Companion';
    }
    if (decl.kind == _DeclKind.type || decl.kind == _DeclKind.companion) {
      _skipSpace();
      if (i < source.length && source[i] == '{') {
        _openBrace();
      }
    }
  }

  bool _handleBrace() {
    if (source[i] == '{') {
      _openBrace();
      return true;
    }
    if (source[i] == '}') {
      if (bodyDepth > 0) {
        bodyDepth--;
      } else if (classStack.isNotEmpty) {
        if (classStack.length - 1 == companionDepth) companionDepth = -1;
        classStack.removeLast();
      }
      i++;
      return true;
    }
    return false;
  }

  void _openBrace() {
    if (pendingClass != null) {
      classStack.add(pendingClass!);
      if (pendingClass == 'Companion') {
        companionDepth = classStack.length - 1;
      }
      pendingClass = null;
    } else {
      bodyDepth++;
    }
    i++;
  }

  bool _trackStructure() {
    if (_at('class ') ||
        _at('interface ') ||
        _at('object ') ||
        _at('enum class ')) {
      pendingClass = _readTypeKeywordAndName();
      _readUntil('{');
      return true;
    }
    if (_at('companion object')) {
      i += 'companion object'.length;
      pendingClass = 'Companion';
      _readUntil('{');
      return true;
    }
    return false;
  }

  _Decl? _readDecl({List<String> annotations = const []}) {
    _skipSpace();
    final modifiers = _consumeModifiers();
    if (_at('class ') ||
        _at('interface ') ||
        _at('object ') ||
        _at('enum class ')) {
      final name = _readTypeKeywordAndName();
      final primary = _readPrimaryCtor();
      return _Decl(
        kind: _DeclKind.type,
        name: name,
        primaryParams: primary.params,
        primaryProperties: primary.properties,
      );
    }
    if (_at('companion object')) {
      i += 'companion object'.length;
      return const _Decl(kind: _DeclKind.companion, name: 'Companion');
    }
    if (_at('fun interface ')) {
      i += 'fun interface '.length;
      return _Decl(kind: _DeclKind.type, name: _readIdent());
    }
    if (modifiers.contains('fun') || _at('fun ')) {
      if (_at('fun ')) i += 'fun '.length;
      final name = _readIdent();
      final params = _readParamList();
      return _Decl(
        kind: _DeclKind.function,
        name: name,
        params: params,
        onOuter: _onOuter(modifiers, annotations),
      );
    }
    if (_at('val ') || _at('var ') || modifiers.contains('const')) {
      if (_at('const ')) i += 'const '.length;
      if (_at('val ') || _at('var ')) i += 4;
      final name = _readIdent();
      return _Decl(
        kind: _DeclKind.property,
        name: name,
        onOuter: _onOuter(modifiers, annotations),
      );
    }
    if (_at('constructor')) {
      i += 'constructor'.length;
      final params = _readParamList();
      return _Decl(kind: _DeclKind.function, name: '<init>', params: params);
    }
    return null;
  }

  bool _onOuter(Set<String> modifiers, List<String> annotations) =>
      companionDepth >= 0 &&
      (modifiers.contains('const') ||
          annotations.any((a) => a.startsWith('@JvmStatic')));

  String _typeKey(String name) {
    final parts = [...classStack, name];
    return '${packageName ?? ''}.${parts.join(r'$')}';
  }

  String _memberKey(String name, List<String> params, {required bool onOuter}) {
    final owner = _owner(onOuter: onOuter);
    return '$owner.$name(${params.join(',')})';
  }

  String _owner({required bool onOuter}) {
    if (classStack.isEmpty) {
      final facade = fileJvmName ?? _fileFacadeName();
      return '${packageName ?? ''}.$facade';
    }
    if (onOuter && companionDepth >= 0) {
      final outer = classStack.sublist(0, companionDepth);
      return '${packageName ?? ''}.${outer.join(r'$')}';
    }
    return '${packageName ?? ''}.${classStack.join(r'$')}';
  }

  String _fileFacadeName() {
    final base = fileName.endsWith('.kt')
        ? fileName.substring(0, fileName.length - 3)
        : fileName;
    return '${base}Kt';
  }

  String _readPackage() {
    i += 'package '.length;
    final start = i;
    while (i < source.length) {
      final c = source[i];
      if (_isIdentChar(c) || c == '.') {
        i++;
      } else {
        break;
      }
    }
    return source.substring(start, i);
  }

  void _readFileAnnotation() {
    final start = i;
    while (i < source.length && source[i] != '\n') {
      i++;
    }
    final line = source.substring(start, i);
    final m = RegExp(r'@file:JvmName\s*\(\s*"([^"]+)"\s*\)').firstMatch(line);
    if (m != null) fileJvmName = m.group(1);
  }

  List<String> _consumeAnnotations() {
    final anns = <String>[];
    while (_at('@')) {
      anns.add(_readAnnotation());
    }
    return anns;
  }

  String _readAnnotation() {
    final start = i;
    i++;
    while (i < source.length && _isIdentChar(source[i])) {
      i++;
    }
    if (_at('(')) {
      i++;
      var depth = 1;
      while (i < source.length && depth > 0) {
        if (source[i] == '(') depth++;
        if (source[i] == ')') depth--;
        i++;
      }
    }
    return source.substring(start, i);
  }

  Set<String> _consumeModifiers() {
    const mods = {
      'public',
      'private',
      'protected',
      'internal',
      'expect',
      'actual',
      'final',
      'open',
      'abstract',
      'sealed',
      'annotation',
      'data',
      'inner',
      'value',
      'external',
      'override',
      'infix',
      'operator',
      'inline',
      'noinline',
      'crossinline',
      'const',
      'lateinit',
      'vararg',
      'suspend',
      'tailrec',
    };
    const declStarts = {
      'fun',
      'val',
      'var',
      'class',
      'interface',
      'object',
      'enum',
      'constructor',
      'companion',
    };
    final found = <String>{};
    while (true) {
      _skipSpace();
      final word = _peekWord();
      if (declStarts.contains(word) || !mods.contains(word)) break;
      found.add(word);
      i += word.length;
    }
    return found;
  }

  String _readTypeKeywordAndName() {
    if (_at('enum class ')) {
      i += 'enum class '.length;
    } else if (_at('class ')) {
      i += 'class '.length;
    } else if (_at('interface ')) {
      i += 'interface '.length;
    } else {
      i += 'object '.length;
    }
    return _readIdent();
  }

  ({List<String> params, List<String> properties}) _readPrimaryCtor() {
    _skipSpace();
    if (!_at('(')) return (params: const [], properties: const []);
    return _readParenContents(collectProperties: true);
  }

  List<String> _readParamList() {
    _skipSpace();
    if (!_at('(')) return const [];
    return _readParenContents().params;
  }

  ({List<String> params, List<String> properties}) _readParenContents({
    bool collectProperties = false,
  }) {
    i++;
    final params = <String>[];
    final properties = <String>[];
    var depth = 1;
    while (i < source.length && depth > 0) {
      if (source[i] == '(') depth++;
      if (source[i] == ')') {
        depth--;
        if (depth == 0) {
          i++;
          break;
        }
      }
      if (_startsCommentOrString()) {
        _skipToken();
        continue;
      }
      if (_at('/**')) {
        _readKDocBlock();
        continue;
      }
      _skipSpace();
      final mods = _consumeModifiers();
      if (mods.contains('vararg') && _peekWord() == 'vararg') {
        i += 'vararg'.length;
      }
      _skipSpace();
      if (_at('val ') || _at('var ')) {
        i += 4;
        final name = _readIdent();
        params.add(name);
        if (collectProperties) properties.add(name);
      } else {
        final name = _readIdent();
        if (name.isNotEmpty) params.add(name);
      }
      _skipToNextParam();
    }
    return (params: params, properties: properties);
  }

  void _skipToNextParam() {
    var depth = 0;
    while (i < source.length) {
      if (_startsCommentOrString()) {
        _skipToken();
        continue;
      }
      final c = source[i];
      if (c == '(') depth++;
      if (c == ')') {
        if (depth == 0) return;
        depth--;
      }
      if (c == ',' && depth == 0) {
        i++;
        return;
      }
      i++;
    }
  }

  void _readUntil(String ch) {
    while (i < source.length) {
      if (_startsCommentOrString()) {
        _skipToken();
        continue;
      }
      if (source[i] == ch) return;
      i++;
    }
  }

  String _readIdent() {
    _skipSpace();
    final start = i;
    while (i < source.length && _isIdentChar(source[i])) {
      i++;
    }
    return source.substring(start, i);
  }

  String _peekWord() {
    _skipSpace();
    final start = i;
    while (i < source.length && _isIdentChar(source[i])) {
      i++;
    }
    final word = source.substring(start, i);
    i = start;
    return word;
  }

  String? _readKDocBlock() {
    if (!_at('/**')) return null;
    i += 3;
    final buf = StringBuffer();
    var depth = 1;
    while (i < source.length && depth > 0) {
      if (_at('/*')) {
        depth++;
        buf.write('/*');
        i += 2;
        continue;
      }
      if (_at('*/')) {
        depth--;
        if (depth > 0) buf.write('*/');
        i += 2;
        continue;
      }
      buf.write(source[i]);
      i++;
    }
    return buf.toString();
  }

  bool _startsCommentOrString() =>
      _at('//') || _at('/*') || _at('"""') || _at('"') || _at("'");

  void _skipToken() {
    if (_at('//')) {
      i += 2;
      while (i < source.length && source[i] != '\n') {
        i++;
      }
      return;
    }
    if (_at('/*')) {
      _readBlockComment();
      return;
    }
    if (_at('"""')) {
      i += 3;
      while (i < source.length) {
        if (_at('"""')) {
          i += 3;
          return;
        }
        i++;
      }
      return;
    }
    if (_at('"')) {
      i++;
      while (i < source.length) {
        if (source[i] == '\\') {
          i += 2;
          continue;
        }
        if (source[i] == '"') {
          i++;
          return;
        }
        if (source[i] == r'$' &&
            i + 1 < source.length &&
            source[i + 1] == '{') {
          _skipTemplate();
          continue;
        }
        i++;
      }
      return;
    }
    if (_at("'")) {
      i++;
      while (i < source.length) {
        if (source[i] == '\\') {
          i += 2;
          continue;
        }
        if (source[i] == "'") {
          i++;
          return;
        }
        i++;
      }
    }
  }

  void _readBlockComment() {
    i += 2;
    var depth = 1;
    while (i < source.length && depth > 0) {
      if (_at('/*')) {
        depth++;
        i += 2;
        continue;
      }
      if (_at('*/')) {
        depth--;
        i += 2;
        continue;
      }
      i++;
    }
  }

  void _skipTemplate() {
    i += 2;
    var depth = 1;
    while (i < source.length && depth > 0) {
      if (_startsCommentOrString()) {
        _skipToken();
        continue;
      }
      if (source[i] == '{') depth++;
      if (source[i] == '}') depth--;
      i++;
    }
  }

  void _skipSpace() {
    while (i < source.length && source[i].trim().isEmpty) {
      i++;
    }
  }

  bool _at(String s) => source.startsWith(s, i);

  bool _isIdentChar(String c) {
    final code = c.codeUnitAt(0);
    return c == '_' ||
        (code >= 0x30 && code <= 0x39) ||
        (code >= 0x41 && code <= 0x5a) ||
        (code >= 0x61 && code <= 0x7a);
  }
}

enum _DeclKind { type, function, property, companion }

final class _Decl {
  const _Decl({
    required this.kind,
    required this.name,
    this.params = const [],
    this.primaryParams = const [],
    this.primaryProperties = const [],
    this.onOuter = false,
  });

  final _DeclKind kind;
  final String name;
  final List<String> params;
  final List<String> primaryParams;
  final List<String> primaryProperties;
  final bool onOuter;
}
