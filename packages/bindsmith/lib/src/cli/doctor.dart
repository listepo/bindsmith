/// `bindsmith doctor` (plan P1-5): can this machine generate what
/// `bindsmith.yaml` asks for?
///
/// Every check has the same shape — find a program or a file, read a version
/// out of it — so the only impure step is [Probe], which tests hand in
/// themselves. What is left is data: which tool a driver needs, where libclang
/// hides on each operating system, which JDK versions jnigen accepts. That is
/// the same split `deps/maven.dart` makes between `Pom.parse` and the fetch.
///
/// Only a toolchain the *configured* platforms need is required, and only one
/// the host could actually have: asking a Linux box for Xcode reports a
/// problem nobody can fix. Without a configuration — a fresh machine, before
/// `bindsmith init` — everything the host supports is checked and nothing is
/// required, because there is nothing yet to be missing for.
library;

import 'dart:io' as io;

import 'package:path/path.dart' as p;

import '../config/config.dart';
import '../emit/apple_glue.dart';
import '../ir/ir.dart';
import 'android_sdk.dart';

/// A toolchain bindsmith drives, and what it drives it for.
enum Tool {
  dart('the Dart SDK'),
  libclang('ffigen, behind the c and objc drivers'),
  swiftc('swiftgen, behind the swift driver'),
  xcode('the Apple SDKs'),
  jdk('jnigen, behind the jvm driver'),
  androidSdk('the Android platform jars'),
  node('the TypeScript sidecar, behind the dts driver'),
  msvc('compiling the native sources of a Windows build'),
  pkgConfig('resolving "pkg-config:" dependencies');

  const Tool(this.purpose);

  /// Prose for the report: what is lost when this one is missing.
  final String purpose;
}

/// What one check found. [found] is the version or path it landed on;
/// [problem] says why that is not good enough, and is `null` when it is.
typedef Check = ({
  Tool tool,
  bool required,
  String? found,
  String? problem,
  String fix,
});

/// A check passed: something was found and nothing is wrong with it.
bool isOk(Check check) => check.found != null && check.problem == null;

/// Runs [executable] and returns what it printed, or `null` if it is not on
/// `PATH` or failed. The one impure step in this file.
///
/// stdout and stderr are read together on purpose: `javac -version` printed to
/// stderr before JDK 9 and to stdout after it.
String? probeProcess(String executable, List<String> args) {
  try {
    final result = io.Process.runSync(executable, args);
    if (result.exitCode != 0) return null;
    final output = '${result.stdout}\n${result.stderr}'.trim();
    return output.isEmpty ? null : output;
  } on io.ProcessException {
    return null;
  }
}

/// How [doctor] runs a program.
typedef Probe = String? Function(String executable, List<String> args);

/// The host as one of the platforms bindsmith knows; anything exotic is
/// treated as Linux, which is what its toolchain looks like.
Platform hostPlatform() => switch (io.Platform.operatingSystem) {
  'macos' => Platform.macos,
  'windows' => Platform.windows,
  _ => Platform.linux,
};

/// Checks the toolchains [config] needs, or every one this host supports when
/// there is no configuration yet.
List<Check> doctor({
  BindsmithConfig? config,
  Probe probe = probeProcess,
  Platform? host,
  Map<String, String>? environment,
}) {
  final os = host ?? hostPlatform();
  final env = environment ?? io.Platform.environment;
  final required = config == null ? const <Tool>{} : requiredTools(config, os);
  final tools = config == null
      ? [
          for (final tool in Tool.values)
            if (_supportedOn(tool, os)) tool,
        ]
      : required.toList();
  return [
    for (final tool in tools)
      _check(
        tool,
        probe,
        env,
        os,
        config: config,
        required: required.contains(tool),
      ),
  ];
}

/// The toolchains [config] needs on a [os] host, in [Tool] order.
///
/// A driver decides most of it; a platform adds what building for it needs.
/// The Dart SDK is always in, since it is what runs bindsmith.
Set<Tool> requiredTools(BindsmithConfig config, Platform os) {
  final tools = {Tool.dart};
  for (final MapEntry(key: platform, value: spec) in config.platforms.entries) {
    switch (spec.driver) {
      case Driver.c || Driver.objc:
        tools.add(Tool.libclang);
      case Driver.swift:
        // swiftgen runs swiftc and the symbol graph extractor, then ffigen
        // over the Objective-C header swiftc wrote.
        tools.addAll([Tool.libclang, Tool.swiftc, Tool.xcode]);
      case Driver.jvm:
        tools.add(Tool.jdk);
      case Driver.dts:
        tools.add(Tool.node);
      case Driver.winmd:
        // package:winmd is pure Dart and reads metadata on any host.
        break;
      case Driver.dbus:
        // package:dbus generates the client in pure Dart.
        break;
    }
    switch (platform) {
      case Platform.ios || Platform.macos:
        tools.add(Tool.xcode);
      case Platform.android:
        tools.addAll([Tool.jdk, Tool.androidSdk]);
      case Platform.windows:
        if (spec.build != null) tools.add(Tool.msvc);
      case _:
        break;
    }
    if (spec.deps.pkgConfig.isNotEmpty) tools.add(Tool.pkgConfig);
  }
  return {
    for (final tool in Tool.values)
      if (tools.contains(tool) && _supportedOn(tool, os)) tool,
  };
}

/// Whether [os] could have [tool] at all. Reporting a missing Xcode on Linux
/// is a problem nobody can fix.
bool _supportedOn(Tool tool, Platform os) => switch (tool) {
  Tool.swiftc || Tool.xcode => os == Platform.macos,
  Tool.msvc => os == Platform.windows,
  Tool.pkgConfig => os != Platform.windows,
  _ => true,
};

Check _check(
  Tool tool,
  Probe probe,
  Map<String, String> env,
  Platform os, {
  BindsmithConfig? config,
  required bool required,
}) {
  final (found, problem) = switch (tool) {
    Tool.dart => (_firstLine(probe('dart', ['--version'])), null),
    Tool.libclang => (_libclang(probe, os), null),
    Tool.swiftc => (_firstLine(probe('swiftc', ['--version'])), null),
    Tool.xcode => _xcode(probe, config),
    Tool.jdk => _atLeast(
      probe('javac', ['-version']),
      minimum: 17,
      maximum: 21,
      what: 'jnigen',
    ),
    Tool.androidSdk => _androidSdk(env, config),
    Tool.node => _atLeast(
      probe('node', ['--version']),
      minimum: 20,
      what: 'the sidecar',
    ),
    Tool.msvc => (_msvc(probe, env), null),
    Tool.pkgConfig => (_firstLine(probe('pkg-config', ['--version'])), null),
  };
  return (
    tool: tool,
    required: required,
    found: found,
    problem: problem,
    fix: _fix(tool, os, config: config),
  );
}

String? _firstLine(String? output) => output?.split('\n').first.trim();

(String?, String?) _xcode(Probe probe, BindsmithConfig? config) {
  final macosSdk = _firstLine(probe('xcrun', ['--show-sdk-path']));
  if (macosSdk == null) return (null, null);
  final wantsIos = config == null || config.platforms.containsKey(Platform.ios);
  if (!wantsIos) return (macosSdk, null);
  final sim = _firstLine(
    probe(
      appleDoctorSimulatorSdkProbe.first,
      appleDoctorSimulatorSdkProbe.skip(1).toList(),
    ),
  );
  if (sim == null) {
    return (
      macosSdk,
      'no iPhone simulator SDK; run: ${appleDoctorSimulatorSdkProbe.join(' ')}',
    );
  }
  return ('$macosSdk; simulator $sim', null);
}

/// Reads the first version number out of [output] and checks it against the
/// range the generator that consumes it accepts.
(String?, String?) _atLeast(
  String? output, {
  required int minimum,
  required String what,
  int? maximum,
}) {
  final line = _firstLine(output);
  if (line == null) return (null, null);
  final major = int.tryParse(RegExp(r'(\d+)').firstMatch(line)?.group(1) ?? '');
  if (major == null) return (line, 'cannot read a version out of "$line"');
  if (major < minimum || (maximum != null && major > maximum)) {
    final range = maximum == null ? '$minimum or newer' : '$minimum–$maximum';
    return (line, '$what needs $range, this is $major');
  }
  return (line, null);
}

/// The Android SDK is a directory, named by the environment rather than found
/// on `PATH`; `ANDROID_HOME` is the current spelling, `ANDROID_SDK_ROOT` the
/// one older setups still export. What jnigen needs from it is the configured
/// platform's `android.jar`, the class path of every class that uses the
/// Android API.
(String?, String?) _androidSdk(
  Map<String, String> env,
  BindsmithConfig? config,
) {
  final compileSdk = config?.platforms[Platform.android]?.compileSdk;
  if (compileSdk == null) {
    final sdk = findAndroidSdkRoot(env);
    return sdk == null ? (null, null) : (sdk, null);
  }
  final (jar, problem) = findAndroidJar(env, compileSdk: compileSdk);
  if (jar != null) return (jar, null);
  return (findAndroidSdkRoot(env), problem);
}

/// The Visual Studio Build Tools are found the documented way: `vswhere.exe`
/// ships at a fixed path with every installer since VS 2017, so it is there
/// even when nothing is on `PATH`. A Developer Command Prompt has already
/// answered the question through `VCToolsInstallDir`.
String? _msvc(Probe probe, Map<String, String> env) {
  final prompt = env['VCToolsInstallDir'];
  if (prompt != null && prompt.isNotEmpty) return prompt;
  final vswhere = p.join(
    env['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)',
    'Microsoft Visual Studio',
    'Installer',
    'vswhere.exe',
  );
  if (!io.File(vswhere).existsSync()) return null;
  return _firstLine(
    probe(vswhere, [
      '-latest',
      '-products',
      '*',
      '-requires',
      'Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
      '-property',
      'installationPath',
    ]),
  );
}

/// libclang is a library, not a program: ffigen loads it from a fixed list of
/// locations per operating system and then asks the compiler where it is
/// (ffigen 22, `src/strings.dart` and `src/config_provider/spec_utils.dart`).
/// doctor looks in the same places and in the same order, so "doctor says yes"
/// and "ffigen found it" cannot disagree.
String? _libclang(Probe probe, Platform os) {
  final (name, locations) = switch (os) {
    Platform.macos => (
      'libclang.dylib',
      const [
        '/Library/Developer/CommandLineTools/usr/lib/',
        '/usr/local/opt/llvm/lib/',
        '/opt/homebrew/opt/llvm/lib/',
        '/Applications/Xcode.app/Contents/Developer/Toolchains/'
            'XcodeDefault.xctoolchain/usr/lib/',
      ],
    ),
    Platform.windows => ('libclang.dll', const [r'C:\Program Files\LLVM\bin\']),
    _ => (
      'libclang.so',
      const [
        '/usr/lib/llvm-20/lib/',
        '/usr/lib/llvm-19/lib/',
        '/usr/lib/llvm-18/lib/',
        '/usr/lib/llvm-17/lib/',
        '/usr/lib/',
        '/usr/lib64/',
      ],
    ),
  };
  for (final directory in locations) {
    final path = p.join(directory, name);
    if (io.File(path).existsSync()) return path;
  }
  // The last resort ffigen also takes: clang knows where its own library is.
  final printed = _firstLine(probe('clang', ['-print-file-name=$name']));
  if (printed != null && io.File(printed).existsSync()) return printed;
  return null;
}

/// What to type to fix a missing [tool] on [os].
String _fix(Tool tool, Platform os, {BindsmithConfig? config}) =>
    switch (tool) {
      Tool.dart => 'install the Dart SDK: https://dart.dev/get-dart',
      Tool.libclang => switch (os) {
        Platform.macos => 'xcode-select --install',
        Platform.windows => 'winget install LLVM.LLVM',
        _ => 'sudo apt-get install libclang-dev',
      },
      Tool.swiftc || Tool.xcode =>
        'install Xcode from the App Store, then: '
            'sudo xcode-select -s /Applications/Xcode.app',
      Tool.jdk => 'mise use -g java@temurin-21 (or install Temurin 21)',
      Tool.androidSdk => () {
        final sdk = config?.platforms[Platform.android]?.compileSdk ?? '35';
        return 'install the Android SDK, export ANDROID_HOME=<sdk directory> and add a '
            'platform: sdkmanager "platforms;android-$sdk"';
      }(),
      Tool.node => 'mise use -g node@24 (or install Node 20 or newer)',
      Tool.msvc =>
        'install the Visual Studio Build Tools with the C++ workload, then run '
            'bindsmith from a Developer Command Prompt',
      Tool.pkgConfig => switch (os) {
        Platform.macos => 'brew install pkg-config',
        _ => 'sudo apt-get install pkg-config',
      },
    };
