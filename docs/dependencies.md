# Dependencies and the lock


A platform that declares dependencies gets them resolved and pinned:

```yaml
platforms:
  android:
    driver: jvm
    deps:
      maven: ["androidx.biometric:biometric:1.2.0-alpha05"]
      repositories:
        - https://dl.google.com/dl/android/maven2/
        - https://repo1.maven.org/maven2/
```

`bindsmith resolve` follows the transitive graph, downloads into `.dart_tool/bindsmith/`, and writes `bindsmith.lock` with the sha256 of every file it landed on. Commit that file. The download cache mirrors a repository's own layout, so it *is* one, and every later run resolves from it — `--offline` makes that a requirement rather than a hope.

A repository URL is `https://` or a `file://` directory, the same two things Gradle accepts; plain `http://` is refused, because an artifact fetched over it is one that whoever sits between you and the mirror chose. A version range, `LATEST` and `-SNAPSHOT` are refused for the same kind of reason: each makes one coordinate mean different bytes on a different day, and there would be nothing honest to write in the lock.
