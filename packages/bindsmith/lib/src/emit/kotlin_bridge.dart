/// Kotlin bridge emitter: re-declares the Kotlin shapes jnigen can only bind
/// unusably, in a facade class it binds plainly.
///
/// jnigen already carries a lot of Kotlin across — nullability and `suspend`
/// both come out of the class metadata — but three shapes reach Dart as
/// something no Dart program can call:
///
/// | Kotlin | what jnigen binds | what the bridge adds |
/// |---|---|---|
/// | default argument | the full arity, plus a synthetic `greet$default(…, int mask, Object)` | an overload without the optional arguments |
/// | `Flow<T>` | an opaque object with no members | `collect` into a listener, plus a handle that cancels |
/// | `sealed class` | the base class only | `kind`, and a checked `as…` per subclass |
///
/// ```kotlin
/// class KtGreeterBridge(val wrapped: KtGreeter) {
///   fun greet(name: String): String = wrapped.greet(name = name)
///
///   interface GreetAllSink {
///     fun onValue(value: String)
///     fun onError(error: Throwable)
///     fun onDone()
///   }
///
///   fun greetAll(names: List<String>, sink: GreetAllSink): AutoCloseable { … }
/// }
/// ```
///
/// The file is compiled into the same module as the Kotlin it wraps and fed
/// back through [JvmDriver] with the bridge classes added to `classes` and the
/// compiler's output directory added to `classPath`. Nothing here is
/// speculative: a type with none of the three shapes gets no bridge at all.
/// Comments are KDoc for whoever reviews the Kotlin; none of it reaches Dart,
/// because jnigen summarizes compiled classes and KDoc is not compiled.
///
/// What cannot be re-declared — a type variable, a wildcard, a Java type with
/// no Kotlin spelling — is written out as a comment naming the reason, so
/// `bindsmith verify` still reports it.
///
/// @docImport '../drivers/jvm/jvm_driver.dart';
library;

import '../ir/ir.dart';
import 'editable_regions.dart';

/// The generated Kotlin source and the binary names of the classes it
/// declares, which the driver needs as `JvmDriver.classes`.
typedef KotlinBridge = ({String source, Set<String> classes});

/// Emits a bridge for every type in [ir] that has a shape jnigen cannot carry.
///
/// [package] is the Kotlin package the bridge is declared in, which must be
/// the one the wrapped classes live in: the bridge reads no private state, but
/// sharing the package keeps the generated names short. [preamble] goes below
/// bindsmith's own header, and [suffix] names the generated classes
/// (`KtGreeter` → `KtGreeterBridge`).
KotlinBridge emitKotlinBridge(
  List<Decl> ir, {
  required String package,
  String preamble = '',
  String suffix = 'Bridge',
}) => _Bridge(ir, package, suffix).run(preamble);

/// Kotlin's synthetic carrier for a default argument: `greet(name, volume)`
/// also gets `greet$default(receiver, name, volume, int mask, Object marker)`.
const _defaultSuffix = r'$default';

const _flow = 'kotlinx.coroutines.flow.Flow';

final class _Bridge {
  _Bridge(this.ir, this.package, this.suffix) {
    for (final d in ir.whereType<TypeDecl>()) {
      types[d.name] = d;
    }
    for (final d in ir.whereType<TypeDecl>()) {
      for (final s in d.supertypes) {
        if (types.containsKey(s.name)) {
          subtypes.putIfAbsent(s.name, () => []).add(d);
        }
      }
    }
  }

  final List<Decl> ir;
  final String package;
  final String suffix;

  final types = <String, TypeDecl>{};

  /// Base type name → the types in the IR that list it as a supertype.
  final subtypes = <String, List<TypeDecl>>{};

  final refused = <String>[];

  /// Whether any bridged member collects a `Flow`, which is the only reason
  /// the file needs the coroutine imports.
  var coroutines = false;

  KotlinBridge run(String preamble) {
    final classes = <String>{};
    final bodies = <String>[];
    for (final decl in ir.whereType<TypeDecl>()) {
      final body = _type(decl);
      if (body == null) continue;
      classes.add('$package.${_bridgeName(decl)}');
      bodies.add(body);
    }

    final out = StringBuffer()
      ..writeln('package $package')
      ..write(preamble)
      ..writeln();
    if (coroutines) {
      out
        ..writeln('import kotlinx.coroutines.CoroutineScope')
        ..writeln('import kotlinx.coroutines.Dispatchers')
        ..writeln('import kotlinx.coroutines.cancel')
        ..writeln('import kotlinx.coroutines.flow.collect')
        ..writeln('import kotlinx.coroutines.launch')
        ..writeln();
    }
    out.write(bodies.join('\n'));
    if (refused.isNotEmpty) {
      out
        ..writeln()
        ..writeln('// Not bridged, and still reported by `bindsmith verify`:');
      for (final line in refused) {
        out.writeln('//   $line');
      }
    }
    return (source: wrapGenerated(out.toString()), classes: classes);
  }

  /// `Greeter$Listener` is a legal Dart and JVM name but not a Kotlin one.
  String _bridgeName(TypeDecl decl) =>
      '${decl.name.replaceAll(r'$', '_')}$suffix';

  /// The class body for [decl], or `null` when it needs no bridge.
  String? _type(TypeDecl decl) {
    if (decl.isDropped || decl.kind == TypeKind.enumeration) return null;
    if (decl.typeParams.isNotEmpty) {
      // A bridge would have to name the type arguments, and JNI erases them.
      if (_problems(decl)) {
        refused.add(
          '${decl.name}: generic over <${decl.typeParams.join(', ')}>, which '
          'JNI erases',
        );
      }
      return null;
    }

    final sinks = <String>[];
    final collects = <String>[];
    final overloads = <String>[];
    final defaulted = {
      for (final m in decl.members)
        if (m.name.endsWith(_defaultSuffix))
          m.name.substring(0, m.name.length - _defaultSuffix.length),
    };

    for (final m in decl.members) {
      if (m.kind != MemberKind.method || m.name.endsWith(_defaultSuffix)) {
        continue;
      }
      if (_element(m.returns) case final element?) {
        if (_collect(decl, m, element) case final piece?) {
          sinks.add(piece.sink);
          collects.add(piece.method);
        }
        continue;
      }
      if (defaulted.contains(m.name)) {
        if (_overload(decl, m) case final piece?) overloads.add(piece);
      }
    }

    final narrowings = _narrowings(decl);
    if (sinks.isEmpty && overloads.isEmpty && narrowings.isEmpty) return null;

    final out = StringBuffer()
      ..write(
        _doc(0, [
          'The parts of `${decl.name}` that JNI cannot reach on its own: '
              '${[if (collects.isNotEmpty) 'a `Flow` has no JNI surface', if (overloads.isNotEmpty) 'a default argument never crosses', if (narrowings.isNotEmpty) 'a sealed subclass is invisible'].join('; ')}.',
        ]),
      )
      ..writeln('class ${_bridgeName(decl)}(val wrapped: ${_self(decl)}) {');
    if (sinks.isNotEmpty) {
      out
        ..writeln('  private val scope = CoroutineScope(Dispatchers.Default)')
        ..writeln()
        ..write(_doc(2, ['Cancels every collection this bridge started.']))
        ..writeln('  fun close() = scope.cancel()')
        ..writeln();
    }
    out.write([...sinks, ...collects, ...overloads, ...narrowings].join('\n'));
    return (out..writeln('}')).toString();
  }

  /// Whether [decl] has any shape a bridge would exist for. Only used to
  /// explain a refusal.
  bool _problems(TypeDecl decl) =>
      subtypes.containsKey(decl.name) ||
      decl.members.any(
        (m) => m.name.endsWith(_defaultSuffix) || _element(m.returns) != null,
      );

  /// The element type of a `Flow<T>` return, or `null` for anything else.
  String? _element(TypeRef returns) {
    final native = returns.native;
    if (native == null || !native.startsWith('$_flow<')) return null;
    return native.substring(_flow.length + 1, native.length - 1);
  }

  /// An overload of [m] without its optional arguments.
  ///
  /// Which arguments are optional is not in the bytecode, and jnigen's Kotlin
  /// metadata does not carry it either, so [Param.optional] is honoured when a
  /// pass has set it and the last argument is assumed optional otherwise —
  /// Kotlin's own rule that a non-trailing default can only be skipped with a
  /// named argument makes trailing defaults the shape that actually occurs.
  /// Named arguments in the forwarding call keep the assumption honest: when
  /// it is wrong, the generated file does not compile.
  String? _overload(TypeDecl decl, Member m) {
    final optional = m.params.where((q) => q.optional).toSet();
    final keep = optional.isEmpty
        ? m.params.take(m.params.length - 1).toList()
        : [
            for (final q in m.params)
              if (!optional.contains(q)) q,
          ];
    if (keep.length == m.params.length) return null;
    final returns = _returns(decl, m);
    if (returns == null) return null;
    final params = _params(decl, m, keep);
    if (params == null) return null;
    final dropped = [
      for (final q in m.params)
        if (!keep.contains(q)) '`${q.name}`',
    ];

    return '${_doc(2, [..._kotlinDocParagraphs(m), '`${decl.name}.${m.name}` without ${dropped.join(', ')}.', 'Kotlin compiles a default argument to a synthetic '
            '`${m.name}$_defaultSuffix` taking a bitmask, so Dart only ever '
            'sees the full arity. Annotate the Kotlin declaration with '
            '`@JvmOverloads` to bind it directly instead.'])}'
        '  fun ${m.name}(${params.join(', ')})$returns =\n'
        '    wrapped.${m.name}('
        '${[for (final q in keep) '${q.name} = ${q.name}'].join(', ')})\n';
  }

  /// A listener interface, plus the method that collects a `Flow` into it.
  ({String sink, String method})? _collect(
    TypeDecl decl,
    Member m,
    String element,
  ) {
    final value = _kotlin(element);
    if (value == null) {
      refused.add(
        '${decl.name}.${m.name}: `Flow<$element>` has no Kotlin spelling here',
      );
      return null;
    }
    final params = _params(decl, m, m.params);
    if (params == null) return null;
    coroutines = true;

    final sink = '${_upper(m.name)}Sink';
    final args = [for (final q in m.params) '${q.name} = ${q.name}'].join(', ');
    return (
      sink:
          '${_doc(2, ['Receives what `${decl.name}.${m.name}` emits.', 'Implement it from Dart with `$sink.implement`.'])}'
          '  interface $sink {\n'
          '    fun onValue(value: $value)\n\n'
          '    fun onError(error: Throwable)\n\n'
          '    fun onDone()\n'
          '  }\n',
      method:
          '${_doc(2, [..._kotlinDocParagraphs(m), 'Collects `${decl.name}.${m.name}` into [sink] until it ends, '
              'fails, or the returned handle is closed.', 'A `Flow` is an object with no JNI surface, so this listener pair '
              'is what the facade turns back into a `Stream`.'])}'
          '  fun ${m.name}(${[...params, 'sink: $sink'].join(', ')}): '
          'AutoCloseable {\n'
          '    val job = scope.launch {\n'
          '      try {\n'
          '        wrapped.${m.name}($args).collect { sink.onValue(it) }\n'
          '        sink.onDone()\n'
          '      } catch (error: Throwable) {\n'
          '        sink.onError(error)\n'
          '      }\n'
          '    }\n'
          '    return AutoCloseable { job.cancel() }\n'
          '  }\n',
    );
  }

  /// `kind`, plus one checked cast per subclass of a sealed base.
  List<String> _narrowings(TypeDecl decl) {
    final subs = subtypes[decl.name] ?? const <TypeDecl>[];
    if (subs.isEmpty) return const [];
    return [
      '${_doc(2, ['The simple name of the subclass this value actually is: one of '
              '${subs.map((s) => '`${_simpleName(s)}`').join(', ')}.'])}'
          '  val kind: String\n'
          '    get() = wrapped.javaClass.simpleName\n',
      for (final sub in subs)
        '${_doc(2, ['The value as `${_simpleName(sub)}`, or `null` when it is not one.', 'JNI can only reinterpret a reference; this cast is checked.'])}'
            '  fun as${_upper(_simpleName(sub))}(): ${_self(sub)}? =\n'
            '    wrapped as? ${_self(sub)}\n',
    ];
  }

  /// The Kotlin spelling of a declaration in this IR.
  String _self(TypeDecl decl) {
    final id = decl.id.replaceAll(r'$', '.');
    return id.startsWith('$package.') ? id.substring(package.length + 1) : id;
  }

  String _simpleName(TypeDecl decl) => decl.id.split(RegExp(r'[.$]')).last;

  String? _returns(TypeDecl decl, Member m) {
    if (m.returns.native == 'void') return '';
    final type = _typeOf(m.returns);
    if (type == null) {
      refused.add(
        '${decl.name}.${m.name}: `${m.returns.native ?? m.returns.name}` has '
        'no Kotlin spelling here',
      );
      return null;
    }
    return ': $type';
  }

  List<String>? _params(TypeDecl decl, Member m, List<Param> params) {
    final out = <String>[];
    for (final q in params) {
      final type = _typeOf(q.type);
      if (type == null) {
        refused.add(
          '${decl.name}.${m.name}: `${q.type.native ?? q.type.name}` has no '
          'Kotlin spelling here',
        );
        return null;
      }
      out.add('${q.name}: $type');
    }
    return out;
  }

  String? _typeOf(TypeRef ref) {
    final kotlin = _kotlin(ref.native ?? '');
    if (kotlin == null) return null;
    return ref.nullability == Nullability.nullable ? '$kotlin?' : kotlin;
  }

  /// A Java type as Kotlin spells it, or `null` when there is no spelling: a
  /// type variable and a wildcard both name something only erasure knows.
  String? _kotlin(String java) {
    final trimmed = java.trim();
    final open = trimmed.indexOf('<');
    if (open < 0) return _plain(trimmed);
    final base = _plain(trimmed.substring(0, open));
    if (base == null) return null;
    final args = <String>[];
    for (final a in _split(trimmed.substring(open + 1, trimmed.length - 1))) {
      final arg = _kotlin(a);
      if (arg == null) return null;
      args.add(arg);
    }
    return '$base<${args.join(', ')}>';
  }

  String? _plain(String java) {
    if (_kotlinNames[java] case final name?) return name;
    if (java.endsWith('[]')) {
      final element = _plain(java.substring(0, java.length - 2));
      return element == null
          ? null
          : _primitiveArrays[element] ?? 'Array<$element>';
    }
    // A wildcard (`? super T`) and a type variable (`T`) are both unwritable:
    // neither names a class.
    if (!java.contains('.')) return null;
    // Kotlin metadata spells Kotlin's own types: `kotlin.String`,
    // `kotlin.collections.List`. Both packages are imported by default.
    for (final prefix in const ['kotlin.collections.', 'kotlin.']) {
      if (java.startsWith(prefix) &&
          !java.substring(prefix.length).contains('.')) {
        return java.substring(prefix.length);
      }
    }
    final dotted = java.replaceAll(r'$', '.');
    return dotted.startsWith('$package.')
        ? dotted.substring(package.length + 1)
        : dotted;
  }

  /// Splits a type-argument list on commas outside `<…>`.
  List<String> _split(String args) {
    final out = <String>[];
    var depth = 0;
    var start = 0;
    for (var i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '<':
          depth++;
        case '>':
          depth--;
        case ',' when depth == 0:
          out.add(args.substring(start, i));
          start = i + 1;
      }
    }
    final last = args.substring(start).trim();
    if (last.isNotEmpty) out.add(last);
    return out;
  }
}

/// A KDoc block indented by [indent] spaces, wrapped to 80 columns for
/// whoever reviews the committed file. It stops there: KDoc is not compiled
/// into the class, so jnigen has none to carry on to Dart.
List<String> _kotlinDocParagraphs(Member m) => [
  ...?m.docs?.split('\n'),
  for (final q in m.params)
    if (q.docs != null) '@param ${q.name} ${q.docs}',
];

String _doc(int indent, List<String> paragraphs) {
  final pad = ' ' * indent;
  final kept = [
    for (final p in paragraphs)
      for (final line in p.split('\n'))
        if (line.trim().isNotEmpty) line.trim(),
  ];
  if (kept.isEmpty) return '';
  final out = StringBuffer('$pad/**\n');
  for (final (i, paragraph) in kept.indexed) {
    if (i > 0) out.writeln('$pad *');
    for (final line in _wrap(paragraph, 80 - indent - 3)) {
      out.writeln('$pad * $line');
    }
  }
  return (out..writeln('$pad */')).toString();
}

/// Greedy word wrap. A single word longer than [width] stays on its own line
/// rather than being broken, because it is a type or an identifier.
List<String> _wrap(String text, int width) {
  final lines = <String>[];
  final line = StringBuffer();
  for (final word in text.split(' ')) {
    if (line.isNotEmpty && line.length + 1 + word.length > width) {
      lines.add(line.toString());
      line.clear();
    }
    line.write(line.isEmpty ? word : ' $word');
  }
  if (line.isNotEmpty) lines.add(line.toString());
  return lines;
}

String _upper(String name) =>
    name.isEmpty ? name : name[0].toUpperCase() + name.substring(1);

const _kotlinNames = {
  'void': 'Unit',
  'boolean': 'Boolean',
  'byte': 'Byte',
  'char': 'Char',
  'short': 'Short',
  'int': 'Int',
  'long': 'Long',
  'float': 'Float',
  'double': 'Double',
  'java.lang.Object': 'Any',
  'java.lang.String': 'String',
  'java.lang.CharSequence': 'CharSequence',
  'java.lang.Number': 'Number',
  'java.lang.Throwable': 'Throwable',
  'java.lang.Iterable': 'Iterable',
  'java.util.Collection': 'Collection',
  'java.util.List': 'List',
  'java.util.Map': 'Map',
  'java.util.Set': 'Set',
};

const _primitiveArrays = {
  'Boolean': 'BooleanArray',
  'Byte': 'ByteArray',
  'Char': 'CharArray',
  'Short': 'ShortArray',
  'Int': 'IntArray',
  'Long': 'LongArray',
  'Float': 'FloatArray',
  'Double': 'DoubleArray',
};
