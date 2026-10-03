// Copyright 2026 moonbit-toml contributors
//
// SPDX-License-Identifier: MIT

///|
/// Parses a value that starts with a digit, `+`, `-`, `i` (inf) or `n` (nan):
/// integers, floats, and the four TOML datetime forms.
fn Scanner::parse_number_or_datetime(self : Scanner) -> Value raise ParseError {
  let start = self.mark()
  if self.looks_like_date() {
    return self.parse_datetime_value(start)
  }
  if self.looks_like_time() {
    let time = self.parse_time_value(start)
    return Value::Datetime({ date: None, time: Some(time), offset: 0, has_offset: false })
  }
  self.parse_number(start)
}

///|
/// True if the input at the current position matches the shape
/// `DDDD-DD-DD` of a TOML date.
fn Scanner::looks_like_date(self : Scanner) -> Bool {
  for i in [0, 1, 2, 3, 5, 6, 8, 9] {
    let ok = match self.peek_at(i) {
      Some(c) => is_digit(c)
      None => false
    }
    if !ok {
      return false
    }
  }
  self.peek_at(4) == Some('-') && self.peek_at(7) == Some('-')
}

///|
/// True if the input at the current position matches the shape `DD:` of a
/// TOML local time (which cannot be a valid integer literal).
fn Scanner::looks_like_time(self : Scanner) -> Bool {
  let d1 = match self.peek_at(0) {
    Some(c) => is_digit(c)
    None => false
  }
  let d2 = match self.peek_at(1) {
    Some(c) => is_digit(c)
    None => false
  }
  d1 && d2 && self.peek_at(2) == Some(':')
}

///|
/// Parses `full-date [ time-delim partial-time [ time-offset ] ]`.
/// The position is at the start of the date.
fn Scanner::parse_datetime_value(
  self : Scanner,
  start : Mark,
) -> Value raise ParseError {
  let date = self.parse_date_value(start)
  let delim = self.peek()
  if delim == Some('T') || delim == Some('t') {
    ignore(self.bump())
    let time = self.parse_time_value(start)
    if self.at_offset_start() {
      let offset = self.parse_offset_value(start)
      return Value::Datetime({ date: Some(date), time: Some(time), offset, has_offset: true })
    }
    return Value::Datetime({ date: Some(date), time: Some(time), offset: 0, has_offset: false })
  }
  if delim == Some(' ') || delim == Some('\t') {
    // A space may separate date and time, but only spaces/tabs may
    // intervene; otherwise the value is just a local date.
    let m = self.mark()
    self.skip_inline_ws()
    if self.looks_like_time() {
      let time = self.parse_time_value(start)
      if self.at_offset_start() {
        let offset = self.parse_offset_value(start)
        return Value::Datetime({ date: Some(date), time: Some(time), offset, has_offset: true })
      }
      return Value::Datetime({ date: Some(date), time: Some(time), offset: 0, has_offset: false })
    }
    self.reset(m)
  }
  Value::Datetime({ date: Some(date), time: None, offset: 0, has_offset: false })
}

///|
fn Scanner::at_offset_start(self : Scanner) -> Bool {
  let c = self.peek()
  c == Some('Z') || c == Some('z') || c == Some('+') || c == Some('-')
}

///|
fn Scanner::parse_date_value(
  self : Scanner,
  start : Mark,
) -> DateParts raise ParseError {
  self.reset(start)
  let year = self.read_fixed_digits(4, start)
  ignore(self.bump()) // '-'
  let month = self.read_fixed_digits(2, start)
  ignore(self.bump()) // '-'
  let day = self.read_fixed_digits(2, start)
  if month < 1 || month > 12 || day < 1 || day > 31 {
    raise self.error_here(InvalidDatetime(self.here(), self.text_since(start.pos)))
  }
  { year, month, day }
}

///|
/// Parses `partial-time`; the position is at the two-digit hour.
fn Scanner::parse_time_value(
  self : Scanner,
  start : Mark,
) -> TimeParts raise ParseError {
  let hour = self.read_fixed_digits(2, start)
  ignore(self.bump()) // ':'
  let minute = self.read_fixed_digits(2, start)
  let mut second = 0
  let mut nanos = 0
  if self.bump_if(':') {
    second = self.read_fixed_digits(2, start)
    if self.bump_if('.') {
      let mut digits = 0
      let mut value = 0
      while self.peek() is Some(c) && is_digit(c) {
        ignore(self.bump())
        if digits < 9 {
          value = value * 10 + hex_value(c)
        }
        digits += 1
      }
      if digits == 0 {
        raise self.error_here(InvalidDatetime(self.here(), self.text_since(start.pos)))
      }
      // Pad the stored nanoseconds to 9 digits; precision beyond 1 ns is
      // truncated.
      let pad = if digits > 9 { 0 } else { 9 - digits }
      let mut scale = 1
      for _i in 0..<pad {
        scale = scale * 10
      }
      nanos = value * scale
    }
  }
  if hour > 23 || minute > 59 || second > 60 {
    raise self.error_here(InvalidDatetime(self.here(), self.text_since(start.pos)))
  }
  { hour, minute, second, nanos }
}

///|
/// Parses `time-offset` (`Z`, `z` or `+HH:MM` / `-HH:MM`).
fn Scanner::parse_offset_value(
  self : Scanner,
  start : Mark,
) -> Int raise ParseError {
  let c = match self.peek() {
    Some(c) => c
    None => raise self.error_here(InvalidDatetime(self.here(), self.text_since(start.pos)))
  }
  if c == 'Z' || c == 'z' {
    ignore(self.bump())
    return 0
  }
  let negative = c == '-'
  ignore(self.bump())
  let hour = self.read_fixed_digits(2, start)
  if !self.bump_if(':') {
    raise self.error_here(InvalidDatetime(self.here(), self.text_since(start.pos)))
  }
  let minute = self.read_fixed_digits(2, start)
  if hour > 23 || minute > 59 {
    raise self.error_here(InvalidDatetime(self.here(), self.text_since(start.pos)))
  }
  let minutes = hour * 60 + minute
  if negative {
    -minutes
  } else {
    minutes
  }
}

///|
/// Reads exactly `n` decimal digits and returns their numeric value.
fn Scanner::read_fixed_digits(self : Scanner, n : Int, ctx : Mark) -> Int raise ParseError {
  let mut v = 0
  for _i in 0..<n {
    let c = match self.peek() {
      Some(c) => c
      None => raise self.error_here(InvalidDatetime(self.here(), self.text_since(ctx.pos)))
    }
    if !is_digit(c) {
      raise self.error_here(InvalidDatetime(self.here(), self.text_since(ctx.pos)))
    }
    v = v * 10 + hex_value(c)
    ignore(self.bump())
  }
  v
}

///|
/// Parses an integer or float literal (decimal, hex, octal or binary),
/// including `inf` / `nan`. The position is at the first character.
fn Scanner::parse_number(self : Scanner, start : Mark) -> Value raise ParseError {
  let mut negative = false
  let mut signed = false
  if self.peek() == Some('+') || self.peek() == Some('-') {
    negative = self.peek() == Some('-')
    signed = true
    ignore(self.bump())
  }
  if self.peek() == Some('i') {
    if self.bump_str("inf") {
      return Value::Float(if negative { -1.0 / 0.0 } else { 1.0 / 0.0 })
    }
    raise self.error_here(InvalidValue(self.here(), 'i'))
  }
  if self.peek() == Some('n') {
    if self.bump_str("nan") {
      return Value::Float(0.0 / 0.0)
    }
    raise self.error_here(InvalidValue(self.here(), 'n'))
  }
  // Radix integers: unsigned, only without a sign.
  if !signed && self.peek() == Some('0') {
    let second = self.peek_at(1)
    let radix = match second {
      Some('x') | Some('X') => Some(16)
      Some('o') | Some('O') => Some(8)
      Some('b') | Some('B') => Some(2)
      _ => None
    }
    match radix {
      Some(r) => {
        ignore(self.bump()) // '0'
        ignore(self.bump()) // marker
        let digits = self.scan_digit_run(hex=true)
        if digits == "" {
          raise self.error_here(InvalidNumber(self.here(), self.text_since(start.pos)))
        }
        return Value::Int(self.accumulate_radix(digits, r, start))
      }
      None => ()
    }
  }
  // Decimal integer or float.
  let int_part = self.scan_digit_run(hex=false)
  if int_part == "" {
    raise self.error_here(InvalidNumber(self.here(), self.text_since(start.pos)))
  }
  if int_part[0] == '0' && int_part.length() > 1 {
    raise self.error_here(InvalidNumber(self.here(), self.text_since(start.pos)))
  }
  let mut is_float = false
  let mut frac_part = ""
  let mut exp_part = ""
  let mut exp_negative = false
  if self.peek() == Some('.') {
    is_float = true
    ignore(self.bump())
    frac_part = self.scan_digit_run(hex=false)
    if frac_part == "" {
      raise self.error_here(InvalidNumber(self.here(), self.text_since(start.pos)))
    }
  }
  if self.peek() == Some('e') || self.peek() == Some('E') {
    is_float = true
    ignore(self.bump())
    if self.peek() == Some('+') || self.peek() == Some('-') {
      exp_negative = self.peek() == Some('-')
      ignore(self.bump())
    }
    exp_part = self.scan_digit_run(hex=false)
    if exp_part == "" {
      raise self.error_here(InvalidNumber(self.here(), self.text_since(start.pos)))
    }
  }
  if !is_float {
    return Value::Int(self.accumulate_decimal(int_part, negative, start))
  }
  // Assemble a canonical decimal float literal and parse it.
  let sb = StringBuilder::StringBuilder()
  if negative {
    sb.write_char('-')
  }
  sb.write_string(int_part)
  if frac_part != "" {
    sb.write_char('.')
    sb.write_string(frac_part)
  } else {
    sb.write_string(".0")
  }
  if exp_part != "" {
    sb.write_char('e')
    if exp_negative {
      sb.write_char('-')
    }
    sb.write_string(exp_part)
  }
  let text = sb.to_string()
  let d = try @string.parse_double(text) catch {
    _ => raise self.error_here(InvalidNumber(self.here(), text))
  }
  Value::Float(d)
}

///|
/// Scans a run of (hex) digits separated by single underscores. Returns the
/// cleaned digit text (underscores removed). Raises when the run is empty,
/// starts or ends with an underscore, or contains consecutive underscores.
fn Scanner::scan_digit_run(self : Scanner, hex~ : Bool) -> String raise ParseError {
  let sb = StringBuilder::StringBuilder()
  let mut got_digit = false
  while true {
    let c = self.peek()
    match c {
      Some(c) =>
        if (if hex { is_hex_digit(c) } else { is_digit(c) }) {
          ignore(self.bump())
          sb.write_char(c)
          got_digit = true
        } else if c == '_' {
          if !got_digit {
            raise self.error_here(
              InvalidNumber(self.here(), "underscore may only appear between digits"),
            )
          }
          // An underscore must be followed by another digit.
          let next = self.peek_at(1)
          let ok = match next {
            Some(n) => if hex {
              is_hex_digit(n)
            } else {
              is_digit(n)
            }
            None => false
          }
          if !ok {
            raise self.error_here(
              InvalidNumber(self.here(), "underscore may only appear between digits"),
            )
          }
          ignore(self.bump())
          got_digit = false
        } else {
          break
        }
      None => break
    }
  }
  if !got_digit {
    raise self.error_here(InvalidNumber(self.here(), "expected at least one digit"))
  }
  sb.to_string()
}

///|
/// Accumulates a decimal digit string into a signed 64-bit integer,
/// rejecting values outside the range of Int64.
fn Scanner::accumulate_decimal(
  self : Scanner,
  digits : String,
  negative : Bool,
  start : Mark,
) -> Int64 raise ParseError {
  let limit : UInt64 = if negative {
    9223372036854775808UL
  } else {
    9223372036854775807UL
  }
  let mut mag : UInt64 = 0UL
  for c in digits {
    let d = hex_value(c).to_uint64()
    // Check before multiplying: mag * 10 + d must not exceed the limit.
    if mag > (limit - d) / 10UL {
      raise self.error_here(InvalidNumber(self.here(), self.text_since(start.pos)))
    }
    mag = mag * 10UL + d
  }
  let signed_mag = mag.reinterpret_as_int64()
  if negative {
    -signed_mag
  } else {
    signed_mag
  }
}

///|
/// Accumulates a radix (hex/octal/binary) digit string; the result must fit
/// in a positive 64-bit signed integer.
fn Scanner::accumulate_radix(
  self : Scanner,
  digits : String,
  radix : Int,
  start : Mark,
) -> Int64 raise ParseError {
  let r : UInt64 = radix.to_uint64()
  let max : UInt64 = 9223372036854775807UL
  let mut mag : UInt64 = 0UL
  for c in digits {
    let d = hex_value(c).to_uint64()
    if mag > (max - d) / r {
      raise self.error_here(InvalidNumber(self.here(), self.text_since(start.pos)))
    }
    mag = mag * r + d
  }
  mag.reinterpret_as_int64()
}
