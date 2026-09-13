#!/bin/sh
# Fetch the SQLite amalgamation into third_party/sqlite/ (not committed).
# Pin: sqlite-amalgamation-3500400 (3.50.4).
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
out="$root/third_party/sqlite"
url="https://www.sqlite.org/2025/sqlite-amalgamation-3500400.zip"
if [ -f "$out/sqlite3.c" ] && [ -f "$out/sqlite3.h" ]; then
  echo "sqlite amalgamation already present"
  exit 0
fi
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
echo "downloading $url"
curl -fsSL "$url" -o "$tmp/sqlite.zip"
mkdir -p "$out"
unzip -o -j "$tmp/sqlite.zip" '*/sqlite3.c' '*/sqlite3.h' -d "$out"
test -f "$out/sqlite3.c"
test -f "$out/sqlite3.h"
echo "wrote $out/sqlite3.c and sqlite3.h"
