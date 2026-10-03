// Copyright 2026 moonbit-toml contributors
//
// SPDX-License-Identifier: MIT

///|
test "encode scalars" {
  @debug.assert_eq(encode_value(Value::Str("hello")), "\"hello\"")
  @debug.assert_eq(encode_value(Value::Str("a\"b\\c\nd\te")), "\"a\\\"b\\\\c\\nd\\te\"")
  @debug.assert_eq(encode_value(Value::Str("\u{0001}\u{007F}")), "\"\\u0001\\u007F\"")
  @debug.assert_eq(encode_value(Value::Int(-42L)), "-42")
  @debug.assert_eq(encode_value(Value::Float(3.0)), "3.0")
  @debug.assert_eq(encode_value(Value::Float(0.1)), "0.1")
  @debug.assert_eq(encode_value(Value::Float(1.0e21)), "1e+21")
  @debug.assert_eq(encode_value(Value::Bool(true)), "true")
}

///|
test "encode floats round trip through parse" {
  for f in [0.1, -0.5, 3.0, 1.0e21, 1.0e-7, 6.626e-34, 224617.445991228, 5.0e-324, 1.7976931348623157e308] {
    let text = encode_value(Value::Float(f))
    let back : Value = parse_value(text)
    @debug.assert_eq(back.equal(Value::Float(f)), true)
  }
}

///|
test "encode datetime forms" {
  @debug.assert_eq(
    encode_datetime({ date: Some({ year: 1979, month: 5, day: 27 }), time: Some({ hour: 7, minute: 32, second: 0, nanos: 0 }), offset: 0, has_offset: true }),
    "1979-05-27T07:32:00Z",
  )
  @debug.assert_eq(
    encode_datetime({ date: Some({ year: 1979, month: 5, day: 27 }), time: Some({ hour: 0, minute: 32, second: 0, nanos: 999999000 }), offset: -420, has_offset: true }),
    "1979-05-27T00:32:00.999999-07:00",
  )
  @debug.assert_eq(
    encode_datetime({ date: Some({ year: 1979, month: 5, day: 27 }), time: Some({ hour: 7, minute: 32, second: 0, nanos: 0 }), offset: 0, has_offset: false }),
    "1979-05-27T07:32:00",
  )
  @debug.assert_eq(
    encode_datetime({ date: Some({ year: 1979, month: 5, day: 27 }), time: None, offset: 0, has_offset: false }),
    "1979-05-27",
  )
  @debug.assert_eq(
    encode_datetime({ date: None, time: Some({ hour: 7, minute: 32, second: 0, nanos: 100000000 }), offset: 0, has_offset: false }),
    "07:32:00.1",
  )
}

///|
test "encode document with tables" {
  let doc = must_parse("[a]\nx = 1\n[a.b]\ny = \"z\"\n[[c]]\nd = true\n[[c]]\n")
  let encoded = encode(doc)
  let reparsed = parse(encoded)
  @debug.assert_eq(Value::Table(reparsed).equal(Value::Table(doc)), true)
  // spot check the encoded shape
  @debug.assert_eq(encoded.contains("[a.b]"), true)
  @debug.assert_eq(encoded.contains("[[c]]"), true)
}

///|
test "encode keys" {
  let doc = parse("a = 1\n\"b c\" = 2\n\"\" = 3\n\"key.with.dots\" = 4")
  let encoded = encode(doc)
  let reparsed = parse(encoded)
  @debug.assert_eq(reparsed.get_int("a"), Some(1L))
  @debug.assert_eq(reparsed.get_int("b c"), Some(2L))
  @debug.assert_eq(reparsed.get_int(""), Some(3L))
  @debug.assert_eq(reparsed.get_int("key.with.dots"), Some(4L))
  @debug.assert_eq(Value::Table(reparsed).equal(Value::Table(doc)), true)
}

///|
test "encode inline tables inside arrays" {
  let doc = must_parse("points = [{x = 1, y = 2}, {x = 3, y = 4}]")
  let encoded = encode(doc)
  let reparsed = parse(encoded)
  @debug.assert_eq(Value::Table(reparsed).equal(Value::Table(doc)), true)
  let points = reparsed.get_array("points").unwrap()
  @debug.assert_eq(points.length(), 2)
}
