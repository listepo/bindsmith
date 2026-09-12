/// Editable regions in generated wrapper files (P7-4).
///
/// Generated bridges are committed and may carry hand-written lines outside the
/// `// bindsmith:begin generated` … `// bindsmith:end generated` block. On
/// regenerate, only the region between those markers is replaced.
library;

import '../drivers/c/ffigen_adapter.dart' show bindsmithHeader;

/// Opens the generated region bindsmith owns on regenerate.
const beginGenerated = '// bindsmith:begin generated';

/// Closes the generated region bindsmith owns on regenerate.
const endGenerated = '// bindsmith:end generated';

/// Writes [body] as a new file with the standard header and editable markers.
String wrapGenerated(String body, {String header = bindsmithHeader}) =>
    '$header$beginGenerated\n$body$endGenerated\n';

/// Merges [body] into [existing], keeping every line outside the markers.
///
/// When [existing] is null, empty, or has no markers, returns a fresh file.
String mergeEditableRegion({
  required String body,
  String? existing,
  String header = bindsmithHeader,
}) {
  final block = '$beginGenerated\n$body$endGenerated';
  if (existing == null || existing.isEmpty) return '$header$block\n';
  final begin = existing.indexOf(beginGenerated);
  final end = existing.indexOf(endGenerated);
  if (begin < 0 || end < begin) return '$header$block\n';
  final before = existing.substring(0, begin);
  final after = existing.substring(end + endGenerated.length);
  final prefix = before.startsWith(header) ? before : '$header$before';
  return '$prefix$block$after';
}

/// Strips [bindsmithHeader] and the editable markers from a wrapper file.
String unwrapGenerated(String source, {String header = bindsmithHeader}) {
  final text = source.startsWith(header)
      ? source.substring(header.length)
      : source;
  final begin = text.indexOf(beginGenerated);
  final end = text.indexOf(endGenerated);
  if (begin < 0 || end < begin) return text;
  return text.substring(begin + beginGenerated.length + 1, end);
}
