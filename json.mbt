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

///|
/// Error raised by `Value::from_json` for JSON values that have no TOML
/// representation.
pub suberror FromJsonError {
  /// JSON `null` does not exist in TOML.
  JsonNull
} derive(Eq, Debug)

///|
/// Converts a core `Json` value into a TOML `Value`.
///
/// Conventions:
/// - JSON `null` raises `FromJsonError::JsonNull` (TOML has no null);
/// - numbers that are integral and fit in 64 bits become TOML integers,
///   everything else stays a float (so JSON `1.0` becomes the integer
///   `1`, and values beyond the double range fall back to `inf`-style
///   floats);
/// - JSON strings never become datetimes — a string that looks like an
///   RFC 3339 date stays a string;
/// - objects become tables, arrays become arrays.
///
/// # Example
///
/// ```mbt check
/// test {
///   let v = @toml.Value::from_json(@json.parse("{\"a\": [1, true]}")) catch {
///     _ => abort("unreachable")
///   }
///   @test.assert_eq(@toml.encode_value(v), "{a = [1, true]}")
/// }
/// ```
pub fn Value::from_json(j : Json) -> Value raise FromJsonError {
  match j {
    Null => raise JsonNull
    True => Bool(true)
    False => Bool(false)
    Number(d, repr~) =>
      match repr {
        // The textual representation is authoritative when present.
        Some(text) =>
          Value::Int(@string.parse_int64(text)) catch {
            _ => Value::Float(d)
          }
        None =>
          if d == d.trunc() &&
            d >= -9223372036854775808.0 &&
            d < 9223372036854775808.0 {
            Value::Int(d.to_int64())
          } else {
            Value::Float(d)
          }
      }
    String(s) => Str(s)
    Array(items) => {
      let arr : Array[Value] = []
      for item in items {
        arr.push(Value::from_json(item))
      }
      Array(arr)
    }
    Object(entries) => {
      let t = Table::new()
      for k, v in entries {
        t.set(k, Value::from_json(v))
      }
      Table(t)
    }
  }
}
