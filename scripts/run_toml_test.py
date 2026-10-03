#!/usr/bin/env python3
# Copyright 2026 moonbit-toml contributors
# SPDX-License-Identifier: MIT
"""Runs the vendored toml-test suite against the compiled toml2json CLI.

This is an independent verification path (in addition to the embedded
`moon test` conformance suite): it drives the native binary over the
official toml-test protocol and compares tagged JSON *semantically* —
numbers by numeric value (NaN equals NaN, -0 equals 0), datetimes by
components (Z equals +00:00), strings/bools exactly.

Usage: python scripts/run_toml_test.py [path-to-toml2json]
"""

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SUITE = ROOT / "toml-test-tests"
EXE = (
    ROOT
    / "_build"
    / "native"
    / "debug"
    / "build"
    / "cmd"
    / "toml2json"
    / "toml2json.exe"
)

DATETIME_TYPES = {"datetime", "datetime-local", "date-local", "time-local"}


def norm_float(s: str):
    s = s.strip().lower()
    if s in ("nan", "+nan", "-nan"):
        return ("nan",)
    neg = s.startswith("-")
    body = s.lstrip("+-")
    if body == "inf":
        return ("-inf",) if neg else ("inf",)
    v = float(s)
    return ("f", v + 0.0)  # +0.0 normalizes -0.0


def parse_datetime(s: str):
    """Parses a canonical datetime value into comparable components."""
    date = None
    time = None
    offset = None
    if "T" in s or " " in s.strip():
        sep = "T" if "T" in s else " "
        date_part, _, time_part = s.partition(sep)
        y, m, d = date_part.split("-")
        date = (int(y), int(m), int(d))
    else:
        time_part = s
        if "-" in s and s.count("-") == 2 and ":" not in s:
            y, m, d = s.split("-")
            return (int(y), int(m), int(d), None, None)
    offset = None
    for marker in ("Z", "z"):
        if time_part.endswith(marker):
            offset = 0
            time_part = time_part[:-1]
    if offset is None and ("+" in time_part or "-" in time_part):
        idx = max(time_part.rfind("+"), time_part.rfind("-"))
        offset_str = time_part[idx:]
        time_part = time_part[:idx]
        sign = -1 if offset_str[0] == "-" else 1
        oh, om = offset_str[1:].split(":")
        offset = sign * (int(oh) * 60 + int(om))
    frac = "0"
    if "." in time_part:
        time_part, _, frac = time_part.partition(".")
    parts = time_part.split(":")
    hour = int(parts[0])
    minute = int(parts[1]) if len(parts) > 1 else 0
    second = int(parts[2]) if len(parts) > 2 else 0
    nanos = int((frac + "000000000")[:9])
    time = (hour, minute, second, nanos)
    return (None, time, offset)


def values_equal(got, expected, path="$"):
    """Compares tagged values (dicts/lists/leaves) semantically."""
    if isinstance(expected, dict) and "type" in expected and "value" in expected:
        if not isinstance(got, dict) or "type" not in got:
            return False, f"{path}: expected tagged value, got {got!r}"
        if got["type"] != expected["type"]:
            return (
                False,
                f"{path}: type {got['type']} != {expected['type']}",
            )
        gv = got["value"]
        ev = expected["value"]
        t = expected["type"]
        if t == "string":
            ok = gv == ev
        elif t == "integer":
            ok = int(gv) == int(ev)
        elif t == "float":
            ok = norm_float(gv) == norm_float(ev)
        elif t == "bool":
            ok = gv == ev
        elif t in DATETIME_TYPES:
            ok = parse_datetime(gv) == parse_datetime(ev)
        else:
            ok = False
        if not ok:
            return False, f"{path}: value {gv!r} != {ev!r} ({t})"
        return True, ""
    if isinstance(expected, dict) and isinstance(got, dict):
        if set(expected.keys()) != set(got.keys()):
            missing = set(expected.keys()) - set(got.keys())
            extra = set(got.keys()) - set(expected.keys())
            return False, f"{path}: keys differ (missing {missing}, extra {extra})"
        for k in expected:
            ok, why = values_equal(got[k], expected[k], f"{path}.{k}")
            if not ok:
                return False, why
        return True, ""
    if isinstance(expected, list) and isinstance(got, list):
        if len(expected) != len(got):
            return False, f"{path}: length {len(got)} != {len(expected)}"
        for i, (g, e) in enumerate(zip(got, expected)):
            ok, why = values_equal(g, e, f"{path}[{i}]")
            if not ok:
                return False, why
        return True, ""
    return False, f"{path}: structure mismatch {got!r} vs {expected!r}"


def main():
    exe = Path(sys.argv[1]) if len(sys.argv) > 1 else EXE
    if not exe.exists():
        print(f"binary not found: {exe}", file=sys.stderr)
        print("build with: moon build --target native cmd/toml2json", file=sys.stderr)
        return 2

    passed = 0
    failed = 0
    failures = []

    valid_dir = SUITE / "valid"
    for toml_path in sorted(valid_dir.rglob("*.toml")):
        rel = toml_path.relative_to(SUITE)
        json_path = toml_path.with_suffix(".json")
        expected = (
            json.loads(json_path.read_text(encoding="utf-8"))
            if json_path.exists()
            else {}
        )
        proc = subprocess.run(
            [str(exe), str(toml_path)], capture_output=True, text=True
        )
        if proc.returncode != 0:
            failed += 1
            failures.append((rel.as_posix(), f"exit {proc.returncode}: {proc.stderr.strip()}"))
            continue
        try:
            got = json.loads(proc.stdout)
        except json.JSONDecodeError as e:
            failed += 1
            failures.append((rel.as_posix(), f"invalid JSON output: {e}"))
            continue
        ok, why = values_equal(got, expected)
        if ok:
            passed += 1
        else:
            failed += 1
            failures.append((rel.as_posix(), why))

    invalid_dir = SUITE / "invalid"
    for toml_path in sorted(invalid_dir.rglob("*.toml")):
        rel = toml_path.relative_to(SUITE)
        proc = subprocess.run(
            [str(exe), str(toml_path)], capture_output=True, text=True
        )
        if proc.returncode != 0:
            passed += 1
        else:
            failed += 1
            failures.append((rel.as_posix(), "invalid document was accepted"))

    print(f"toml-test via CLI: {passed} passed, {failed} failed (of {passed + failed})")
    for name, why in failures[:20]:
        print(f"  FAIL {name}: {why}")
    if len(failures) > 20:
        print(f"  ... and {len(failures) - 20} more")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
