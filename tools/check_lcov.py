"""Checks LCOV line coverage against a minimum percentage."""

from __future__ import annotations

import argparse
from pathlib import Path


def coverage_percentage(lcov_path: Path) -> float:
    """Calculates line coverage from an LCOV file."""
    found = 0
    hit = 0
    for line in lcov_path.read_text(encoding="utf-8").splitlines():
        if line.startswith("LF:"):
            found += int(line.removeprefix("LF:"))
        elif line.startswith("LH:"):
            hit += int(line.removeprefix("LH:"))
    if found == 0:
        return 0.0
    return (hit / found) * 100


def main() -> int:
    """Runs the command-line coverage check."""
    parser = argparse.ArgumentParser()
    parser.add_argument("lcov_path", type=Path)
    parser.add_argument("minimum", type=float)
    args = parser.parse_args()

    percentage = coverage_percentage(args.lcov_path)
    print(f"Line coverage: {percentage:.2f}%")
    if percentage < args.minimum:
        print(f"Coverage is below required minimum {args.minimum:.2f}%.")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
