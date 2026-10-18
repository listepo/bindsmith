#!/usr/bin/env python3
"""Smoke test for P8-4: a natively built CLI must finish `generate`.

ffigen looks for a `dart` executable next to the running binary to format its
output and, in a `dart build cli` binary, used to search the filesystem root
forever. This builds the CLI natively, runs `generate` on the C fixture in a
scratch project and fails if it does not finish within the timeout.

Needs a Dart SDK on PATH, libclang (Xcode or libclang-dev) and a C compiler.
Usage: python3 scripts/native_generate_smoke.py [--timeout SECONDS]
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONFIG = """name: smoke_bind
output: lib/src/generated
facade: {{library: lib/smoke_bind.dart}}
platforms:
  {platform}:
    driver: c
    headers: [c/geometry.h]
"""


def host_platform() -> str:
    return {"darwin": "macos", "win32": "windows"}.get(sys.platform, "linux")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--timeout", type=int, default=180)
    timeout = ap.parse_args().timeout
    dart = shutil.which("dart")
    if not dart:
        print("dart not found on PATH", file=sys.stderr)
        return 2
    with tempfile.TemporaryDirectory(prefix="bindsmith_smoke_") as tmp:
        tmp = Path(tmp)
        bundle = tmp / "bundle"
        subprocess.run(
            [dart, "build", "cli", "-t", "bin/bindsmith.dart", "-o", str(bundle)],
            cwd=ROOT / "packages" / "bindsmith",
            check=True,
        )
        project = tmp / "project"
        (project / "c").mkdir(parents=True)
        shutil.copy(ROOT / "fixtures/c/geometry/geometry.h", project / "c")
        (project / "pubspec.yaml").write_text(
            "name: smoke_bind\nenvironment: {sdk: ^3.13.0}\n"
        )
        (project / "bindsmith.yaml").write_text(
            CONFIG.format(platform=host_platform())
        )
        # A clean PATH with no `dart`: the native binary must not need one.
        env = dict(os.environ, PATH=os.pathsep.join(["/usr/bin", "/bin"]))
        try:
            result = subprocess.run(
                [str(bundle / "bundle" / "bin" / "bindsmith"), "generate"],
                cwd=project,
                env=env,
                timeout=timeout,
                capture_output=True,
                text=True,
            )
        except subprocess.TimeoutExpired:
            print(f"FAIL: native generate did not finish in {timeout}s (P8-4)")
            return 1
        if result.returncode != 0:
            print(result.stdout + result.stderr)
            print(f"FAIL: native generate exited {result.returncode}")
            return 1
        out = project / "lib/src/generated"
        if not any(out.rglob("*.g.dart")):
            print("FAIL: no binding was written")
            return 1
        print("OK: native generate finished and wrote a binding")
        return 0


if __name__ == "__main__":
    sys.exit(main())
