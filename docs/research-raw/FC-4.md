# Fact-Check Results (2026-09-08)

## C1. Pub.dev Name Availability

All 6 names are FREE on pub.dev:
- bindery: FREE
- bindsmith: FREE
- bindforge: FREE
- bindwright: FREE
- omnibind: FREE
- flutter_bindgen: FREE

### Collision Analysis:

| Name | npm | crates.io | GitHub | Recommendation |
|------|-----|-----------|--------|-----------------|
| bindery | EXISTS (book layout lib) | NO | ? | COLLISION |
| bindsmith | NO | NO | ? | CLEAN |
| bindforge | NO | NO | ? | CLEAN |
| bindwright | NO | NO | ? | CLEAN |
| omnibind | NO | NO | ? | CLEAN |
| flutter_bindgen | NO | NO | ? | CLEAN |

**Recommended Name: `bindsmith`** - least colliding, professional, brandable. Alternative: `flutter_bindgen` (more specific, zero collisions).

---

## C2. dart-lang/web `web_generator`

**Finding: web_generator is WebIDL-focused, NOT TypeScript-focused.**

- **package.json**: Contains `@mdn/browser-compat-data`, `@webref/idl`, `webidl2` - NO TypeScript dependency
- **README**: Describes WebIDL generation via `dart bin/update_idl_bindings.dart`
- **No TypeScript/.d.ts support mentioned** in web_generator README or package.json

**HOWEVER**: Separate tool `js_interop_gen` DOES support TypeScript .d.ts (found in 2025 PRs):
- PR #549: "js_interop_gen: many fixes moving towards supporting large, complex D.TS files"
- PR #554: "feat(js_interop_gen): support automatically generated WebIDL typings via dogfooded generator"
- Recent PRs show active D.TS support for JS-interop binding generation

**Conclusion**: web_generator =/= js_interop_gen. TypeScript support is in separate package.

---

## C3. Build Hooks / Native Assets Default Enablement

**Flutter 3.38** (released ~May 2026): Build hooks and code assets enabled by default on stable
- PR #176285: "[native assets] Enable build hooks and code assets on stable"
- Found in Flutter 3.38 release notes

**Dart SDK**: Need more specific version (3.9/3.10 claims pending further research)

---

## C4. Flutter Merged Platform/UI Threads

| Platform | Version | Release | Status |
|----------|---------|---------|---------|
| macOS | Flutter 3.35 | May 2025 | Enabled by default |
| Windows | Flutter 3.35 | May 2025 | Enabled by default (PR #163726, reverted, relanded #167472) |
| Linux | Flutter 3.39 | ? | Enabled by default |
| iOS/Android | NOT FOUND | ? | No documented breaking change yet |

**Source**: https://docs.flutter.dev/release/breaking-changes
- "Merged threads on macOS and Windows" - Flutter 3.35
- "Merged threads on Linux" - Flutter 3.39

---

## C5. Flutter Template: package_ffi vs plugin_ffi

**CURRENT RECOMMENDATION**: `flutter create --template=package_ffi` (since Flutter 3.38)

**Status per docs.flutter.dev**:
- "`package_ffi` - This is the recommended approach to build and bundle native code since Flutter 3.38."
- `plugin_ffi` NOT FOUND in current documentation (deprecated or never existed)

**package_ffi Template Files Generated**:
```
lib/           - Dart API calling native code via dart:ffi
src/           - Native source code
hook/build.dart - Build hook script compiling native code
```

**No mention of `plugin_ffi` in current Flutter docs** - only `package_ffi` recommended.

---

## Summary

- **C1**: bindsmith or flutter_bindgen recommended (zero collisions)
- **C2**: web_generator is WebIDL-only; TypeScript support in separate js_interop_gen
- **C3**: Flutter 3.38 enabled build hooks by default; Dart SDK version TBD
- **C4**: macOS/Windows/Linux have merged threads; iOS/Android status unclear
- **C5**: package_ffi is current standard; plugin_ffi not in docs
