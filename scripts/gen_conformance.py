#!/usr/bin/env python3
# Copyright 2026 moonbit-toml contributors
# SPDX-License-Identifier: MIT
"""Generates MoonBit conformance tests from the vendored toml-test suite.

Reads toml-test-tests/{valid,invalid} and emits:
  - conformance_data.mbt : case sources and expected values as MoonBit literals
  - conformance_test.mbt : one MoonBit test per suite case

The expected tagged JSON of toml-test is converted into the library's own
`Value` model at generation time, so the generated tests compare parsed
documents structurally via `Value::equal` (order-insensitive tables, NaN
equality, datetime component equality).
"""

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SUITE = ROOT / "toml-test-tests"

DATETIME_TYPES = {"datetime", "datetime-local", "date-local", "time-local"}


def esc(s: str) -> str:
    """Escape a Python string as a MoonBit string literal body (no quotes)."""
    out = []
    for ch in s:
        o = ord(ch)
        if ch == '"':
            out.append('\\"')
        elif ch == "\\":
            out.append("\\\\")
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\t":
            out.append("\\t")
        elif ch == "\r":
            out.append("\\r")
        elif o < 0x20 or o == 0x7F:
            out.append("\\u%04X" % o)
        else:
            out.append(ch)
    return "".join(out)


def lit(s: str) -> str:
    return '"' + esc(s) + '"'


def float_lit(f: float) -> str:
    if f != f:  # nan
        return "(0.0 / 0.0)"
    if f == float("inf"):
        return "(1.0 / 0.0)"
    if f == float("-inf"):
        return "(-1.0 / 0.0)"
    r = repr(f)
    # MoonBit float literals need digits on both sides of the dot/exponent.
    if "e" in r or "E" in r:
        mantissa, _, exp = r.partition("e")
        if "." not in mantissa:
            mantissa += ".0"
        return mantissa + "e" + exp
    if "." not in r:
        r += ".0"
    return r


def parse_datetime(kind: str, value: str):
    """Parses a toml-test datetime value string into components."""
    date = time = None
    offset = 0
    has_offset = False
    rest = value
    if kind in ("datetime", "datetime-local", "date-local"):
        date_part, _, rest = rest.partition("T") if "T" in rest else rest.partition(" ")
        if kind == "date-local" or not rest:
            # pure date; also handles values that had no time at all
            if kind == "date-local":
                date_part = value
                rest = ""
        y, m, d = date_part.split("-")
        date = (int(y), int(m), int(d))
    if kind in ("datetime", "datetime-local", "time-local"):
        if rest:
            # optional offset tail
            offset_str = None
            for marker in ("Z", "z"):
                if rest.endswith(marker):
                    offset_str = "Z"
                    rest = rest[:-1]
                    break
            if offset_str is None:
                for i, ch in enumerate(rest):
                    if ch in "+-" and i > 0:
                        offset_str = rest[i:]
                        rest = rest[:i]
                        break
            t = rest
            frac = "0"
            if "." in t:
                t, _, frac = t.partition(".")
            parts = t.split(":")
            hour = int(parts[0])
            minute = int(parts[1]) if len(parts) > 1 else 0
            second = int(parts[2]) if len(parts) > 2 else 0
            # nanoseconds: same truncation/padding rule as the library
            frac_digits = (frac + "000000000")[:9]
            nanos = int(frac_digits)
            time = (hour, minute, second, nanos)
            if offset_str is not None and kind == "datetime":
                has_offset = True
                if offset_str in ("Z", "z"):
                    offset = 0
                else:
                    sign = -1 if offset_str[0] == "-" else 1
                    oh, om = offset_str[1:].split(":")
                    offset = sign * (int(oh) * 60 + int(om))
    return date, time, offset, has_offset


def json_to_value(tagged, indent=0):
    if isinstance(tagged, list):
        items = ", ".join(json_to_value(v, indent) for v in tagged)
        return f"Value::Array([{items}])"
    if isinstance(tagged, dict):
        if set(tagged.keys()) == {"type", "value"}:
            typ = tagged["type"]
            val = tagged["value"]
            if typ == "string":
                return f"Value::Str({lit(val)})"
            if typ == "integer":
                return f"Value::Int({int(val)}L)"
            if typ == "float":
                return f"Value::Float({float_lit(float(val))})"
            if typ == "bool":
                return f"Value::Bool({val})"
            if typ in DATETIME_TYPES:
                date, time, offset, has_offset = parse_datetime(typ, val)
                date_expr = "None"
                if date is not None:
                    date_expr = (
                        f"Some({{ year: {date[0]}, month: {date[1]}, day: {date[2]} }})"
                    )
                time_expr = "None"
                if time is not None:
                    time_expr = (
                        f"Some({{ hour: {time[0]}, minute: {time[1]}, "
                        f"second: {time[2]}, nanos: {time[3]} }})"
                    )
                return (
                    f"Value::Datetime({{ date: {date_expr}, time: {time_expr}, "
                    f"offset: {offset}, has_offset: {str(has_offset).lower()} }})"
                )
            raise ValueError(f"unknown type {typ}")
        entries = ", ".join(
            f"({lit(k)}, {json_to_value(v, indent)})"
            for k, v in tagged.items()
        )
        return f"Value::Table(Table::from_array([{entries}]))"
    raise ValueError(f"unexpected tagged value {tagged!r}")


def collect():
    valid = []
    skipped = []
    invalid = []
    valid_dir = SUITE / "valid"
    invalid_dir = SUITE / "invalid"
    for toml_path in sorted(invalid_dir.rglob("*.toml")):
        rel = toml_path.relative_to(invalid_dir).with_suffix("")
        name = rel.as_posix()
        try:
            src = toml_path.read_bytes().decode("utf-8")
        except UnicodeDecodeError:
            skipped.append(name)
            continue
        invalid.append((name, src))
    for toml_path in sorted(valid_dir.rglob("*.toml")):
        rel = toml_path.relative_to(valid_dir).with_suffix("")
        name = rel.as_posix()
        json_path = toml_path.with_suffix(".json")
        try:
            src = toml_path.read_bytes().decode("utf-8")
        except UnicodeDecodeError:
            skipped.append(name)
            continue
        if not json_path.exists():
            expected = {}
        else:
            expected = json.loads(json_path.read_text(encoding="utf-8"))
        valid.append((name, src, json_to_value(expected)))
    return valid, invalid, skipped


def fn_name(name: str) -> str:
    out = []
    for ch in name.lower():
        if ch.isalnum():
            out.append(ch)
        else:
            out.append("_")
    return "".join(out)


def main():
    valid, invalid, skipped = collect()
    print(
        f"collected: {len(valid)} valid, {len(invalid)} invalid, "
        f"{len(skipped)} skipped (non-UTF-8)"
    )

    data = []
    data.append(
        "// Generated by scripts/gen_conformance.py from toml-test v1.0.0.\n"
        "// DO NOT EDIT BY HAND; regenerate with `python scripts/gen_conformance.py`.\n"
    )
    data.append("")
    data.append("///|")
    data.append("pub let valid_cases : Array[(String, String, Value)] = [")
    for name, src, expected in valid:
        data.append(f"  // toml-test valid: {name}")
        data.append(f"  ({lit(name)}, {lit(src)}, {expected}),")
    data.append("]")
    data.append("")
    data.append("///|")
    data.append("pub let invalid_cases : Array[(String, String)] = [")
    for name, src in invalid:
        data.append(f"  ({lit(name)}, {lit(src)}),")
    data.append("]")
    data.append("")
    if skipped:
        data.append("// The following cases contain invalid UTF-8 and are covered by the")
        data.append("// byte-level CLI runner (scripts/run_toml_test.py) instead:")
        for name in skipped:
            data.append(f"//   {name}")
        data.append("")
    (ROOT / "conformance_data.mbt").write_text("\n".join(data), encoding="utf-8")

    tests = []
    tests.append(
        "// Generated by scripts/gen_conformance.py from toml-test v1.0.0.\n"
        "// DO NOT EDIT BY HAND; regenerate with `python scripts/gen_conformance.py`.\n"
    )
    tests.append("")
    for i, (name, _src, _expected) in enumerate(valid):
        tests.append("///|")
        tests.append(f'test "toml-test valid: {name}" {{')
        tests.append(f"  check_valid_case({i})")
        tests.append("}")
        tests.append("")
    for i, (name, _src) in enumerate(invalid):
        tests.append("///|")
        tests.append(f'test "toml-test invalid: {name}" {{')
        tests.append(f"  check_invalid_case({i})")
        tests.append("}")
        tests.append("")
    (ROOT / "conformance_test.mbt").write_text("\n".join(tests), encoding="utf-8")
    print(f"wrote conformance_data.mbt and conformance_test.mbt")

    runner = []
    runner.append("// Copyright 2026 moonbit-toml contributors")
    runner.append("//")
    runner.append("// SPDX-License-Identifier: MIT")
    runner.append("")
    runner.append("///|")
    runner.append("// Checks one generated valid case: parse and compare structurally")
    runner.append("// against the expected value derived from toml-test's tagged JSON.")
    runner.append("fn check_valid_case(i : Int) -> Unit raise {")
    runner.append("  let (name, src, expected) = valid_cases[i]")
    runner.append("  let doc = parse(src) catch {")
    runner.append('    err => fail("toml-test valid case \'\\{name}\' raised: \\{err.message()}")')
    runner.append("  }")
    runner.append("  let got : Value = Value::Table(doc)")
    runner.append("  if !got.equal(expected) {")
    runner.append(
        '    fail("toml-test valid case \'\\{name}\' mismatch\\n  got:      \\{encode_value(got)}\\n  expected: \\{encode_value(expected)}")'
    )
    runner.append("  }")
    runner.append("}")
    runner.append("")
    runner.append("///|")
    runner.append("// Checks one generated invalid case: the document must be rejected.")
    runner.append("fn check_invalid_case(i : Int) -> Unit raise {")
    runner.append("  let (name, src) = invalid_cases[i]")
    runner.append("  try parse(src) catch {")
    runner.append("    _ => return")
    runner.append("  } noraise {")
    runner.append('    _ => fail("toml-test invalid case \'\\{name}\' was accepted: \\{src}")')
    runner.append("  }")
    runner.append("}")
    runner.append("")
    (ROOT / "conformance_run_test.mbt").write_text("\n".join(runner), encoding="utf-8")
    print("wrote conformance_run_test.mbt")


if __name__ == "__main__":
    sys.exit(main())
