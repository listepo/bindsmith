/// The jnigen toolchain lock has to exclude another isolate, not only
/// another process: `dart test` runs files as isolates of one process, and
/// [FileLock] does not.
library;

import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'jvm_toolchain.dart';

void main() {
  late Directory dir;
  late File lock;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('bindsmith_jnigen_lock_');
    lock = File(p.join(dir.path, 'lock'));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('two isolates cannot hold the lock at once', () async {
    final ready = ReceivePort();
    final released = ReceivePort();
    final errors = ReceivePort();
    final isolate = await Isolate.spawn(_hold, (
      lock.path,
      ready.sendPort,
      released.sendPort,
    ), onError: errors.sendPort);
    addTearDown(() {
      isolate.kill();
      ready.close();
      released.close();
      errors.close();
    });
    errors.listen((Object? error) => fail('$error'));
    expect(await ready.first, 'held');
    final watch = Stopwatch()..start();
    await withJniToolchainLock(() async {}, lock: lock);
    expect(watch.elapsed, greaterThan(const Duration(milliseconds: 300)));
    expect(await released.first, 'released');
  });

  test('a lock left by a dead process is taken over', () async {
    // `dart -e` is gone; a one-line script is the process that then exits.
    final script = File(p.join(dir.path, 'exit.dart'))
      ..writeAsStringSync('void main() {}\n');
    final probe = await Process.start(Platform.resolvedExecutable, [
      script.path,
    ]);
    final dead = probe.pid;
    expect(await probe.exitCode, 0);
    lock.writeAsStringSync(
      '$dead ${DateTime.now().toUtc().toIso8601String()} dead-token\n',
    );
    var ran = false;
    await withJniToolchainLock(() async {
      ran = true;
    }, lock: lock);
    expect(ran, isTrue);
    expect(lock.existsSync(), isFalse);
  });

  test('a lock older than twenty minutes is taken over', () async {
    final stamped = DateTime.now().toUtc().subtract(
      const Duration(minutes: 21),
    );
    lock.writeAsStringSync('$pid ${stamped.toIso8601String()} old-token\n');
    var ran = false;
    await withJniToolchainLock(() async {
      ran = true;
    }, lock: lock);
    expect(ran, isTrue);
    expect(lock.existsSync(), isFalse);
  });

  test('an empty lock past the settle window is taken over', () async {
    lock.createSync();
    lock.setLastModifiedSync(
      DateTime.now().subtract(const Duration(seconds: 5)),
    );
    var ran = false;
    await withJniToolchainLock(() async {
      ran = true;
    }, lock: lock);
    expect(ran, isTrue);
    expect(lock.existsSync(), isFalse);
  });
}

Future<void> _hold((String, SendPort, SendPort) message) async {
  final (path, ready, released) = message;
  await withJniToolchainLock(() async {
    ready.send('held');
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }, lock: File(path));
  released.send('released');
}
