/// Scans C header text for documentation ffigen 22 cannot attach: `#define`
/// constants and same-name `typedef struct Name Name;` opaque handles.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../ir/ir.dart';

final _lineBreak = RegExp(r'\r\n|\r|\n');

/// Returns the comment directly above [declaration], or a trailing comment on
/// the matched line. [declaration] is matched against the full [source].
String? commentAbove(String source, RegExp declaration) {
  final match =
      declaration.matchAsPrefix(source) ?? declaration.firstMatch(source);
  if (match == null) return null;

  final before = source.substring(0, match.start);
  final lineStart = before.lastIndexOf('\n') + 1;
  final lineEnd = source.indexOf('\n', match.start);
  final declLine = source.substring(
    lineStart,
    lineEnd == -1 ? source.length : lineEnd,
  );
  final lines = source.split(_lineBreak);
  final declLineIndex = before.split(_lineBreak).length - 1;

  final above = _commentLinesAbove(lines, declLineIndex);
  if (above.isNotEmpty) {
    return removeRawCommentMarkups(above.join('\n'));
  }
  return _trailingComment(declLine, match.end - lineStart);
}

/// Maps C symbol names to documentation found in [source] for `#define NAME` and
/// `typedef struct|union NAME NAME;`.
Map<String, String> headerDocs(String source) {
  final docs = <String, String>{};
  for (final m in RegExp(
    r'#\s*define\s+(\w+)\b',
    multiLine: true,
  ).allMatches(source)) {
    final name = m.group(1)!;
    final comment = commentAbove(
      source,
      RegExp(r'#\s*define\s+' + name + r'\b'),
    );
    if (comment != null) docs[name] = comment;
  }
  for (final m in RegExp(
    r'typedef\s+(?:struct|union)\s+(\w+)\s+\1\s*;',
    multiLine: true,
  ).allMatches(source)) {
    final name = m.group(1)!;
    final comment = commentAbove(
      source,
      RegExp(r'typedef\s+(?:struct|union)\s+' + name + r'\s+' + name + r'\s*;'),
    );
    if (comment != null) docs[name] = comment;
  }
  return docs;
}

/// Quoted `#include "…"` paths relative to [fromDir], normalized POSIX-style.
List<String> quotedIncludes(String source, String fromDir) => [
  for (final m in RegExp(
    r'#\s*include\s+"([^"]+)"',
    multiLine: true,
  ).allMatches(source))
    p.normalize(p.join(fromDir, m.group(1)!)),
];

/// If [usr] is `c:<file>@<offset>@macro@<name>`, returns the file name and
/// byte offset clang recorded for the macro definition.
(String file, int offset)? macroLocationFromUsr(String usr) {
  final m = RegExp(r'^c:([^@]+)@(\d+)@macro@').firstMatch(usr);
  if (m == null) return null;
  return (m.group(1)!, int.parse(m.group(2)!));
}

/// Reads [entryHeaders] under [workingDirectory] and every quoted include
/// transitively, returning merged [headerDocs].
Map<String, String> headerDocsFromTree({
  required List<String> entryHeaders,
  required String workingDirectory,
}) {
  final merged = <String, String>{};
  final seen = <String>{};
  final queue = [
    for (final h in entryHeaders) p.canonicalize(p.join(workingDirectory, h)),
  ];
  while (queue.isNotEmpty) {
    final path = queue.removeLast();
    if (!seen.add(path)) continue;
    final file = File(path);
    if (!file.existsSync()) continue;
    final source = file.readAsStringSync();
    merged.addAll(headerDocs(source));
    queue.addAll(quotedIncludes(source, p.dirname(path)));
  }
  return merged;
}

/// Fills [docs] only where a declaration already has none.
List<Decl> mergeHeaderDocs(List<Decl> decls, Map<String, String> docs) {
  Decl merge(Decl d) {
    final text = docs[d.id];
    if (d.docs != null || text == null) return d;
    // copyWith(docs:) is declared on Decl, so no per-subtype case is needed.
    return d.copyWith(docs: text);
  }

  return [for (final d in decls) merge(d)];
}

/// Strips `///`, `//`, `/** */` and `/* */` the way ffigen 22 does.
String? removeRawCommentMarkups(String? string) {
  if (string == null || string.isEmpty) return null;
  final sb = StringBuffer();
  if (RegExp(r'^\s*/\*+').hasMatch(string)) {
    string = string.replaceFirst(RegExp(r'^\s*/\*+\s*'), '');
    string = string.replaceFirst(RegExp(r'\s*\*+/$'), '');
    for (final element in string.split(_lineBreak)) {
      sb.writeln(element.replaceFirst(RegExp(r'^\s*\**\s*'), ''));
    }
  } else if (RegExp(r'^\s*//?/?\s*').hasMatch(string)) {
    for (final element in string.split(_lineBreak)) {
      sb.writeln(element.replaceFirst(RegExp(r'^\s*//?/?\s*'), ''));
    }
  }
  final trimmed = sb.toString().trim();
  return trimmed.isEmpty ? null : trimmed;
}

List<String> _commentLinesAbove(List<String> lines, int declLineIndex) {
  final collected = <String>[];
  for (var i = declLineIndex - 1; i >= 0; i--) {
    final line = lines[i];
    if (line.trim().isEmpty) break;
    if (_isCommentLine(line)) {
      collected.insert(0, line);
    } else {
      break;
    }
  }
  return collected;
}

bool _isCommentLine(String line) {
  final trimmed = line.trimLeft();
  return trimmed.startsWith('///') ||
      trimmed.startsWith('//') ||
      trimmed.startsWith('/*') ||
      trimmed.startsWith('*') ||
      trimmed.startsWith('*/');
}

String? _trailingComment(String declLine, int declEndInLine) {
  final tail = declLine.substring(declEndInLine);
  final slash = tail.indexOf('//');
  if (slash >= 0) {
    return removeRawCommentMarkups(tail.substring(slash));
  }
  final block = RegExp(r'/\*.*?\*/').firstMatch(tail);
  if (block != null) {
    return removeRawCommentMarkups(block.group(0));
  }
  return null;
}
