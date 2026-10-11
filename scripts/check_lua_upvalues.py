#!/usr/bin/env python3
"""Check compiled Lua closures against WoW's 60-upvalue limit.

Modern luac accepts more upvalues than the client. Exclude its synthetic _ENV
upvalue when counting; this supplements syntax checks, not in-game validation.
"""

import argparse
from pathlib import Path
import re
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="+", type=Path)
    parser.add_argument("--luac", default="luac")
    args = parser.parse_args()
    files = set()
    for path in args.paths:
        if not path.exists():
            parser.error(f"Missing path: {path}")
        files.update(path.rglob("*.lua") if path.is_dir() else [path])
    if not files:
        parser.error("No Lua files found")
    failures = []
    maximum = 0
    for path in sorted(files):
        result = subprocess.run([args.luac, "-p", "-l", "-l", str(path)], capture_output=True, text=True)
        if result.returncode:
            failures.append(result.stderr.strip())
            continue
        for chunk in re.split(r"\n(?=(?:main|function) <)", result.stdout):
            match = re.search(r"\nupvalues \((\d+)\)[^\n]*:\n([\s\S]*)", chunk)
            if not match:
                continue
            count = int(match[1]) - len(re.findall(r"^\s*\d+\s+_ENV\s", match[2], re.MULTILINE))
            maximum = max(maximum, count)
            if count > 60:
                failures.append(f"{chunk.splitlines()[0]}: {count} upvalues (limit 60)")
    for failure in failures:
        print(failure)
    print(f"Upvalue audit: {len(files)} files, maximum {maximum}, {len(failures)} failures")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
