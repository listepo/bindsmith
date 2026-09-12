/// Swift bridge emitter: turns the `dropped` markers a Swift driver produced
/// back into Swift that Objective-C, and therefore Dart, can see.
///
/// swift2objc writes an `@objc` wrapper for the Swift API, but only for the
/// declarations it understands. What it leaves behind arrives in the IR as a
/// member carrying a `dropped` marker, with the Swift spelling of its
/// parameters and result. This emitter re-exposes those members on a hand-off
/// class:
///
/// ```swift
/// @objc public final class GreeterBridge: NSObject {
///   public var wrapped: Greeter
///   @objc public init(_ wrapper: GreeterWrapper) {
///     wrapped = wrapper.wrappedInstance
///   }
///   @objc public func greetAll(names: NSArray) -> NSArray {
///     return wrapped.greetAll(names: names as! [String]) as NSArray
///   }
/// }
/// ```
///
/// The file is compiled into the same module as the sources and the generated
/// wrapper, and is fed back through the Swift driver as an
/// `objcCompatibleSources` entry, which binds it as written. Taking the
/// wrapper rather than the Swift type in the initializer is what lets Dart
/// build one: `wrappedInstance` is internal to the generated wrapper, and the
/// bridge is in the same module.
///
/// Three conversions carry a signature across, all of them read off the IR:
///
/// * a collection casts to its `NS` counterpart (`[String]` ↔ `NSArray`);
/// * a Swift type that swift2objc *did* wrap travels as that wrapper
///   (`Volume` ↔ `VolumeWrapper`), which is how the wrapper itself passes it;
/// * an `async` result becomes a completion handler.
///
/// Anything left — a generic, a tuple, a Swift-only type with no wrapper of
/// its own — is written out as a comment naming the reason and keeps its
/// `dropped` marker in the IR, so `bindsmith verify` still reports it.
library;

import '../ir/ir.dart';
import 'editable_regions.dart';

/// The generated Swift source and the `@objc` classes it declares, which the
/// driver needs as `SwiftDriver.objcCompatibleTypes`.
typedef SwiftBridge = ({String source, Set<String> classes});

/// Emits a bridge for every type in [ir] that has dropped members.
///
/// [preamble] goes below bindsmith's own header line. [suffix] names the
/// generated classes (`Greeter` → `GreeterBridge`), and [wrapperSuffix] is how
/// swift2objc named its own wrapper for the same type.
SwiftBridge emitSwiftBridge(
  List<Decl> ir, {
  String preamble = '',
  String suffix = 'Bridge',
  String wrapperSuffix = 'Wrapper',
}) => _Bridge(ir, suffix, wrapperSuffix).run(preamble);

final class _Bridge {
  _Bridge(this.ir, this.suffix, this.wrapperSuffix) {
    for (final d in ir) {
      if (d.name.endsWith(wrapperSuffix)) {
        wrapped.add(d.name.substring(0, d.name.length - wrapperSuffix.length));
      } else if (d is TypeDecl &&
          (d.kind == TypeKind.struct || d.kind == TypeKind.enumeration)) {
        swiftOnly.add(d.name);
      }
    }
    swiftOnly.removeAll(wrapped);
  }

  final List<Decl> ir;
  final String suffix;
  final String wrapperSuffix;

  /// Swift types swift2objc already carries across, by their Swift name.
  final wrapped = <String>{};

  /// Swift types the IR knows about that have no Objective-C form at all.
  final swiftOnly = <String>{};

  final refused = <String>[];

  SwiftBridge run(String preamble) {
    final out = StringBuffer()
      ..write(preamble)
      ..writeln('import Foundation');
    final classes = <String>{};

    for (final decl in ir) {
      if (decl is! TypeDecl) {
        if (decl.isDropped) refused.add('${decl.name}: not a member of a type');
        continue;
      }
      final dropped = [
        for (final m in decl.members)
          if (m.isDropped && m.kind != MemberKind.setter) m,
      ];
      if (dropped.isEmpty) continue;
      if (decl.typeParams.isNotEmpty) {
        refused.add(
          '${decl.name}: generic over <${decl.typeParams.join(', ')}>, which '
          'Objective-C cannot represent at all',
        );
        continue;
      }
      final wrapper = '${decl.name}$wrapperSuffix';
      final klass = '${decl.name}$suffix';
      classes.add(klass);
      out
        ..writeln()
        ..writeln('/// The members of `${decl.name}` that swift2objc left out')
        ..writeln('/// of `$wrapper`, re-exposed for Objective-C.')
        ..writeln('@objc public final class $klass: NSObject {')
        ..writeln('  public var wrapped: ${decl.name}')
        ..writeln();
      if (wrapped.contains(decl.name)) {
        out
          ..writeln('  @objc public init(_ wrapper: $wrapper) {')
          ..writeln('    wrapped = wrapper.wrappedInstance')
          ..writeln('  }')
          ..writeln();
      } else {
        out
          ..writeln('  // `$wrapper` is not in the binding, so Dart cannot')
          ..writeln('  // reach this bridge; expose `${decl.name}` first.')
          ..writeln('  public init(_ wrapped: ${decl.name}) {')
          ..writeln('    self.wrapped = wrapped')
          ..writeln('  }')
          ..writeln();
      }
      // Each member already ends in a newline, so joining leaves exactly one
      // blank line between them and none before the brace.
      out
        ..write(
          [
            for (final member in dropped)
              _member(
                decl,
                member,
                decl.members
                    .where(
                      (m) =>
                          m.kind == MemberKind.setter && m.name == member.name,
                    )
                    .firstOrNull,
              ),
          ].join('\n'),
        )
        ..writeln('}');
    }

    if (refused.isNotEmpty) {
      out.writeln();
      out.writeln('// Not bridged, and still reported by `bindsmith verify`:');
      for (final line in refused) {
        out.writeln('//   $line');
      }
    }
    return (source: wrapGenerated(out.toString()), classes: classes);
  }

  String _member(TypeDecl owner, Member member, Member? setter) {
    final receiver = member.isStatic ? owner.name : 'wrapped';
    final why = _refuse(member);
    if (why != null) {
      return '  // Not bridged: ${member.native ?? member.name} — $why\n';
    }
    final docs = [
      for (final line in (member.docs ?? '').split('\n'))
        if (line.trim().isNotEmpty) '  /// ${line.trim()}\n',
      for (final q in member.params)
        if (q.docs != null) '  /// - Parameter ${q.name}: ${q.docs}\n',
      if (member.native != null) '  /// `${member.native}`\n',
    ].join();
    final modifiers = 'public ${member.isStatic ? 'static ' : ''}';

    if (member.kind == MemberKind.property) {
      final body = StringBuffer()
        ..write(docs)
        ..writeln(
          '  @objc ${modifiers}var ${member.name}: '
          '${_objc(member.returns.name)} {',
        )
        ..writeln(
          '    get { ${_out('$receiver.${member.name}', member.returns)} }',
        );
      if (setter != null) {
        final value = _in('newValue', setter.params.single.type);
        body.writeln('    set { $receiver.${member.name} = $value }');
      }
      return (body..writeln('  }')).toString();
    }

    final args = [
      for (final q in member.params)
        '${q.named ? '' : '_ '}${q.name}: ${_objc(q.type.name)}',
    ];
    final call =
        '$receiver.${member.name}(${[for (final q in member.params) '${q.named ? '${q.name}: ' : ''}${_in(q.name, q.type)}'].join(', ')})';
    final isVoid = member.returns.name == 'Void';

    final body = StringBuffer()..write(docs);
    if (member.async != Async.none) {
      // Objective-C has no `await`, so the result arrives on a block. The
      // facade turns that back into a `Future` (P6-4).
      final handler = isVoid ? '()' : '(${_objc(member.returns.name)})';
      body
        ..writeln(
          '  @objc ${modifiers}func ${member.name}('
          '${[...args, 'completion: @escaping $handler -> Void'].join(', ')}) {',
        )
        ..writeln('    Task {')
        ..writeln(
          isVoid
              ? '      await $call\n      completion()'
              : '      completion(${_out('await $call', member.returns)})',
        )
        ..writeln('    }')
        ..writeln('  }');
      return body.toString();
    }

    final result = _out(call, member.returns);
    body
      ..writeln(
        '  @objc ${modifiers}func ${member.name}(${args.join(', ')})'
        '${isVoid ? '' : ' -> ${_objc(member.returns.name)}'} {',
      )
      ..writeln('    ${isVoid ? result : 'return $result'}')
      ..writeln('  }');
    return body.toString();
  }

  /// Why this member cannot be re-exposed, or `null` when it can.
  String? _refuse(Member member) {
    if (member.kind == MemberKind.constructor) {
      return 'an initializer has to be written by hand; the bridge takes the '
          'wrapper';
    }
    if (member.async == Async.stream) {
      return 'a stream needs a subscription object, not a completion handler';
    }
    for (final type in [
      member.returns,
      for (final q in member.params) q.type,
    ]) {
      if (!_representable(type.name)) {
        return '`${type.name}` is not representable in Objective-C';
      }
    }
    return null;
  }

  /// A Swift type as an `@objc` signature spells it.
  String _objc(String swift) {
    final (base, question) = _optional(swift);
    final objc = switch (base) {
      _ when wrapped.contains(base) => '$base$wrapperSuffix',
      _ when base.startsWith('[') && base.contains(':') => 'NSDictionary',
      _ when base.startsWith('[') => 'NSArray',
      _ when base.startsWith('Set<') => 'NSSet',
      _ => base,
    };
    return '$objc$question';
  }

  /// Objective-C value → the Swift type the call site needs.
  String _in(String expression, TypeRef type) {
    final (base, question) = _optional(type.name);
    if (wrapped.contains(base)) return '$expression$question.wrappedInstance';
    if (_objc(base) == base) return expression;
    return '$expression as$question! $base';
  }

  /// Swift value → what the `@objc` signature promised.
  String _out(String expression, TypeRef type) {
    final (base, _) = _optional(type.name);
    if (wrapped.contains(base)) {
      return '$base$wrapperSuffix($expression)';
    }
    return _objc(base) == base
        ? expression
        : '$expression as ${_objc(type.name)}';
  }

  /// Whether Objective-C can see this type once [_objc] has mapped it.
  bool _representable(String swift) {
    final (base, _) = _optional(swift);
    if (base.startsWith('(') || base.contains('->')) return false;
    if (wrapped.contains(base)) return true;
    if (swiftOnly.contains(base)) return false;
    if (base.startsWith('[') || base.startsWith('Set<')) return true;
    // `Box<T>` and a bare type parameter are the two shapes that never cross.
    return !base.contains('<') &&
        !(base.length <= 2 && base == base.toUpperCase());
  }
}

(String, String) _optional(String swift) => swift.endsWith('?')
    ? (swift.substring(0, swift.length - 1), '?')
    : (swift, '');
