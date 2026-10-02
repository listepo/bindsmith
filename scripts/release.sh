#!/usr/bin/env bash
# The one place a bindsmith release version is decided (bump.yml runs it).
#
#   scripts/release.sh [patch|minor|major] [--dry-run|--local]
#
#   (none)     start the Bump workflow (gh workflow run bump.yml -f level=...)
#   --dry-run  print the version that would be released; change nothing
#   --local    make the version commit and stop (what bump.yml runs)
#
# The version in packages/bindsmith/pubspec.yaml is the version to release; it
# is raised (scripts/bump_version.dart) only when `v<version>` is already
# tagged, and both pubspecs move together. Never pushes, never tags: bump.yml
# lands the commit through a pull request with green checks, then tags the
# commit that landed on main.
set -euo pipefail

cd "$(dirname "$0")/.."

level="${1:-patch}"
mode="${2:-}"
case "$level" in
  patch | minor | major) ;;
  *) echo "level must be patch, minor or major (got '$level')" >&2; exit 2 ;;
esac
case "$mode" in
  "")
    gh workflow run bump.yml -f level="$level"
    echo "Bump and release ($level) started: gh run list --workflow bump.yml"
    exit 0 ;;
  --dry-run | --local) ;;
  *) echo "unknown option: $mode" >&2; exit 2 ;;
esac

pubspecs=(packages/bindsmith/pubspec.yaml packages/bindsmith_runtime/pubspec.yaml)
current="$(awk '/^version: / { print $2; exit }' "${pubspecs[0]}")"
[ -n "$current" ] || { echo "no version in ${pubspecs[0]}" >&2; exit 1; }

version="$current"
if git rev-parse -q --verify "refs/tags/v$current" >/dev/null; then
  version="$(dart run scripts/bump_version.dart --bump "$level" --current "$current")"
fi

echo "current $current -> release v$version"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "version=$version" >>"$GITHUB_OUTPUT"
fi

if [ "$mode" = "--dry-run" ]; then
  echo "dry run: nothing written"
  exit 0
fi
if [ "$version" = "$current" ]; then
  echo "local: v$version is not tagged yet; nothing to commit"
  exit 0
fi

for f in "${pubspecs[@]}"; do
  sed -i.bak -E "s/^version: .*/version: $version/" "$f" && rm -f "$f.bak"
done
git add "${pubspecs[@]}"
git commit --quiet -m "chore(release): v$version"
echo "local: version commit made, not pushed, not tagged"
