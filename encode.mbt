// Copyright 2026 moonbit-toml contributors
//
// SPDX-License-Identifier: MIT

///|
/// Serializes a table back into a TOML document. Sub-tables and arrays of
/// tables are emitted as `[a.b]` / `[[a.b]]` sections; every other value is
/// written inline. Key order follows first-definition order (scalars before
/// nested tables), and the output round-trips: parsing it again yields an
/// equal `Table`.
pub fn encode(table : Table) -> String {
  let sb = StringBuilder::StringBuilder()
  encode_table_into(sb, table, [])
  sb.to_string()
}

///|
/// Serializes a single value in inline form (used for arrays and inline
/// tables, and handy for fragments).
pub fn encode_value(value : Value) -> String {
  let sb = StringBuilder::StringBuilder()
  encode_value_into(sb, value)
  sb.to_string()
}

///|
fn encode_table_into(
  sb : StringBuilder,
  table : Table,
  path : Array[String],
) -> Unit {
  // Simple (non-table) values first.
  for k in table.keys() {
    let v = match table.get(k) {
      Some(v) => v
      None => abort("unreachable")
    }
    let defer_value = match v {
      Value::Table(_) => true
      Value::Array(items) => is_array_of_tables(items)
      _ => false
    }
    if !defer_value {
      write_key_eq_value(sb, k, v)
    }
  }
  // Then nested tables and arrays of tables.
  for k in table.keys() {
    let v = match table.get(k) {
      Some(v) => v
      None => abort("unreachable")
    }
    match v {
      Value::Table(sub) => {
        write_table_header(sb, path, k, "[", "]")
        encode_table_into(sb, sub, extend_path(path, k))
      }
      Value::Array(items) =>
        if is_array_of_tables(items) {
          for item in items {
            match item {
              Value::Table(elem) => {
                write_table_header(sb, path, k, "[[", "]]")
                encode_table_into(sb, elem, extend_path(path, k))
              }
              _ => abort("unreachable")
            }
          }
        }
      _ => ()
    }
  }
}

///|
fn extend_path(path : Array[String], k : String) -> Array[String] {
  let next : Array[String] = []
  for p in path {
    next.push(p)
  }
  next.push(k)
  next
}

///|
fn write_table_header(
  sb : StringBuilder,
  path : Array[String],
  k : String,
  open : String,
  close : String,
) -> Unit {
  sb.write_char('\n')
  sb.write_string(open)
  for part in path {
    sb.write_string(encode_key(part))
    sb.write_char('.')
  }
  sb.write_string(encode_key(k))
  sb.write_string(close)
  sb.write_char('\n')
}

///|
fn write_key_eq_value(sb : StringBuilder, k : String, v : Value) -> Unit {
  sb.write_string(encode_key(k))
  sb.write_string(" = ")
  encode_value_into(sb, v)
  sb.write_char('\n')
}

///|
fn encode_value_into(sb : StringBuilder, v : Value) -> Unit {
  match v {
    Str(s) => sb.write_string(encode_basic_string(s))
    Int(i) => sb.write_object(i)
    Float(f) => sb.write_string(format_float(f))
    Bool(b) => sb.write_string(if b { "true" } else { "false" })
    Datetime(dt) => sb.write_string(encode_datetime(dt))
    Array(items) => {
      sb.write_char('[')
      for i, item in items {
        if i > 0 {
          sb.write_string(", ")
        }
        encode_value_into(sb, item)
      }
      sb.write_char(']')
    }
    Table(t) => {
      sb.write_char('{')
      let mut i = 0
      for k in t.keys() {
        if i > 0 {
          sb.write_string(", ")
        }
        let inner = match t.get(k) {
          Some(inner) => inner
          None => abort("unreachable")
        }
        sb.write_string(encode_key(k))
        sb.write_string(" = ")
        encode_value_into(sb, inner)
        i += 1
      }
      sb.write_char('}')
    }
  }
}

///|
/// Quotes a key when it is not expressible as a bare key.
fn encode_key(k : String) -> String {
  let mut bare = k.length() > 0
  for c in k {
    if !is_bare_key_char(c) {
      bare = false
      break
    }
  }
  if bare {
    k
  } else {
    encode_basic_string(k)
  }
}

///|
/// Renders a string as a TOML basic string with escapes.
fn encode_basic_string(s : String) -> String {
  let sb = StringBuilder::StringBuilder()
  sb.write_char('"')
  for c in s {
    let code = c.to_int()
    match c {
      '"' => sb.write_string("\\\"")
      '\\' => sb.write_string("\\\\")
      '\u{0008}' => sb.write_string("\\b")
      '\t' => sb.write_string("\\t")
      '\n' => sb.write_string("\\n")
      '\u{000C}' => sb.write_string("\\f")
      '\r' => sb.write_string("\\r")
      _ =>
        if code < 0x20 || code == 0x7F {
          sb.write_string(escape_unicode(code))
        } else {
          sb.write_char(c)
        }
    }
  }
  sb.write_char('"')
  sb.to_string()
}

///|
fn escape_unicode(code : Int) -> String {
  let sb = StringBuilder::StringBuilder()
  sb.write_string("\\u")
  for shift in [12, 8, 4, 0] {
    let d = (code >> shift) & 0xF
    sb.write_char(
      if d < 10 {
        (0x30 + d).to_char().unwrap_or('0')
      } else {
        (0x41 + d - 10).to_char().unwrap_or('A')
      },
    )
  }
  sb.to_string()
}

///|
/// Renders a float as a valid TOML float literal (always with a fractional
/// part or an exponent; specials as `inf` / `-inf` / `nan`).
fn format_float(f : Double) -> String {
  if f.is_nan() {
    return "nan"
  }
  if f.is_inf() {
    return if f > 0.0 { "inf" } else { "-inf" }
  }
  let s = f.to_string()
  let mut needs_frac = true
  for c in s {
    if c == '.' || c == 'e' || c == 'E' {
      needs_frac = false
      break
    }
  }
  if needs_frac {
    s + ".0"
  } else {
    s
  }
}

///|
/// Renders a datetime in its canonical form (uppercase `T`/`Z`, two-digit
/// components, trailing zeros of the fractional part removed).
pub fn encode_datetime(dt : Datetime) -> String {
  let sb = StringBuilder::StringBuilder()
  match dt.date {
    Some(d) => {
      write_padded_int(sb, d.year, 4)
      sb.write_char('-')
      write_padded_int(sb, d.month, 2)
      sb.write_char('-')
      write_padded_int(sb, d.day, 2)
    }
    None => ()
  }
  match dt.time {
    Some(t) => {
      if dt.date is Some(_) {
        sb.write_char('T')
      }
      write_padded_int(sb, t.hour, 2)
      sb.write_char(':')
      write_padded_int(sb, t.minute, 2)
      sb.write_char(':')
      write_padded_int(sb, t.second, 2)
      if t.nanos > 0 {
        sb.write_char('.')
        // 9 digits, trailing zeros trimmed.
        let digits = write_padded_to_string(t.nanos, 9)
        let mut end = digits.length()
        while end > 1 {
          match digits.get_char(end - 1) {
            Some('0') => end -= 1
            _ => break
          }
        }
        sb.write_string(digits[0:end].to_owned())
      }
    }
    None => ()
  }
  if dt.has_offset {
    if dt.offset == 0 && dt.date is Some(_) {
      sb.write_char('Z')
    } else if dt.offset == 0 && dt.date is None {
      // A local time never carries an offset; the parser never produces
      // this shape, but keep the output valid anyway.
      sb.write_char('Z')
    } else {
      let minutes = dt.offset
      sb.write_char(if minutes < 0 { '-' } else { '+' })
      let abs = if minutes < 0 { -minutes } else { minutes }
      write_padded_int(sb, abs / 60, 2)
      sb.write_char(':')
      write_padded_int(sb, abs % 60, 2)
    }
  }
  sb.to_string()
}

///|
fn write_padded_int(sb : StringBuilder, v : Int, width : Int) -> Unit {
  sb.write_string(write_padded_to_string(v, width))
}

///|
fn write_padded_to_string(v : Int, width : Int) -> String {
  let mut s = v.to_string()
  while s.length() < width {
    s = "0" + s
  }
  s
}
