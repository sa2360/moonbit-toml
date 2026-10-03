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
  let obj = back.as_object().unwrap()
  @debug.assert_eq(obj.contains("nums"), true)
  @debug.assert_eq(obj.contains("owner"), true)
  let nums = obj["nums"].as_array().unwrap()
  @debug.assert_eq(nums.length(), 3)
  let first = match nums[0] {
    Number(n) => n
    _ => abort("expected number")
  }
  @debug.assert_eq(first, 1.0)
  let owner = obj["owner"].as_object().unwrap()
  @debug.assert_eq(owner["name"].as_string().unwrap(), "Tom")
  let age = match owner["age"] {
    Number(n) => n
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
