/// The fixups DSL: declarative edits applied to IR after the drivers run.
///
/// Mirrors the `fixups:` list in `bindsmith.yaml`:
///
/// ```yaml
/// fixups:
///   - match: { platform: android, symbol: "com.example.Client#connect$2" }
///     rename: connectWithTimeout
///   - match: { symbol: "Client.*Legacy*" }
///     hide: true
///   - match: { platform: ios, symbol: Client.onEvent }
///     threading: main
///   - match: { symbol: Client.fetch }
///     nullability: { returns: nonnull }
///   - match: { symbol: Client.connect }
///     ack: true      # acknowledge verify markers
/// ```
library;

import '../ir/ir.dart';
import 'passes.dart';

final class Fixup {
  const Fixup({
    required this.match,
    this.platform,
    this.rename,
    this.hide = false,
    this.threading,
    this.returns,
    this.ack = false,
  });

  final SymbolPattern match;

  /// Restrict to one platform; `null` applies everywhere.
  final Platform? platform;
  final String? rename;

  /// Mark as dropped (kept in the IR for `dump`, never emitted).
  final bool hide;
  final Threading? threading;

  /// Override the nullability of the return type.
  final Nullability? returns;

  /// Remove verify markers: a human has reviewed this symbol.
  final bool ack;

  bool appliesTo(Platform p) => platform == null || platform == p;
}

Pass fixupsPass(List<Fixup> fixups) =>
    (decls) => [for (final decl in decls) _applyAll(decl, fixups)];

Decl _applyAll(Decl decl, List<Fixup> fixups) {
  var current = decl;
  for (final fixup in fixups) {
    if (!fixup.appliesTo(current.platform)) continue;
    if (fixup.match.matchesDecl(current)) {
      current = _applyToDecl(current, fixup);
    } else if (current is TypeDecl && fixup.match.touches(current)) {
      current = current.copyWith(
        members: [
          for (final m in current.members)
            fixup.match.matchesMember(current, m)
                ? _applyToMember(m, fixup)
                : m,
        ],
      );
    }
  }
  return current;
}

Decl _applyToDecl(Decl decl, Fixup fixup) {
  final markers = _editMarkers(decl.markers, fixup);
  final name = fixup.rename ?? decl.name;
  return switch (decl) {
    TypeDecl() => decl.copyWith(
      name: name,
      markers: markers,
      members: fixup.threading == null
          ? decl.members
          : [
              for (final m in decl.members)
                m.copyWith(threading: fixup.threading),
            ],
    ),
    FunctionDecl() => decl.copyWith(
      name: name,
      markers: markers,
      returns: fixup.returns == null
          ? decl.returns
          : decl.returns.copyWith(nullability: fixup.returns),
    ),
    VariableDecl() => decl.copyWith(name: name, markers: markers),
  };
}

Member _applyToMember(Member m, Fixup fixup) => m.copyWith(
  name: fixup.rename ?? m.name,
  threading: fixup.threading ?? m.threading,
  returns: fixup.returns == null
      ? m.returns
      : m.returns.copyWith(nullability: fixup.returns),
  markers: _editMarkers(m.markers, fixup),
);

List<Marker> _editMarkers(List<Marker> markers, Fixup fixup) => [
  for (final m in markers)
    if (!(fixup.ack && m.kind == MarkerKind.verify)) m,
  if (fixup.hide) Marker.dropped('hidden by fixup ${fixup.match}'),
];
