// Copyright 2026 moonbit-toml contributors
//
// SPDX-License-Identifier: MIT

///|
// Checks one generated valid case: parse and compare structurally
// against the expected value derived from toml-test's tagged JSON,
// then re-encode and re-parse to verify the round trip.
fn check_valid_case(i : Int) -> Unit raise {
  let (name, src, expected) = valid_cases[i]
  let doc = parse(src) catch {
    err => fail("toml-test valid case '\{name}' raised: \{err.message()}")
  }
  let got : Value = Value::Table(doc)
  if !got.equal(expected) {
    fail(
      "toml-test valid case '\{name}' mismatch\n  got:      \{encode_value(got)}\n  expected: \{encode_value(expected)}",
    )
  }
  // Round trip: encode the parsed document, parse it again and
  // require an equal result.
  let encoded = encode(doc)
  let reparsed : Value = Value::Table(
    parse(encoded) catch {
      err =>
        fail(
          "toml-test valid case '\{name}' failed to round trip: \{err.message()}\n  encoded: \{encoded}",
        )
    },
  )
  if !reparsed.equal(got) {
    fail(
      "toml-test valid case '\{name}' round trip mismatch\n  encoded: \{encoded}\n  got:      \{encode_value(got)}\n  reparsed: \{encode_value(reparsed)}",
    )
  }
}

///|
// Checks one generated invalid case: the document must be rejected.
fn check_invalid_case(i : Int) -> Unit raise {
  let (name, src) = invalid_cases[i]
  try parse(src) catch {
    _ => return
  } noraise {
    _ => fail("toml-test invalid case '\{name}' was accepted: \{src}")
  }
}
