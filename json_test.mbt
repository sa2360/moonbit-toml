// Copyright 2026 moonbit-toml contributors
//
// SPDX-License-Identifier: MIT

///|
test "to_json primitives" {
  @debug.assert_eq(Value::Int(42L).to_json().stringify(), "42")
  // 64-bit integers keep full precision through the textual representation.
  @debug.assert_eq(
    Value::Int(9223372036854775807L).to_json().stringify(),
    "9223372036854775807",
  )
  @debug.assert_eq(
    Value::Int(-9223372036854775808L).to_json().stringify(),
    "-9223372036854775808",
  )
  @debug.assert_eq(Value::Float(2.5).to_json().stringify(), "2.5")
  @debug.assert_eq(Value::Bool(true).to_json().stringify(), "true")
  @debug.assert_eq(Value::Str("hi").to_json().stringify(), "\"hi\"")
  @debug.assert_eq(Value::Float(1.0 / 0.0).to_json().stringify(), "\"inf\"")
  @debug.assert_eq(Value::Float(-1.0 / 0.0).to_json().stringify(), "\"-inf\"")
  @debug.assert_eq(Value::Float(0.0 / 0.0).to_json().stringify(), "\"nan\"")
}

///|
test "to_json datetime becomes canonical string" {
  let doc = must_parse("a = 1979-05-27T07:32:00Z\nb = 1979-05-27\nc = 07:32:00")
  @debug.assert_eq(
    Value::Datetime(doc.get_datetime("a").unwrap()).to_json().stringify(),
    "\"1979-05-27T07:32:00Z\"",
  )
  @debug.assert_eq(
    Value::Datetime(doc.get_datetime("b").unwrap()).to_json().stringify(),
    "\"1979-05-27\"",
  )
  @debug.assert_eq(
    Value::Datetime(doc.get_datetime("c").unwrap()).to_json().stringify(),
    "\"07:32:00\"",
  )
}

///|
test "to_json arrays and objects parse back" {
  let doc = must_parse(
    "nums = [1, 2, 3]\nnested = [[1], [2]]\n[owner]\nname = \"Tom\"\nage = 30",
  )
  let json = Value::Table(doc).to_json()
  let back = @json.parse(json.stringify())
  let obj = match back {
    Object(m) => m
    _ => abort("expected object")
  }
  @debug.assert_eq(obj.contains("nums"), true)
  @debug.assert_eq(obj.contains("owner"), true)
  let nums = match obj["nums"] {
    Array(items) => items
    _ => abort("expected array")
  }
  @debug.assert_eq(nums.length(), 3)
  let first = match nums[0] {
    Number(n, ..) => n
    _ => abort("expected number")
  }
  @debug.assert_eq(first, 1.0)
  let owner = match obj["owner"] {
    Object(m) => m
    _ => abort("expected object")
  }
  let name = match owner["name"] {
    String(s) => s
    _ => abort("expected string")
  }
  @debug.assert_eq(name, "Tom")
  let age = match owner["age"] {
    Number(n, ..) => n
    _ => abort("expected number")
  }
  @debug.assert_eq(age, 30.0)
}

///|
test "to_json via ToJson trait" {
  // The trait impl lets Value flow into @json helpers directly.
  let j = @json.to_json(Value::Array([Value::Int(1L), Value::Str("x")]))
  @debug.assert_eq(j.stringify(), "[1,\"x\"]")
}

///|
test "from_json primitives and conventions" {
  @debug.assert_eq(Value::from_json(@json.parse("42")).as_int(), Some(42L))
  // Integral doubles become integers.
  @debug.assert_eq(Value::from_json(@json.parse("1.0")).as_int(), Some(1L))
  @debug.assert_eq(Value::from_json(@json.parse("-3.0")).as_int(), Some(-3L))
  @debug.assert_eq(Value::from_json(@json.parse("2.5")).as_double(), Some(2.5))
  @debug.assert_eq(Value::from_json(@json.parse("true")).as_bool(), Some(true))
  @debug.assert_eq(Value::from_json(@json.parse("\"hi\"")).as_str(), Some("hi"))
  // Non-finite doubles are representable in TOML.
  @debug.assert_eq(
    Value::from_json(@json.parse("1e400")).as_double(),
    Some(1.0 / 0.0),
  )
}

///|
test "from_json rejects null" {
  let j = @json.parse("null")
  try Value::from_json(j) catch {
    JsonNull => return
  } noraise {
    _ => fail("expected JsonNull")
  }
}

///|
test "from_json nested structures" {
  let v = Value::from_json(
    @json.parse("{\"server\": {\"port\": 8080, \"tags\": [\"a\"]}}"),
  ) catch {
    _ => fail("unexpected error")
  }
  let t = v.as_table().unwrap()
  @debug.assert_eq(t.get_path("server.port"), Some(Value::Int(8080L)))
  @debug.assert_eq(t.get_path("server.tags.0"), None) // paths do not index arrays
  @debug.assert_eq(encode_value(v), "{server = {port = 8080, tags = [\"a\"]}}")
}

///|
test "json to toml to json round trip (json-safe document)" {
  // JSON cannot distinguish 2 from 2.0, so by convention integral JSON
  // numbers become integers; use non-integral floats here.
  let doc = must_parse("a = 1\nb = \"x\"\nc = [1.5, true]\n[t]\nd = 2.25")
  let circle = Value::from_json(@json.parse(Value::Table(doc).to_json_string())) catch {
    _ => fail("unexpected error")
  }
  @debug.assert_eq(circle.equal(Value::Table(doc)), true)
}
