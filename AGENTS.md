# AGENTS.md

Guidance for AI coding agents (and humans) working in this repository.

## What this is

`sa2360/toml` — a TOML v1.0.0 parser and serializer for MoonBit with 100%
compliance against the official toml-test v1.0.0 suite. Published on
mooncakes.io as `sa2360/toml`.

## Commands

```bash
moon check                          # type check
moon test                           # full suite (unit + embedded toml-test conformance + doc examples)
moon test --target native           # same suite on the native backend
moon bench                          # parse / encode / to_json / json-parse benchmarks
moon fmt                            # format (CI enforces `moon fmt && git diff --exit-code`)
moon info                           # regenerate pkg.generated.mbti (CI enforces it is current)
moon build --target native cmd/toml2json
python scripts/run_toml_test.py     # official-protocol runner over the CLI (needs the CLI built)
python scripts/gen_conformance.py   # regenerate conformance tests from toml-test-tests/ (run `moon fmt` after)
moon publish                        # publish to mooncakes.io (bump version in moon.mod first)
```

## Layout

- `value.mbt` — `Value` / `Table` / `Datetime` model, accessors, `equal`, `Eq`/`Debug` impls
- `error.mbt` — `Position`, `ParseErrorData`, `ParseError` (+ exported `Show`)
- `scanner.mbt` — cursor with line/column tracking, character classes
- `strings.mbt` — the four string kinds, escape validation
- `numbers.mbt` — integers / floats / datetimes with range checks
- `parser.mbt` — document / table headers / keyvals / arrays / inline tables, table definition rules
- `encode.mbt` — serializer (documents and inline values)
- `json.mbt` — `Json` interop (`to_json`, `ToJson` impl)
- `cmd/toml2json` — native CLI emitting toml-test tagged JSON
- `cmd/example` — runnable demo
- `scripts/` — conformance generator + CLI runner (Python)
- `toml-test-tests/` — vendored official suite (Apache-2.0), do not edit

## Conventions and invariants

- **Never weaken conformance**: every change must keep `moon test` fully
  green (the embedded toml-test suite is the acceptance bar).
- **Round-trip is an invariant**: `parse(encode(t)) == t` and
  `parse_value(encode_value(v)) == v`. `property_test.mbt` enforces this
  with deterministic seeds; if you change the scanner, parser or encoder,
  also run a wider seed sweep locally before committing.
- Public trait impls must be written as `pub impl` or they will not appear
  in the generated `.mbti` interface (learned the hard way with `ToJson`).
- Keep the build warning-free (`moon test` on a clean `_build`).
- Tests live in `*_test.mbt` files; generated conformance data/tests
  (`conformance_*_test.mbt`) must not be edited by hand.
- `Double::to_string` is shortest-roundtrip and identical on wasm and
  native; the encoder relies on it (plus appending `.0` for integral
  floats and mapping `inf`/`nan`).
- Datetime policy: seconds are required in date-times, optional in
  time-only values; sub-second precision is truncated to nanoseconds;
  multi-line strings normalize CRLF to LF.
- Nesting depth: arrays and inline tables are bounded at
  `MAX_NESTING_DEPTH` (200). Any new recursive construct added to the
  parser must go through `enter_nesting`/`leave_nesting` as well.

## Measured dead ends

- Rewriting the scanner to snapshot the input into an `Array[Char]`
  (avoiding per-call UTF-16 decoding in `String::get_char`) was benchmarked
  at ~1.79 ms vs ~1.74 ms for the baseline on the 200-section bench doc —
  no gain; the snapshot allocation cancels out the cheaper reads. The
  parser's cost sits elsewhere (StringBuilder traffic, number/datetime
  conversion, map operations). Don't repeat this refactor expecting wins.

## Commit style

Small, milestone-scoped commits with descriptive messages; the hackathon
values a traceable history.
