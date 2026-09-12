# bindsmith — исследование: генератор биндингов нативных API для всех платформ Flutter

Дата: 2026-09-08. Метод: 8 параллельных исследовательских агентов (Haiku) по измерениям D1–D8 → 5 адверсариальных фактчек-агентов (FC-1…FC-4) → синтез (Fable). Сырые отчёты лежат в `docs/research-raw/`. Утверждения, которые фактчек не подтвердил, помечены `[~]`; исправленные — `[✗→✓]`; подтверждённые первоисточником — без пометки.

---

## 1. Постановка задачи

Нужна программа, которая по описанию нативного API (заголовки C/Objective-C, Swift-модули, JAR/AAR, `.d.ts`, `.winmd`, `.gir`, D-Bus XML) генерирует Dart-биндинги для шести платформ Flutter — Android, iOS, macOS, Windows, Linux, Web — запускается из командной строки и управляется конфигами. Ориентиры: Mono/Xamarin/.NET MAUI (bgen, Objective Sharpie, class-parse/generator, Metadata.xml), NativeScript (metadata generator + динамический рантайм), плюс Rust/IDL-миры (uniffi, flutter_rust_bridge, Gluecodium, Djinni, SWIG).

Ключевое различие, которое нужно держать в голове:

| Направление | Что это | Инструменты Dart |
|---|---|---|
| native → Dart («биндинги») | Dart вызывает существующий нативный API напрямую | ffigen (C/ObjC), swiftgen (Swift), jnigen (Java/Kotlin), dart:js_interop (JS), win32/winmd, dbus, gir |
| Dart ↔ native («каналы/скаффолдинг») | Определяем интерфейс сообщений, генерируем обе стороны | pigeon (Kotlin/Java/Swift/ObjC/C++/GObject; Web не поддерживается) |

Задача пользователя — первое направление; pigeon остаётся вспомогательным (для случаев, где прямой вызов невозможен или нежелателен).

---

## 2. Что реально существует в Dart/Flutter (сентябрь 2026)

| Пакет | Версия / дата | Что делает | Конфиг | Ограничения |
|---|---|---|---|---|
| `ffigen` | 22.0.0 (2026-09-08) | C и Objective-C заголовки → Dart FFI через libclang | Dart-скрипт `tool/ffigen.dart`: `FfiGenerator`, `Input`, `DartOutput`, visitor-API (`.name`, `.isIncluded`). YAML объявлен устаревшим | Нет C++; макросы, varargs, SAL-аннотации, `__stdcall` — проблемные зоны |
| `objective_c` | 9.6.0 (2026-08-20) | Рантайм ObjC-интеропа: `ObjCObjectBase`, блоки (`.fromFunction/.listener/.blocking`), ARC через `NativeFinalizer`, протоколы через `ObjCProtocolBuilder` | — | Только Apple |
| `swift2objc` | 0.3.0 (2026-09-08) [✗→✓ есть на pub.dev] | Генерирует ObjC-обёртку из Swift-кода | Dart-API | Экспериментальный |
| `swiftgen` | 0.2.0 (2026-09-08) | Оркестрирует swift2objc → swiftc → ffigen; выдаёт `.g.dart` + `.m` | Dart-скрипт с классом `SwiftGenerator` (`target`, `inputs`, `include`, `output`, `ffigen`) | Экспериментальный; README 4 строки; только NSObject-совместимые типы (структуры/генерики Swift не пробрасываются) |
| `jnigen` / `jni` | 1.0.0 (2026-09-03) / 1.0.3 (2026-07-30) [✗→✓ jni не 1.0.0] | Java/Kotlin (байткод или исходники) → Dart через JNI | Dart-скрипт `tool/jnigen.dart`: `JniGenerator`, `Input`, `DartOutput`, метод `generate()`; YAML — legacy | Требует JDK 17–21 и Android SDK при генерации; Kotlin suspend → `Future`, nullability из Kotlin-метаданных; интерфейсы реализуются через `implement()`; глобальные ссылки освобождаются вручную (`.release()`) |
| `pigeon` | 28.0.0 (2026-08-21) | Типобезопасные platform channels; `@HostApi`, `@FlutterApi`, `@ProxyApi` | Dart-файл с `@ConfigurePigeon(PigeonOptions(...))` | Web не поддерживается; обе стороны — одна версия pigeon; публичные API на pigeon «strongly discouraged» |
| `win32` / `winmd` | 6.4.0 (2026-08-05) / 7.1.1 (2026-08-04) | Win32/COM-биндинги, сгенерированные из Microsoft `Win32Metadata` (`.winmd`) | Внутренний генератор в `halildurmus/win32/packages/generator` (курируемые JSON-списки) | Пользователь биндинги не генерирует — берёт готовые; `winmd` можно использовать как библиотеку чтения метаданных |
| `dbus` (Canonical) | 0.7.15 (2026-08-20) | `dart-dbus generate-remote-object <iface.xml>` / `generate-object` | CLI | Только D-Bus (Linux), LGPL 2.1 |
| `dart-gobject-bindings` (`gir-binding-gen`) | community, обновлён 2026-09-06 | `.gir` (GObject-Introspection) → Dart | — | Незрелый, один автор |
| `web` + `web_generator` | web_generator — внутренний инструмент dart-lang/web, на pub.dev нет [✗→✓] | Генерирует `package:web` из WebIDL (`@webref/idl`, `webidl2`) | — | TypeScript `.d.ts` НЕ поддерживает |
| `js_interop_gen` (dart-lang/web) | не опубликован; PR 2025 (#549, #554) | `.d.ts` → Dart `dart:js_interop` (extension types) | — | В разработке; единственный живой TS→Dart генератор (js_facade_gen архивирован в 2022) |
| `hooks` / `code_assets` / `native_toolchain_c` / `native_toolchain_cmake` | 2.2.0 / 2.0.0 / 0.19.4 / 0.3.2 (август 2026) | Build hooks (`hook/build.dart`, `hook/link.dart`): сборка и бандлинг нативного кода | Dart | Включены по умолчанию в stable с Flutter 3.38 (Dart 3.10, ноябрь 2025) [✗→✓ не «сентябрь 2024»] |
| Шаблон `package_ffi` | рекомендован с Flutter 3.38; `plugin_ffi` deprecated [✗→✓] | `lib/`, `src/`, `hook/build.dart` | — | — |

Прочее: `dart:js_interop` стабилен с Dart 3.3 (февраль 2024), `dart:js_util`/`package:js` deprecated с Dart 3.7; dart2wasm компилирует только `dart:js_interop`-код. Pub workspaces стабильны с Dart 3.6. `dart compile exe --target-os` кросс-компилирует только в Linux (arm, arm64, riscv64, x64) [✗→✓].

Кто чем пользуется в продакшене (D7, частично без перепроверки `[~]`): плагины команды Flutter (webview_flutter, camera, video_player, in_app_purchase, local_auth) — pigeon; path_provider/url_launcher/shared_preferences — рукописные каналы; команда Dart — `cupertino_http` (ffigen ObjC, `ffigen.yaml` в репо), `ok_http` (jnigen), `sqlite3` (ffigen C); Sentry мигрирует на FFI/JNI `[~]`; Nutrient выпустил «bindings API» (beta февраль 2026 → GA июль 2026) `[~]`; HERE SDK — Gluecodium (свой генератор с Dart-целью). Ни один вендор не генерирует Flutter-обёртки автоматически из SDK; issue flutter/flutter#98084 «Web interop в pigeon» открыт с 2022.

Вывод: все кирпичи для отдельных платформ есть и официально поддерживаются, но **нет ни одного инструмента, который берёт одну декларацию и выдаёт биндинги для шести платформ** плюс единый Dart-фасад. Ближайшие «оркестраторы» — swiftgen (только Swift→ObjC→Dart) и dart-native/codegen (ObjC+Java, без документации).

---

## 3. Как генерируют interop/binding нативного API на каждой платформе

Единая схема: **вход → генератор → конфиг → команды → рантайм → интеграция в сборку → подводные камни**. Сниппеты конфигов схематичны (имена классов взяты из changelog'ов ffigen 22 / jnigen 1.0; точные сигнатуры — в API-docs пакетов).

### 3.1 Android — Java/Kotlin через jnigen + jni

- **Вход:** `.class`/JAR/AAR (в т.ч. из Maven), либо Java-исходники; Kotlin — только скомпилированный (метаданные Kotlin читаются для nullability и `suspend`).
- **Конфиг** `tool/jnigen.dart`:
  ```dart
  import 'package:jnigen/jnigen.dart';
  void main() => JniGenerator(
        input: Input(
          classes: ['androidx.biometric.BiometricPrompt'],
          // maven-зависимости, android_sdk_config(add_gradle_deps), source_path...
        ),
        output: Output(dart: DartOutput(path: Uri.directory('lib/src/android/'))),
      ).generate();
  ```
  Legacy-вариант: `jnigen.yaml` (`classes:`, `maven_downloads: source_deps/jar_only_deps`, `android_sdk_config: add_gradle_deps: true`, `output: dart: path/structure`).
- **Команды:** `dart run tool/jnigen.dart` (или `dart run jnigen --config jnigen.yaml`). Для плагина с Android-примером jnigen сам вызывает Gradle, чтобы собрать classpath — поэтому «сначала собери Android».
- **Рантайм:** `package:jni` — `JObject`, `JString`, `JList/JMap`, `Jni.spawn()` для десктопной JVM; глобальные ссылки освобождать `.release()`; Java-интерфейсы реализуются из Dart через `Interface.implement(...)`.
- **Сборка:** `ffiPlugin: true`/Gradle; R8/ProGuard keep-правила для классов, вызываемых из Dart; JDK 17–21.
- **Камни:** нумерованные суффиксы перегрузок меняются между версиями (`Intent.new$2` → `Intent.new$12`); корутины/default-параметры/companion объекты требуют Kotlin-фасада; коллбек-объекты держать в Dart-ссылке, иначе GC.

### 3.2 iOS / macOS — Objective-C через ffigen + objective_c; Swift через swiftgen

- **Вход ObjC:** заголовки фреймворков (системных или из xcframework/pod). **Вход Swift:** Swift-модуль; swiftgen сам делает `swift2objc` → `swiftc -emit-objc-header` → ffigen.
- **Конфиг** `tool/ffigen.dart` (ObjC):
  ```dart
  import 'package:ffigen/ffigen.dart';
  void main() => FfiGenerator(
        input: Input(entryPoints: [Uri.file('src/wrapper.h')], /* language objc, compilerOpts */),
        output: Output(dart: DartOutput(path: Uri.file('lib/src/ios/av.dart'))),
        // objcInterfaces / protocols / categories — include-фильтры;
        // visitor: переименования, исключения
      ).generate();
  ```
  Swift: `tool/swiftgen.dart` с `SwiftGenerator(target:, inputs:, include:, output:, ffigen:)`.
- **Команды:** `dart run tool/ffigen.dart`; `dart run tool/swiftgen.dart`. Коммитить и `.g.dart`, и `.m` (последний должен попадать в `Classes/**` podspec'а).
- **Рантайм:** `package:objective_c` (ARC через `NativeFinalizer`, блоки `.fromFunction`/`.listener`/`.blocking`, протоколы через `$Builder.implementAsListener`), `package:ffi`.
- **Сборка:** podspec `s.frameworks = 'AVFoundation'` или SwiftPM `linkerSettings: [.linkedFramework(...)]`; `ffiPlugin: true` для ios/macos.
- **Камни:** только `@objc`/NSObject-совместимые Swift-API видны; блоки, вызываемые с чужого потока, — только `.listener`/`.blocking`; UIKit/AppKit — main thread; include-фильтры обязательны (иначе миллионы строк из транзитивных фреймворков); макросы не переносятся.

### 3.3 Windows — C через ffigen, Win32/COM через win32 (+winmd), C++ через шим

- **Вход:** C-заголовки (свои или SDK, пути `Windows Kits\10\Include\...\um|shared`); для Win32 — `.winmd` из NuGet `Microsoft.Windows.SDK.Win32Metadata`.
- **Генератор:** ffigen (`Input(compilerOpts: ['-I...'])`); Win32 — готовый `package:win32` (регенерировать самим не нужно; для кастомного среза — `package:winmd` как читатель метаданных); C++ SDK — `extern "C"` шим, собираемый `native_toolchain_c`/`native_toolchain_cmake` из `hook/build.dart`.
- **Рантайм:** `package:ffi`, `package:win32` (COM vtables, `calloc/free`).
- **Сборка:** `hook/build.dart` (`build(args, (input, output) => CBuilder/CLibrary...)`), `ffiPlugin: true` для windows; каналы — pigeon C++ (`cppHeaderOut/cppSourceOut`).
- **Камни:** libclang нужен для ffigen; SAL-аннотации/`__stdcall`; MSVC-редистрибутивы при дистрибуции; pigeon C++ с forward-declaration багами (issue #128330).

### 3.4 Linux — C через ffigen + pkg-config, D-Bus через dart-dbus, GObject через .gir

- **Вход:** C-заголовки (`pkg-config --cflags gtk+-3.0` → include-пути); D-Bus introspection XML; `.gir`.
- **Генератор:** ffigen (Canonical так делает `glib.dart`, `stdlibc.dart`); `dart-dbus generate-remote-object iface.xml -o lib/x.dart` (клиент) / `generate-object` (сервер); `gir-binding-gen` (community).
- **Рантайм:** `package:ffi`, `package:dbus`.
- **Сборка:** `hook/build.dart` + `ffiPlugin: true`; каналы — pigeon GObject (Flutter Linux embedder — GTK3; миграция на GTK4 стоит с 2021, issue #94804).
- **Камни:** макросы `G_OBJECT()`-кастов и `g_object_new` varargs не переносятся ffigen; версии glibc; D-Bus-код «черновой», требует доводки.

### 3.5 Web — dart:js_interop, package:web, генерация из .d.ts

- **Вход:** браузерные API — WebIDL (уже сгенерированы в `package:web`); JS-библиотеки — `.d.ts` (npm) или ручные декларации.
- **Генератор:** для приложений — ручные `extension type Chart(JSObject _) implements JSObject { external ... }` с `@JS()`; автоматика из `.d.ts` — только неопубликованный `js_interop_gen` в dart-lang/web; `js_facade_gen` архивирован (2022).
- **Рантайм:** `dart:js_interop` (`JSPromise.toDart`, `.toJS`, `JSFunction`), `package:web`.
- **Сборка:** `<script>` в `web/index.html` или загрузка в `flutter_bootstrap.js`; плагин — `pluginClass`/`fileName` в `flutter: plugin: platforms: web`.
- **Камни:** структурная типизация TS против номинальных extension types; коллбеки держать (`.toJS`), иначе GC; `dart:html`/`package:js` не собираются dart2wasm.

### 3.6 Общая упаковка

- `flutter create --template=package_ffi <name>` (Flutter ≥ 3.38): `lib/`, `src/`, `hook/build.dart`; `hooks` + `code_assets` + `native_toolchain_c` в dev_dependencies.
- Federated plugin: app-facing пакет с `default_package:` на платформу, реализации с `implements:`; для FFI-реализаций — `ffiPlugin: true`.
- Pigeon: `dart run pigeon --input pigeons/messages.dart`; `@async` → Kotlin `suspend`/Swift `async throws` (по умолчанию с v28).

### 3.7 Сводная таблица

| Платформа | Вход | Генератор | Конфиг | Рантайм | Сборка | Зрелость |
|---|---|---|---|---|---|---|
| Android | .class/JAR/AAR, Maven | jnigen 1.0 | `tool/jnigen.dart` | jni 1.0.3 | Gradle, R8 keep | стабильно, но breaking 0.14→1.0 |
| iOS/macOS ObjC | .h фреймворков | ffigen 22 (objc) | `tool/ffigen.dart` | objective_c 9.6 | podspec/SwiftPM | стабильно |
| iOS/macOS Swift | Swift-модуль | swiftgen 0.2 | `tool/swiftgen.dart` | objective_c | podspec Classes/** | экспериментально |
| Windows C | .h | ffigen 22 (c) | `tool/ffigen.dart` | ffi | hook/build.dart | стабильно |
| Windows Win32/COM | .winmd | win32 (готовый), winmd | — | win32 | — | стабильно, без самостоятельной генерации |
| Linux C/GLib | .h + pkg-config | ffigen 22 | `tool/ffigen.dart` | ffi | hook/build.dart | стабильно, макросы вручную |
| Linux D-Bus | introspection XML | dart-dbus | CLI | dbus | — | стабильно |
| Linux GObject | .gir | gir-binding-gen | — | — | — | незрелый |
| Web browser API | WebIDL | web_generator (внутренний) | — | web | — | стабильно (готовый пакет) |
| Web JS-библиотеки | .d.ts | js_interop_gen (не опубликован) / вручную | — | dart:js_interop | index.html | пробел рынка |
| Каналы | Dart IDL | pigeon 28 | `@ConfigurePigeon` | — | — | стабильно; нет Web |

---

## 4. Аналоги в других экосистемах

### 4.1 Mono / Xamarin / .NET MAUI

**iOS/macOS (dotnet/macios).** Биндинг — вручную написанные `ApiDefinition.cs`/`StructsAndEnums.cs` с атрибутами `[BaseType]`, `[Export]`, `[Protocol]`, `[Model]`, `[NullAllowed]`, `[Static]`, `[Wrap]`, `[BindAs]`, `[Field]`; генератор `bgen` выпускает objc_msgSend-трамплины и регистратор. Все Apple SDK привязаны так же, вручную, а покрытие проверяется тестами `xtro-sharpie`. RFC #21308 (перенос bgen на Roslyn, «rgen») открыт с сентября 2024, milestone Future, разработки нет [✗→✓].

**Objective Sharpie.** `dotnet tool install -g Sharpie.Bind.Tool`; только macOS; исходники не публичны, но это обычный dotnet global tool, а не «закрытая утилита» [✗→✓]. Парсит заголовки libclang'ом, выдаёт черновик ApiDefinition с атрибутом `[Verify]`, который **намеренно ломает компиляцию, пока разработчик не проверит место и не удалит атрибут** (подсказки: `InferredFromPreceedingTypedef`, `ConstantsInterfaceAssociation`, `MethodToProperty`, `StronglyTypedNSArray`, `PlatformInvoke`). Это лучший из известных UX-паттернов принудительного ревью сгенерированного кода.

**Android (.NET for Android).** `class-parse` читает байткод (включая Kotlin-метаданные) → `api.xml` → `generator` выдаёт C# с `[Register]`/`JniPeerMembers`. Фиксапы — `Metadata.xml` на XPath: `<remove-node path="..."/>`, `<attr path="..." name="managedName">…</attr>`, `<add-node>`; плюс `EnumFields.xml`/`EnumMethods.xml`. Зависимости — `<AndroidMavenLibrary Include="g:a" Version="…"/>` (.NET 9) с автоматической загрузкой из Maven и **верификацией Java-зависимостей**. Kotlin `suspend` (скрытый `Continuation`) не биндится `[~]`.

**Swift.** .NET 9: `CallConvSwift`, `SwiftSelf`/`SwiftError`; экспериментальный `dotnet/runtimelab` SwiftBindings потребляет `.swiftinterface` + dylib, пока только структуры/enum/статические функции.

**Native Library Interop (MAUI Community Toolkit).** Официально рекомендуемый паттерн «slim binding»: пишешь тонкую обёртку на Swift/Kotlin с простой поверхностью → биндишь обёртку, а не SDK. Шаблон — репозиторий `CommunityToolkit/Maui.NativeLibraryInterop` (не `dotnet new`).

**C/C++/Win32.** CppSharp v1.2 (Clang 19; конфиг — C#-класс `ILibrary`, конвейер passes); ClangSharpPInvokeGenerator 21.1.8.4 (`.rsp`-файлы, `--remap`, `--with-attribute`, `--exclude`, `--traverse`); CsWin32 0.3.333 — Roslyn source generator с **pull-моделью**: `NativeMethods.txt` перечисляет нужные API, генерируется только они из `Windows.Win32.winmd`; win32metadata 71.x — единая машинно-читаемая модель Win32, которую едят CsWin32, windows-rs, Dart `win32`, Zig.

**Уроки .NET:** (1) nullability и generics — вечные щели; (2) без ручных фиксапов не обходится ни один SDK; (3) slim binding победил «биндить всё»; (4) разрешение зависимостей должно быть частью генератора; (5) `[Verify]` дешевле, чем баги в проде; (6) размер сгенерированного кода — проблема линковки/тримминга.

### 4.2 NativeScript — динамический полюс

Метаданные о всём API платформы генерируются на этапе сборки: iOS — `ios-metadata-generator` (C++/libclang) → бинарный `metadata-<arch>.bin`; Android — `android-metadata-generator` (ASM/BCEL) → `treeNodeStream/treeValueStream/treeStringsStream`. Рантайм (V8 на iOS с NativeScript 7.0, 2020 — не «9.0/2025» [✗→✓]) диспатчит вызовы через libffi/objc_msgSend и JNI-рефлексию. Фильтрация — `native-api-usage.json` (whitelist/blacklist в плагинах и `App_Resources`), а не `.mdg` [✗→✓]. Типы для IDE — `ns typings ios` / `ns typings android --jar|--aar`; пакеты `@nativescript/types-ios` 15.2 МБ и `types-android` 48.1 МБ (unpacked, 9.1.1). Наследование нативных классов — через Static Binding Generator.

Плюсы: 100% покрытие API без кодогена под каждую библиотеку; API становятся доступны сразу после выхода SDK. Минусы: рантайм и метаданные в бинаре, нет tree-shaking, старт медленнее, накладные на вызов **≈3.5× против нативного кода** по собственному бенчмарку NativeScript (49 мс vs 14 мс на 100k вызовов, iPhone 13 Pro, NS 8.3) [✗→✓ не «1.5–2×»]. Для Flutter такой путь означал бы собственный рантайм и потерю AOT-преимуществ — отвергнуто (см. §6). Заимствуем идею **whitelist использования API** как pull-модель и генерацию типов из метаданных.

Родственники: dart_native (Alibaba; pub.dev 0.7.11, декабрь 2022 — заброшен [✗→✓]; репозиторий `dart-native/codegen` живой, но без README), PyObjC/rubicon-objc, Pyjnius/Chaquopy, Unity `AndroidJavaObject`, JNA, koffi.

### 4.3 Rust и IDL-мультитаргеты

| Инструмент | Версия | Вход → выход | Конфиг | Урок для нас |
|---|---|---|---|---|
| uniffi-rs | 0.32.0 (2026-06-30) [✗→✓] | Rust (proc-macros/UDL) → Kotlin, Swift, Python, Ruby; сторонние: Go, C#, RN, **Dart** (`Uniffi-Dart/uniffi-dart` 0.2.1, июнь 2026, активен) | `uniffi.toml` `[bindings.<lang>]`, custom_types | Единый ComponentInterface + Askama-шаблоны + checksum'ы совместимости |
| flutter_rust_bridge | 2.13.0 (2026-08-23); 2.14 beta [✗→✓ не 1.8.2] | Rust (syn) → Dart, все 6 платформ (Web через wasm) | `flutter_rust_bridge.yaml` (`rust_input`, `dart_output`, integration cargokit/native-assets) | Единственный зрелый «одна декларация → 6 платформ», но вход только Rust |
| Gluecodium (HERE) | 14.1.1 (2026-03-03), активен | LIME IDL → C++, Java, Kotlin, Swift, **Dart** | CLI `-generators cpp,java,kotlin,swift,dart` | Официальная Dart-цель через dart:ffi и opaque handles; документация не переносится |
| Djinni | 1.4.1 (декабрь 2023) [✗→✓ не поддерживается] | IDL → C++/Java/ObjC | — | Нет Dart; мёртв |
| SWIG / wit-bindgen | — | нет Dart-цели (SWIG: issue #557; wit-bindgen: Rust, C, C++, C#, Go) | — | — |
| rust-bindgen | 0.72 | C/C++ → Rust | allowlist/blocklist, `ParseCallbacks` | Программируемые фиксапы |
| objc2 header-translator | objc2 0.6.4 | Apple SDK → `objc2-*` крейты | `translation-config.toml` per-framework (`skipped`, availability по ОС, safety-флаги) | Лучший образец декларативных фиксапов + availability gating |
| gtk-rs gir | — | `.gir` → sys + safe слои | `Gir.toml` `[[object]] status = generate/manual/ignore` | Два слоя: сырой и идиоматичный |
| windows-rs / windows-bindgen | 0.100.0 (2026-09-03) | `.winmd` → Rust | `--filter`, `--in/--out`, `--flat`, `--sys`, `--reference` (флаг `--minimal` не подтверждён [~]) | Pull-модель по фильтру |

### 4.4 Kotlin / Swift / Java / JS-экосистемы

- **Kotlin/Native cinterop** — `.def` (`headers`, `headerFilter`, `excludeFilter`, `compilerOpts`, `strictEnums`, C-преамбула после `---`); макросы не поддерживаются. **Swift export** — экспериментальный с Kotlin 2.2.20 (статус на 2.4.20 фактчек не подтвердил `[~]`). **SKIE** 0.10.14 (июль 2026) — Gradle-плагин Touchlab, чинит suspend/Flow/sealed на Swift-стороне. **karakum** 1.0.0-alpha.112 — TS `.d.ts` → Kotlin/JS через TypeScript Compiler API.
- **swift-java** 0.6.0 (2026-09-05): режимы `ffm` (JDK 25+, Swift 6.2) и `jni` (Android); JDK 17+ для макросов. **jextract** (OpenJDK, активен): libclang, `--include-*`, приём «`--dump-includes` → отредактировать → `--config`» — dump-then-curate. **JavaCPP presets** — `Info(...)` карты в Java-коде.
- **React Native** 0.87.1 (New Architecture по умолчанию с 0.76 `[~]`), codegen по TS-спекам (`codegenConfig`); Nitro/nitrogen (`nitro.json`; репозиторий переехал); Expo Modules DSL. **Agora Terra** — `cxx-parser` (cppast + libclang) → TerraNode AST → TS-рендереры, YAML-конфиг; Dart-рендерер для agora_rtc_engine `[~]`.
- **Общие уроки:** маппинг async у каждой экосистемы свой (suspend/Flow, Swift async, Promise → Future/Stream); nullability — из аннотаций (JSpecify, Kotlin-метаданные, ObjC `nullable`); генерики стираются; main-thread-аннотации нужно переносить; документация теряется почти у всех; snapshot-тесты сгенерированного кода + компиляционная матрица — универсальная практика; спектр фиксапов от «минимальные переименования» до «полный override».

---

## 5. Сравнительная матрица

| Инструмент | Подход | Вход | Цели | Конфиг | Фиксапы | Ревью | Зависимости | Зрелость / лицензия |
|---|---|---|---|---|---|---|---|---|
| Xamarin/MAUI bgen + Sharpie | статический кодоген, ручной IDL на C# | ObjC .h | C# iOS/macOS | C#-атрибуты | в самом ApiDefinition | `[Verify]` | pod/xcframework руками; NLI-шаблон | зрелый / MIT (Sharpie — не публичен) |
| .NET for Android generator | статический, из байткода | JAR/AAR | C# Android | MSBuild + `Metadata.xml` | XPath | нет | `AndroidMavenLibrary` + верификация | зрелый / MIT |
| CsWin32 | source generator, pull | `.winmd` | C# Windows | `NativeMethods.txt` | JSON опции | нет | NuGet metadata | зрелый / MIT |
| NativeScript | динамический рантайм + метаданные | SDK целиком | JS/TS iOS/Android | `native-api-usage.json` | нет | нет | CocoaPods/Gradle из плагина | зрелый / Apache-2.0 |
| uniffi-rs | статический из Rust | Rust | Kotlin/Swift/Py/Ruby (+Dart) | `uniffi.toml` | custom_types | нет | cargo | зрелый / MPL-2.0 |
| flutter_rust_bridge | статический из Rust | Rust | Dart × 6 платформ | YAML | атрибуты | нет | cargokit/native-assets | зрелый / MIT |
| Gluecodium | статический из IDL | LIME | C++/Java/Kotlin/Swift/Dart | CLI | в IDL | нет | — | зрелый / Apache-2.0 |
| objc2 header-translator | статический из SDK | Apple .h | Rust | `translation-config.toml` | декларативные | нет | — | зрелый / MIT |
| ffigen / jnigen / swiftgen / pigeon | статический, по одной платформе | .h / .class / Swift / Dart IDL | Dart | Dart-скрипты | visitor / include | нет | jnigen: Maven | стабильно / экспериментально; BSD |
| **bindsmith (предлагается)** | статический оркестратор + единый IR | .h, Swift, JAR/AAR, .d.ts, .winmd, .gir, D-Bus XML | Dart × 6 + фасад + нативные обёртки | YAML + JSON Schema, Dart-эскейп | декларативные + visitor | маркеры `verify` | Maven/CocoaPods/SwiftPM/npm/NuGet + lockfile | — |

---

## 6. Статический кодоген vs динамический мост

| Критерий | Статический (ffigen/jnigen/bgen) | Динамический (NativeScript) |
|---|---|---|
| Покрытие API | только описанное в конфиге (pull) | 100% сразу |
| Типобезопасность | полная, `dart analyze` | типы только для IDE |
| Размер приложения | минимальный (tree-shaking) | +метаданные, +рантайм |
| Производительность вызова | FFI-прямой вызов | ≈3.5× медленнее нативного |
| AOT/Flutter | естественно | нужен свой JIT/интерпретатор — на iOS невозможен |
| Стоимость поддержки | генератор × платформы | рантайм × платформы + метаданные |

Решение: статический кодоген. Из динамического мира берём pull-модель (whitelist использования) и генерацию типов из метаданных.

---

## 7. Выбор языка реализации

| Критерий | Dart | Rust | Kotlin/JVM | TypeScript/Node | C# |
|---|---|---|---|---|---|
| Доступ к официальным генераторам как к библиотекам (`FfiGenerator`, `JniGenerator`, `SwiftGenerator`, `Pigeon.runWithOptions`, `winmd`) | напрямую | только subprocess | subprocess | subprocess | subprocess |
| Эмиссия Dart (code_builder 4.12, dart_style 3.1, analyzer 14.3 для проверки) | родное | нет | нет | нет | нет |
| Дистрибуция для Flutter-разработчиков | `dart pub global activate`, `dart run`, `dart compile exe` | cargo/бинарь | JVM | npm | dotnet tool |
| Парсинг `.d.ts` | через node-сайдкар или порт | swc/oxc — без семантики типов | karakum-подход | TypeScript Compiler API — идеально | нет |
| Скорость генерации | не критична | избыточна | JVM-старт | ок | ок |
| Кто будет контрибьютить | Flutter-сообщество | узко | узко | широко, но чужое для Flutter | узко |

Решение: **Dart** для ядра, CLI и всех драйверов; для `.d.ts` — узкий сайдкар на TypeScript Compiler API (node), вызываемый драйвером `web`, либо переиспользование `js_interop_gen` из dart-lang/web, когда он созреет. Ничего второго языка в ядре.

---

## 8. Предлагаемая архитектура bindsmith

```
bindsmith.yaml ──► загрузчик конфига (yaml + JSON Schema) ──► план генерации
                                                                    │
     ┌──────────────┬──────────────┬──────────────┬─────────────────┼──────────────┬──────────────┐
  driver c       driver objc    driver swift   driver jvm       driver web     driver winmd   driver dbus/gir
  (ffigen)       (ffigen+       (swiftgen)     (jnigen)         (.d.ts/WebIDL  (package:winmd) (dart-dbus,
                 objective_c)                                    → js_interop)                   gir)
     └──────────────┴──────────────┴──────────────┴─────────────────┴──────────────┴──────────────┘
                                                                    │
                                   единый IR (BindingModel: типы, методы, поля, async, nullability, availability, docs)
                                                                    │
                     passes: include/exclude → rename → nullability → async-mapping → threading → availability
                             → doc-propagation → fixups (DSL) → verify-markers → size budget
                                                                    │
                  emitters: platform bindings (.g.dart) │ unified facade (conditional imports, stubs) │
                           native wrappers (Swift @objc / Kotlin facade) │ build glue (hook/build.dart, podspec, Gradle)
                                                                    │
                  verify: dart analyze │ compile matrix (macOS/Linux/Windows runners) │ golden tests │ lockfile check
```

Компоненты:

1. **Конфиг** `bindsmith.yaml` с опубликованной JSON Schema (`# yaml-language-server: $schema=...`) и Dart-эскейп-хатчем `tool/bindsmith.dart` (тот же путь, по которому пошли ffigen/jnigen).
2. **CLI** (`args`/`CommandRunner`, `mason_logger`, `cli_completion`): `init`, `doctor`, `resolve`, `generate [--platform]`, `verify`, `diff`, `watch`, `explain <symbol>`.
3. **Драйверы** — тонкие адаптеры над официальными генераторами через их библиотечные API (без парсинга их вывода), с пиннингом версий и адаптерами под breaking changes.
4. **IR + passes** — единая модель, куда сводятся все фронтенды; декларативные фиксапы в стиле `translation-config.toml`/`Metadata.xml`; pull-модель как в CsWin32 (`include:` списки), dump-then-curate как в jextract (`bindsmith dump` → отредактировать → `include`).
5. **Фасад** — один `lib/<pkg>.dart` с conditional imports (`dart.library.ffi` / `dart.library.js_interop`), платформенные реализации, `UnsupportedError`-заглушки, единый маппинг async (`Future`/`Stream`) и ошибок.
6. **Slim-binding генератор** — по IR выпускает Swift `@objc`-обёртку/Kotlin-фасад для непереносимого (Swift-структуры, suspend/Flow, генерики), плюс podspec/SwiftPM/Gradle-интеграцию (паттерн MAUI NLI, но автоматизированный).
7. **Разрешение зависимостей** — Maven (уже есть в jnigen), CocoaPods/SwiftPM (xcframework), npm (`.d.ts`), NuGet (`Win32Metadata`), pkg-config; `bindsmith.lock` с чексуммами для воспроизводимости.
8. **Verify-маркеры** — аналог `[Verify]`: сомнительные места помечаются `@BindsmithVerify('reason')`, а кастомный lint (analyzer plugin или `dart analyze` с `// ignore` протоколом) валит `bindsmith verify`, пока маркер не снят.
9. **Верификация** — golden-тесты сгенерированного кода, компиляционная матрица в CI (macOS: iOS/macOS; ubuntu: Linux/Android/Web; windows), отчёт размера сгенерированного кода, `doctor` для тулчейнов (libclang, JDK 17–21, Android SDK, Xcode, VS Build Tools, node).

YAGNI (не делаем): свой рантайм/динамический диспатч; собственный парсер C++ (шим `extern "C"` + slim-обёртка); поддержка макросов; GUI; обязательная AI-зависимость; собственный Dart-форматтер/анализатор.

---

## 9. Чем bindsmith будет лучше существующего

1. **Одна декларация → 6 платформ + единый фасад.** Сегодня это делает только flutter_rust_bridge и только для Rust-входа.
2. **Web-паритет.** `.d.ts` → `dart:js_interop` — публичного инструмента нет с 2022 года; issue про Web в pigeon открыт 4 года.
3. **Pull-модель + декларативные фиксапы + verify-маркеры** — синтез CsWin32, objc2, Sharpie; ни у одного Dart-инструмента этого нет.
4. **Slim-binding как генерируемый артефакт**, а не ручной совет из документации MAUI.
5. **Зависимости и lockfile** — генерация воспроизводима на CI без «сначала собери Android».
6. **Устойчивость к апстриму** — пиннинг ffigen/jnigen/swiftgen, адаптеры, миграционные диффы (`bindsmith diff` показывает, что изменилось после бампа генератора, включая переименования перегрузок `new$2 → new$12`).
7. **Перенос документации и availability** (`@available`/`@RequiresApi` → dartdoc + рантайм-проверки).
8. **Бюджет размера** — отчёт, сколько строк/символов сгенерировано на платформу и что можно исключить.

---

## 10. Риски

| Риск | Вероятность | Митигация |
|---|---|---|
| Breaking changes апстрима (ffigen 22 — переписанный API; jnigen 1.0; swiftgen 0.x) | высокая | пиннинг версий в драйверах, контрактные тесты на API генераторов, адаптеры |
| swiftgen/swift2objc экспериментальны | высокая | slim-binding fallback: генерируем `@objc`-обёртку сами |
| `.d.ts` → Dart: структурные типы, перегрузки, генерики | средняя | ограниченное подмножество + verify-маркеры; следить за `js_interop_gen` |
| Тяжёлый тулчейн (libclang, JDK, Android SDK, Xcode, VS) | высокая | `doctor`, контейнеры для CI, кэш артефактов |
| Поддержка 6 платформ одной командой | высокая | поэтапность: сначала C/ObjC/JVM, потом Swift/Web, потом winmd/gir |
| Макросы, C++ | средняя | документированное «нет»; шим-генератор |

---

## 11. Журнал фактчека (что было опровергнуто или исправлено)

| # | Исходное утверждение | Итог |
|---|---|---|
| 1 | jni 1.0.0 | jni 1.0.3 (2026-07-30); jnigen 1.0.0 (2026-09-03) |
| 2 | swift2objc нет на pub.dev | есть: 0.3.0; swiftgen 0.2.0 (оба 2026-09-08) |
| 3 | web_generator на pub.dev, поддерживает `.d.ts` | внутренний инструмент dart-lang/web, только WebIDL; `.d.ts` — отдельный неопубликованный `js_interop_gen` |
| 4 | flutter_rust_bridge 1.8.2 | 2.13.0 (2026-08-23), 2.14.0-beta.1 |
| 5 | uniffi 0.31.0 (январь 2026) | 0.32.0 (2026-06-30) |
| 6 | windows-bindgen 0.66 (май 2026) с `--minimal` | 0.66 — январь 2026; актуальная 0.100.0; `--minimal` не подтверждён |
| 7 | NativeScript перешёл на V8 (iOS) в 9.0 (2025) | в 7.0 (2020) |
| 8 | фильтрация метаданных через `.mdg` | `native-api-usage.json` |
| 9 | накладные NativeScript 1.5–2× | ≈3.5× по собственному бенчмарку |
| 10 | dart_native поддерживается | последний релиз декабрь 2022 |
| 11 | Objective Sharpie — закрытая утилита | dotnet global tool `Sharpie.Bind.Tool`, исходники не публичны |
| 12 | Djinni поддерживается, есть Dart | релиз 1.4.1 (2023), только C++/Java/ObjC |
| 13 | шаблон `plugin_ffi` | deprecated, актуален `package_ffi` (Flutter 3.38) |
| 14 | `dart compile exe` кросс-компилирует | только в Linux-цели |
| 15 | YAML — стандарт конфигов ffigen/jnigen | Dart-скрипты; YAML legacy |
| 16 | native assets stable в «Flutter 3.38 (сентябрь 2024)» | 3.38 = ноябрь 2025; build hooks включены по умолчанию в 3.38 |
| 17 | Roslyn-генератор rgen в разработке | RFC #21308 открыт, работ нет |

Непроверенные `[~]`: Kotlin Swift export на 2.4.x; статус Nitro после переезда репозитория; данные D7 по Sentry/Nutrient/Mapbox; jextract `--dump-includes` (известный флаг, первоисточник не открыт); Terra в Agora Flutter SDK.

---

## 12. Источники (первоисточники, открытые фактчеком)

- pub.dev API: ffigen, objective_c, swift2objc, swiftgen, jnigen, jni, pigeon, win32, winmd, dbus, hooks, code_assets, native_toolchain_c, native_toolchain_cmake, web, flutter_rust_bridge, dart_native, args, cli_completion, mason_logger, code_builder, dart_style, analyzer, build_runner, melos и др.
- dart-lang/native (README/CHANGELOG ffigen, jnigen, swiftgen, swift2objc); dart.dev/interop/*; dart.dev/tools/hooks; dart.dev/tools/dart-compile; dart.dev/tools/pub/workspaces
- docs.flutter.dev: developing-packages (package_ffi), release notes 3.35/3.38, breaking-changes (merged threads)
- dart-lang/web (web_generator README/package.json, PR #549, #554); dart-lang/http (cupertino_http ffigen.yaml, ok_http jnigen.yaml)
- halildurmus/win32 (packages/generator); canonical/dbus.dart; llamadonica/dart-gobject-bindings
- learn.microsoft.com: Objective Sharpie get-started / verify; AndroidMavenLibrary; CallConvSwift; MAUI Native Library Interop; dotnet/macios#21308; dotnet/runtimelab SwiftBindings (#2518)
- mono/CppSharp releases; NuGet ClangSharpPInvokeGenerator, Microsoft.Windows.CsWin32; microsoft/win32metadata
- docs.nativescript.org (metadata, generate-typings); blog.nativescript.org (V8 beta 2020; perf-metrics part 1); NativeScript/ios-metadata-generator, android-metadata-generator; npm @nativescript/*
- crates.io: uniffi, windows-bindgen, objc2; Uniffi-Dart/uniffi-dart; heremaps/gluecodium; cross-language-cpp/djinni-generator; swig.org/compat.html; bytecodealliance/wit-bindgen; madsmtm/objc2 header-translator README
- JetBrains/kotlin releases; touchlab/skie; npm karakum; swiftlang/swift-java; openjdk/jextract; AgoraIO-Extensions/terra; npm react-native
- roszkowski.dev/2026/swiftgen-jnigen/ (18 мая 2026); flutter/flutter#98084
