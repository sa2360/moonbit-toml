// Copyright 2026 moonbit-toml contributors
//
// SPDX-License-Identifier: MIT

// Property-style tests: randomly generated TOML documents must survive the
// parse -> encode -> parse round trip with a structurally equal result.
// The generator is a deterministic LCG, so the suite is stable across runs
// while still exploring a wide space of documents.

///|
priv struct Rng {
  mut state : UInt64
}

///|
fn Rng::next(self : Rng) -> UInt64 {
  // xorshift64*
  let mut x = self.state
  x = x ^ (x >> 12)
  x = x ^ (x << 25)
  x = x ^ (x >> 27)
  self.state = x
  x * 2685821657736338717UL
}

///|
fn Rng::make(seed : UInt64) -> Rng {
  { state: seed | 1UL, }
}

///|
/// Uniform integer in [0, n).
fn Rng::below(self : Rng, n : Int) -> Int {
  (self.next() % n.to_uint64()).to_int()
}

///|
fn Rng::pick(self : Rng, chars : String) -> Char {
  let idx = self.below(chars.length())
  match chars.get_char(idx) {
    Some(c) => c
    None => 'x'
  }
}

///|
let random_word_chars = "abcdefghijklmnopqrstuvwxyzABCZ_0123456789"

///|
let random_string_chars = "abc XYZ 09 -=[]{};:,.<>/?!@#%^&*()_\t\\\"'\né漢😀"

///|
fn Rng::bare_key(self : Rng) -> String {
  let len = 1 + self.below(8)
  let sb = StringBuilder::StringBuilder()
  for _i in 0..<len {
    sb.write_char(self.pick(random_word_chars))
  }
  // Avoid keys that would look like numbers/dates/booleans when re-parsed.
  let k = sb.to_string()
  let first = k.get_char(0).unwrap_or('x')
  if first.is_ascii_digit() ||
    first == 't' ||
    first == 'f' ||
    first == 'i' ||
    first == 'n' {
    "k_" + k
  } else {
    k
  }
}

///|
fn Rng::any_key(self : Rng) -> String {
  if self.below(3) == 0 {
    // A quoted key with tricky characters.
    let specials = [
      "a.b", "", "\"q\"", "sp ace", "tab\tkey", "1979-05-27", "日本語",
    ]
    specials[self.below(specials.length())]
  } else {
    self.bare_key()
  }
}

///|
fn Rng::random_string(self : Rng) -> Value {
  let len = self.below(20)
  let sb = StringBuilder::StringBuilder()
  for _i in 0..<len {
    sb.write_char(self.pick(random_string_chars))
  }
  Value::Str(sb.to_string())
}

///|
fn Rng::random_int(self : Rng) -> Value {
  // Generate i64 values across interesting magnitudes.
  let v = match self.below(4) {
    0 => Int64::from_int(self.below(1000) - 500)
    1 => Int64::from_int(self.below(2000000000) - 1000000000)
    2 => (self.next() >> 1).reinterpret_as_int64()
    _ =>
      -9223372036854775808L +
      (self.next() % 1000000000000000UL).reinterpret_as_int64()
  }
  Value::Int(v)
}

///|
fn Rng::random_float(self : Rng) -> Value {
  let v = match self.below(5) {
    0 => (self.next() % 10000UL).to_double() / 8.0
    1 => -(self.next() % 100000UL).to_double() / 1024.0
    2 => (self.next() % 1000UL).to_double() * 1.0e10
    3 => (self.next() % 1000UL).to_double() * 1.0e-10
    _ => self.next().reinterpret_as_int64().to_double() / 3.0
  }
  Value::Float(v)
}

///|
fn Rng::random_datetime(self : Rng) -> Value {
  let year = 1000 + self.below(9000)
  let month = 1 + self.below(12)
  let day = 1 + self.below(28)
  let hour = self.below(24)
  let minute = self.below(60)
  let second = self.below(60)
  let nanos = self.below(1000000000)
  let date : @toml.DateParts? = Some({ year, month, day, })
  let time : @toml.TimeParts? = Some({ hour, minute, second, nanos, })
  match self.below(4) {
    0 => {
      let offset = self.below(24 * 60) - 12 * 60
      Value::Datetime({ date, time, offset, has_offset: true, })
    }
    1 => Value::Datetime({ date, time, offset: 0, has_offset: false, })
    2 => Value::Datetime({ date, time: None, offset: 0, has_offset: false, })
    _ => Value::Datetime({ date: None, time, offset: 0, has_offset: false, })
  }
}

///|
fn Rng::random_scalar(self : Rng) -> Value {
  match self.below(6) {
    0 => self.random_string()
    1 => self.random_int()
    2 => self.random_float()
    3 => Value::Bool(self.below(2) == 0)
    4 => self.random_datetime()
    _ => self.random_string()
  }
}

///|
/// Generates a random value with bounded nesting depth.
fn Rng::random_value(self : Rng, depth : Int) -> Value {
  if depth <= 0 || self.below(3) == 0 {
    return self.random_scalar()
  }
  match self.below(3) {
    0 => {
      // Array of mixed values.
      let len = self.below(5)
      let items : Array[Value] = []
      for _i in 0..<len {
        items.push(self.random_value(depth - 1))
      }
      Value::Array(items)
    }
    1 => {
      // Inline table (no arrays of tables inside inline tables).
      let t = Table::new()
      let len = self.below(4)
      for _i in 0..<len {
        t.set(self.any_key(), self.random_value(depth - 1))
      }
      Value::Table(t)
    }
    _ => self.random_scalar()
  }
}

///|
/// A table is "array friendly" when it contains no arrays of tables and no
/// inline tables nested in arrays, so encode() can emit it as [headers].
fn Rng::random_document(self : Rng) -> Table {
  let root = Table::new()
  let count = 1 + self.below(6)
  for _i in 0..<count {
    match self.below(4) {
      0 =>
        // Simple value.
        root.set(self.any_key(), self.random_value(1))
      1 => {
        // A nested table with scalars only.
        let t = Table::new()
        for _j in 0..<(1 + self.below(4)) {
          t.set(self.any_key(), self.random_scalar())
        }
        root.set(self.any_key(), Value::Table(t))
      }
      2 => {
        // An array of scalar values.
        let len = self.below(4)
        let items : Array[Value] = []
        for _j in 0..<len {
          items.push(self.random_scalar())
        }
        root.set(self.any_key(), Value::Array(items))
      }
      _ => {
        // An array of small tables (becomes [[array of tables]]).
        let len = 1 + self.below(3)
        let items : Array[Value] = []
        for _j in 0..<len {
          let t = Table::new()
          for _k in 0..<(1 + self.below(3)) {
            t.set(self.any_key(), self.random_scalar())
          }
          items.push(Value::Table(t))
        }
        root.set(self.any_key(), Value::Array(items))
      }
    }
  }
  root
}

///|
test "property: random documents round trip (seed sweep)" {
  for seed in [1UL, 7UL, 42UL, 1337UL, 20261003UL, 999999937UL, 1234567891011UL] {
    let rng = Rng::make(seed)
    for _round in 0..<40 {
      let doc = rng.random_document()
      let encoded = encode(doc)
      let reparsed = parse(encoded) catch {
        err =>
          fail(
            "seed \{seed}: re-parse failed: \{err.message()}\nencoded:\n\{encoded}",
          )
      }
      if !Value::Table(reparsed).equal(Value::Table(doc)) {
        let original = encode(doc)
        fail(
          "seed \{seed}: round trip mismatch\nencoded:\n\{encoded}\nre-encoded:\n\{original}",
        )
      }
    }
  }
}

///|
test "property: random values round trip inline (seed sweep)" {
  for seed in [3UL, 11UL, 777UL, 271828182UL] {
    let rng = Rng::make(seed)
    for _round in 0..<60 {
      let v = rng.random_value(3)
      let inline = encode_value(v)
      let back = parse_value(inline) catch {
        err =>
          fail(
            "seed \{seed}: inline value '\{inline}' failed to parse: \{err.message()}",
          )
      }
      if !back.equal(v) {
        fail("seed \{seed}: inline round trip mismatch for '\{inline}'")
      }
    }
  }
}

///|
test "property: random strings survive basic string quoting" {
  for seed in [5UL, 99UL, 424242UL] {
    let rng = Rng::make(seed)
    for _round in 0..<80 {
      let v = rng.random_string()
      let inline = encode_value(v)
      let back = parse_value(inline) catch {
        err =>
          fail(
            "seed \{seed}: string '\{inline}' failed to parse: \{err.message()}",
          )
      }
      @debug.assert_eq(back.as_str(), v.as_str())
    }
  }
}
