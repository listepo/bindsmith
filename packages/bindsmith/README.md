# bindsmith

One `bindsmith.yaml`, six Flutter platforms. Generates Dart bindings for native
APIs by driving ffigen, swiftgen, jnigen, winmd, and dart-dbus, plus a
TypeScript `.d.ts` driver for Web — through a unified IR with fixup passes and
review markers.

```bash
dart pub global activate bindsmith
bindsmith doctor --json
bindsmith generate
```

Docs: https://github.com/listepo/bindsmith#readme
