# Examples

Seven `package_ffi`-style packages that drive bindsmith against real SDKs. Each
has a tiny Flutter app under `example/` that `flutter build`s in CI where the
host can.

| Package | Driver | Platforms CI builds |
| --- | --- | --- |
| [`avfoundation_audio`](avfoundation_audio) | ObjC | macOS, iOS |
| [`androidx_biometric`](androidx_biometric) | JVM + Maven | Android APK |
| [`sqlite_desktop`](sqlite_desktop) | C + `hook/build.dart` | Windows, Linux, macOS |
| [`chartjs_web`](chartjs_web) | `.d.ts` | Web |
| [`swift_volume`](swift_volume) | Swift + `wrapper: auto` | macOS, iOS |
| [`dbus_greeter`](dbus_greeter) | D-Bus | Linux |
| [`win32_tickcount`](win32_tickcount) | WinMD | Windows |

Generate from the package directory after `dart pub get` / `flutter pub get`:

```
dart run bindsmith resolve   # when the config has Maven or npm deps
dart run bindsmith generate
```

`sqlite_desktop` fetches the SQLite amalgamation with `tool/fetch_sqlite.sh`
(the `.c` is not committed). `chartjs_web` binds a curated subset of Chart.js
types in `src/chart.d.ts`; the published `chart.js` typings contain mapped types
the js_interop emitter cannot format yet.
