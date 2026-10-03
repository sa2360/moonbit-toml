// Copyright 2026 moonbit-toml contributors
//
// SPDX-License-Identifier: MIT

///|
/// toml2json: parse a TOML file and print it as toml-test protocol JSON
/// (values tagged as `{"type": ..., "value": ...}`).
///
/// Usage: `toml2json <file.toml>`
///
/// Exit status: 0 on success, non-zero when the input is not valid TOML
/// (the error message goes to stderr).
fn main raise {
  let args = @env.args()
  let mut file : String? = None
  for arg in args {
    // Skip the program path itself (first argument on native targets).
    if arg == args[0] {
      continue
    }
    file = Some(arg)
    break
  }
  let path = match file {
    Some(path) => path
    None => abort("usage: toml2json <file.toml>")
  }
  let bytes = @fs.read_file_to_bytes(path)
  let text = decode_utf8_strict(bytes)
  let doc = @toml.parse(text) catch { err => abort(err.message()) }
  let sb = StringBuilder::StringBuilder()
  emit_tagged(sb, @toml.Value::Table(doc))
  println(sb.to_string())
}

///|
/// Decodes UTF-8 bytes into a String, rejecting invalid sequences
/// (bad continuation bytes, surrogates, overlong encodings, > U+10FFFF).
fn decode_utf8_strict(bytes : Bytes) -> String raise {
  let sb = StringBuilder::StringBuilder()
  let len = bytes.length()
  let mut i = 0
  while i < len {
    let b0 = bytes[i].to_int()
    if b0 < 0x80 {
      sb.write_char(b0.to_char().unwrap_or('\u{FFFD}'))
      i += 1
    } else if b0 >= 0xC2 && b0 <= 0xDF {
      let b1 = cont(bytes, i + 1, len)
      sb.write_char(
        (((b0 & 0x1F) << 6) | (b1 & 0x3F)).to_char().unwrap_or('\u{FFFD}'),
      )
      i += 2
    } else if b0 >= 0xE0 && b0 <= 0xEF {
      let b1 = cont(bytes, i + 1, len)
      // Reject overlong forms and surrogates.
      if (b0 == 0xE0 && b1 < 0xA0) || (b0 == 0xED && b1 > 0x9F) {
        abort("invalid UTF-8 byte \{i}")
      }
      let b2 = cont(bytes, i + 2, len)
      let cp = ((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F)
      sb.write_char(cp.to_char().unwrap_or('\u{FFFD}'))
      i += 3
    } else if b0 >= 0xF0 && b0 <= 0xF4 {
      let b1 = cont(bytes, i + 1, len)
      // Reject overlong forms and code points beyond U+10FFFF.
      if (b0 == 0xF0 && b1 < 0x90) || (b0 == 0xF4 && b1 > 0x8F) {
        abort("invalid UTF-8 byte \{i}")
      }
      let b2 = cont(bytes, i + 2, len)
      let b3 = cont(bytes, i + 3, len)
      let cp = ((b0 & 0x07) << 18) |
        ((b1 & 0x3F) << 12) |
        ((b2 & 0x3F) << 6) |
        (b3 & 0x3F)
      sb.write_char(cp.to_char().unwrap_or('\u{FFFD}'))
      i += 4
    } else {
      // Stray continuation byte, 0xC0/0xC1, or 0xF5..0xFF.
      abort("invalid UTF-8 byte \{i}")
    }
  }
  sb.to_string()
}

///|
/// Reads one continuation byte (0x80..0xBF) at `i`.
fn cont(bytes : Bytes, i : Int, len : Int) -> Int raise {
  if i >= len {
    abort("truncated UTF-8 sequence at byte \{i}")
  }
  let b = bytes[i].to_int()
  if b < 0x80 || b > 0xBF {
    abort("invalid UTF-8 continuation byte \{i}")
  }
  b
}

///|
/// Emits a TOML value in the toml-test tagged JSON protocol.
fn emit_tagged(sb : StringBuilder, v : @toml.Value) -> Unit {
  match v {
    @toml.Str(s) => {
      sb.write_string("{\"type\": \"string\", \"value\": ")
      emit_json_string(sb, s)
      sb.write_char('}')
    }
    @toml.Int(i) => {
      sb.write_string("{\"type\": \"integer\", \"value\": ")
      emit_json_string(sb, i.to_string())
      sb.write_char('}')
    }
    @toml.Float(f) => {
      sb.write_string("{\"type\": \"float\", \"value\": ")
      emit_json_string(sb, format_float_json(f))
      sb.write_char('}')
    }
    @toml.Bool(b) => {
      sb.write_string("{\"type\": \"bool\", \"value\": ")
      emit_json_string(sb, if b { "true" } else { "false" })
      sb.write_char('}')
    }
    @toml.Datetime(dt) => {
      sb.write_string("{\"type\": \"")
      sb.write_string(dt.kind_name())
      sb.write_string("\", \"value\": ")
      emit_json_string(sb, @toml.encode_datetime(dt))
      sb.write_char('}')
    }
    @toml.Array(items) => {
      sb.write_char('[')
      for i, item in items {
        if i > 0 {
          sb.write_char(',')
        }
        emit_tagged(sb, item)
      }
      sb.write_char(']')
    }
    @toml.Table(t) => {
      sb.write_char('{')
      let mut i = 0
      for k in t.keys() {
        if i > 0 {
          sb.write_char(',')
        }
        emit_json_string(sb, k)
        sb.write_char(':')
        emit_tagged(sb, t.get(k).unwrap_or(@toml.Value::Bool(false)))
        i += 1
      }
      sb.write_char('}')
    }
  }
}

///|
/// Canonical float rendering for the tagged protocol: shortest decimal
/// that round-trips, always with a fraction or exponent, `inf`/`nan`
/// specials.
fn format_float_json(f : Double) -> String {
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
/// Emits a JSON string literal with proper escaping (control characters
/// as \uXXXX, everything else raw UTF-8).
fn emit_json_string(sb : StringBuilder, s : String) -> Unit {
  sb.write_char('"')
  for c in s {
    let code = c.to_int()
    match c {
      '"' => sb.write_string("\\\"")
      '\\' => sb.write_string("\\\\")
      '\u{0008}' => sb.write_string("\\b")
      '\u{000C}' => sb.write_string("\\f")
      '\n' => sb.write_string("\\n")
      '\r' => sb.write_string("\\r")
      '\t' => sb.write_string("\\t")
      _ =>
        if code < 0x20 {
          sb.write_string(unicode_escape_json(code))
        } else {
          sb.write_char(c)
        }
    }
  }
  sb.write_char('"')
}

///|
fn unicode_escape_json(code : Int) -> String {
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
