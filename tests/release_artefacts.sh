#!/bin/sh
# P8-3: the release artefacts exist and the formula / workflow parse.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

need() {
  if [ ! -f "$1" ]; then
    echo "release_artefacts: missing $1" >&2
    exit 1
  fi
}

need LICENSE
need packages/bindsmith/LICENSE
need packages/bindsmith/CHANGELOG.md
need packages/bindsmith_runtime/CHANGELOG.md
need packages/bindsmith/README.md
need packages/bindsmith_runtime/README.md
need .github/ISSUE_TEMPLATE/bug.yml
need scripts/formula.sh
need .github/workflows/release.yml

if ! grep -q 'bindsmith doctor --json' .github/ISSUE_TEMPLATE/bug.yml; then
  echo "release_artefacts: bug template does not ask for doctor --json" >&2
  exit 1
fi

if ! grep -q 'dart compile exe' .github/workflows/release.yml; then
  echo "release_artefacts: release.yml does not compile an exe" >&2
  exit 1
fi

if command -v ruby >/dev/null 2>&1; then
  ruby -ryaml -e "YAML.load_file(ARGV[0])" .github/workflows/release.yml
  ruby -ryaml -e "YAML.load_file(ARGV[0])" .github/ISSUE_TEMPLATE/bug.yml
fi

zeros="$(awk 'BEGIN { while (n++ < 64) printf "0" }')"
out="$(sh scripts/formula.sh 0.1.0 "$zeros")"
case "$out" in
  *"class Bindsmith < Formula"*) ;;
  *) echo "release_artefacts: formula.sh did not emit a Formula" >&2; exit 1 ;;
esac
