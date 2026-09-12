// The process boundary: the real streams, the real exit code. Everything the
// command line does lives in `lib/src/cli/runner.dart`, so tests drive it
// in-process without spawning a Dart VM per case.
import 'dart:io';

import 'package:bindsmith/bindsmith.dart';

Future<void> main(List<String> args) async {
  exitCode = await runBindsmith(args, out: stdout, err: stderr);
}
