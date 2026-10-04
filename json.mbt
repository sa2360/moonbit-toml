// Copyright 2026 moonbit-toml contributors
//
// SPDX-License-Identifier: MIT

///|
/// Converts a TOML value to JSON (`moonbitlang/core` `Json`).
///
/// Mapping:
/// - integers keep full 64-bit precision through their textual
///   representation;
/// - the four datetime forms become strings in the canonical TOML notation;
/// - JSON has no representation for non-finite floats, so `inf`, `-inf`
///   and `nan` become the strings `"inf"`, `"-inf"` and `"nan"`;
/// - tables become JSON objects, arrays become JSON arrays.
///
/// # Example
///
/// ```mbt check
/// test {
///   let doc = @toml.parse("port = 8080\nactive = true")
///   @test.assert_eq(
///     @toml.Value::Table(doc).to_json_string(),
///     "{\"port\":8080,\"active\":true}",
///   )
/// }
/// ```
pub fn Value::to_json(self : Value) -> Json {
  match self {
    Str(s) => Json::string(s)
    Int(i) => Json::number(i.to_double(), repr=i.to_string())
    Float(f) =>
      if f.is_nan() {
        Json::string("nan")
      } else if f.is_inf() {
        Json::string(if f > 0.0 { "inf" } else { "-inf" })
      } else {
        Json::number(f)
      }
    Bool(b) => Json::boolean(b)
    Datetime(dt) => Json::string(encode_datetime(dt))
    Array(items) => {
      let arr : Array[Json] = []
      for item in items {
        arr.push(item.to_json())
      }
      Json::array(arr)
    }
    Table(t) => {
      let obj : Map[String, Json] = Map([])
      for k in t.keys() {
        let v = match t.get(k) {
          Some(v) => v
          None => abort("unreachable")
        }
        obj[k] = v.to_json()
      }
      Json::object(obj)
    }
  }
}

///|
/// Implements the standard `ToJson` trait so TOML values work with
/// `@json.to_json`, `@json.json_inspect` and friends.
pub impl ToJson for Value with fn to_json(self) {
  self.to_json()
}

///|
/// Serializes a TOML value to a JSON string (compact form).
pub fn Value::to_json_string(self : Value) -> String {
  @json.to_json(self).stringify()
}
