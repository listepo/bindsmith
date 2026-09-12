import '../ir/ir.dart';

/// A glob over IR symbols, as written in `include:` lists and `fixups.match`.
///
/// Three spellings are accepted:
///
/// * `Type` or `com.example.Type` — matches a declaration by Dart name or
///   native id.
/// * `Type.member` — matches members of declarations named `Type`.
/// * `native.id#member` — matches members by the declaration's native id.
///
/// `*` matches any run of characters, `?` one character. Everything else is
/// literal, including `$` in jnigen overload suffixes (`connect$2`).
final class SymbolPattern {
  SymbolPattern._(this.source, this._whole, this._type, this._member);

  factory SymbolPattern.parse(String source) {
    if (source.trim().isEmpty) {
      throw const FormatException('symbol pattern must not be empty');
    }
    final hash = source.indexOf('#');
    if (hash >= 0) {
      return SymbolPattern._(
        source,
        null,
        _glob(source.substring(0, hash)),
        _glob(source.substring(hash + 1)),
      );
    }
    final dot = source.lastIndexOf('.');
    return SymbolPattern._(
      source,
      _glob(source),
      dot > 0 ? _glob(source.substring(0, dot)) : null,
      dot > 0 ? _glob(source.substring(dot + 1)) : null,
    );
  }

  final String source;
  final RegExp? _whole;
  final RegExp? _type;
  final RegExp? _member;

  /// Whether this pattern names [decl] as a whole.
  bool matchesDecl(Decl decl) =>
      _whole != null &&
      (_whole.hasMatch(decl.id) || _whole.hasMatch(decl.name));

  /// Whether this pattern names [member] of [decl].
  bool matchesMember(Decl decl, Member member) =>
      _type != null &&
      _member != null &&
      (_type.hasMatch(decl.id) || _type.hasMatch(decl.name)) &&
      _member.hasMatch(member.name);

  /// Whether this pattern can match anything named [name], declaration or
  /// member alike.
  ///
  /// This is what a driver's pull list is built from: at generation time there
  /// is a name and no IR yet, and `Type.member` has to keep `Type` or the
  /// member it names is never generated in the first place.
  bool touchesName(String name) => (_whole ?? _type)?.hasMatch(name) ?? false;

  /// Whether this pattern can match anything inside [decl].
  bool touches(Decl decl) =>
      matchesDecl(decl) ||
      (_type != null && (_type.hasMatch(decl.id) || _type.hasMatch(decl.name)));

  @override
  String toString() => source;

  static RegExp _glob(String glob) {
    final buffer = StringBuffer('^');
    for (final rune in glob.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(switch (char) {
        '*' => '.*',
        '?' => '.',
        _ when RegExp(r'[A-Za-z0-9_]').hasMatch(char) => char,
        _ => '\\$char',
      });
    }
    buffer.write(r'$');
    return RegExp(buffer.toString());
  }
}
