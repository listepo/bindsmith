# ADR-0003: Configuration is YAML with a JSON Schema, plus a Dart escape hatch

Status: accepted (2026-09-08)

Users write one `bindsmith.yaml` (validated against `bindsmith.schema.json`, so editors autocomplete and CI fails early with a path to the wrong key). Everything that is data — inputs, include lists, fixups, dependency coordinates, verify policy — lives there. Behaviour that cannot be data (custom visitors, marshalling for one odd type) goes into an optional `tool/bindsmith.dart` script that receives the parsed config and may register extra passes. The upstream generators moved from YAML to Dart scripts in 2026; we keep YAML for the user and translate to their Dart APIs ourselves so a config diff stays reviewable by non-Dart teammates.
