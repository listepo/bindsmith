/// bindsmith: one config, six Flutter platforms.
///
/// Library entry point for embedding the generator (the CLI in `bin/` uses
/// the same API). See `plan.md` for the pipeline: drivers → IR → passes →
/// emitters → verification.
library;

export 'src/cli/doctor.dart';
export 'src/cli/runner.dart';
export 'src/config/config.dart';
export 'src/config/reference.dart';
export 'src/config/schema.dart';
export 'src/deps/lockfile.dart';
export 'src/deps/maven.dart';
export 'src/deps/npm.dart';
export 'src/deps/nuget.dart';
export 'src/deps/resolve.dart';
export 'src/drivers/c/c_driver.dart';
export 'src/drivers/c/objc_driver.dart';
export 'src/drivers/dbus/dbus_driver.dart';
export 'src/drivers/dts/dts_driver.dart';
export 'src/drivers/jvm/jvm_driver.dart';
export 'src/drivers/swift/swift_driver.dart';
export 'src/drivers/winmd/winmd_driver.dart';
export 'src/emit/android_glue.dart';
export 'src/emit/apple_glue.dart';
export 'src/emit/build_hook.dart';
export 'src/emit/cpp_shim.dart';
export 'src/emit/editable_regions.dart';
export 'src/emit/facade.dart';
export 'src/emit/js_interop.dart';
export 'src/emit/kotlin_bridge.dart';
export 'src/emit/layout.dart';
export 'src/emit/swift_bridge.dart';
export 'src/emit/win32.dart';
export 'src/ir/ir.dart';
export 'src/passes/fixups.dart';
export 'src/passes/passes.dart';
export 'src/verify/verify.dart';
