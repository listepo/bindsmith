/// Marks GLib symbols ffigen cannot bind faithfully: GObject cast macros and
/// `g_object_new` varargs.
library;

import '../ir/ir.dart';
import 'passes.dart';

final _gObjectCast = RegExp(
  r'^G_(?:OBJECT|TYPE_CHECK_INSTANCE(?:_CAST|_TYPE)?|TYPE_INSTANCE_'
  r'(?:CAST|GET_CLASS)|TYPE_CHECK_VALUE(?:_TYPE)?|PARAM_SPEC)$',
);

/// Adds [Marker.verify] on GObject cast macros and `g_object_new` varargs.
Pass glibMacroPass() =>
    (decls) => [
      for (final d in decls)
        switch (d) {
          FunctionDecl() when _needsGlibMarker(d) => d.copyWith(
            markers: [...d.markers, Marker.verify(_glibReason(d))],
          ),
          _ => d,
        },
    ];

bool _needsGlibMarker(FunctionDecl d) {
  final names = {d.id, d.name, if (d.native != null) d.native!};
  if (names.any(_isGObjectNew)) return true;
  return names.any((n) => _gObjectCast.hasMatch(n));
}

bool _isGObjectNew(String name) =>
    name == 'g_object_new' ||
    name == 'g_object_new_valist' ||
    name.startsWith('g_object_new_with');

String _glibReason(FunctionDecl d) {
  final names = {d.id, d.name, if (d.native != null) d.native!};
  if (names.any(_isGObjectNew)) {
    return 'g_object_new is variadic: ffigen binds only fixed arguments; '
        'call a typed constructor wrapper instead';
  }
  return 'GObject cast macro: not callable from Dart; cast the pointer '
      'yourself or use a wrapper function';
}
