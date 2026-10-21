#!/usr/bin/env python3
"""Fail unless both packages pass `dart pub publish --dry-run` with no warnings.

P8-3. This does not publish, tag, or upload a release. The bindsmith
archive must omit the test goldens that import jni, objective_c, and
bindsmith_runtime; those cannot be declared dependencies of this package.
"""

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACKAGES = ("packages/bindsmith", "packages/bindsmith_runtime")

# Tracked Dart files whose imports the publisher rejects.
OMITTED = (
    "test/drivers/goldens/greeter_jvm.g.dart",
    "test/drivers/goldens/ktgreeter_jvm.g.dart",
    "test/emit/goldens/sdk.g.dart",
    "test/emit/goldens/sdk_io.g.dart",
    "test/emit/goldens/sdk_web.g.dart",
)


def dry_run(package: str) -> tuple[int, str]:
    proc = subprocess.run(
        ["dart", "pub", "publish", "--dry-run"],
        cwd=ROOT / package,
        text=True,
        capture_output=True,
        stdin=subprocess.DEVNULL,
        check=False,
    )
    return proc.returncode, proc.stdout + proc.stderr


def main() -> int:
    failed = False
    for package in PACKAGES:
        code, out = dry_run(package)
        name = package.rsplit("/", 1)[-1]
        if code != 0 or "Package has 0 warnings." not in out:
            print(f"{name}: publish dry-run is not clean (exit {code})", file=sys.stderr)
            print(out, file=sys.stderr)
            failed = True
            continue
        if package == "packages/bindsmith":
            leaked = [path for path in OMITTED if Path(path).name in out]
            if leaked:
                print(f"{name}: archive still lists {leaked}", file=sys.stderr)
                failed = True
                continue
        print(f"{name}: 0 warnings")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
