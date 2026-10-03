// Copyright 2026 moonbit-toml contributors
//
// SPDX-License-Identifier: MIT

///|
/// Parses the four TOML string kinds starting at an opening quote.
/// `"""` / `'''` select the multi-line variants.
fn Scanner::parse_string_value(self : Scanner) -> String raise ParseError {
  let c = match self.peek() {
    Some(c) => c
    None => raise self.error_here(UnexpectedEof(self.here()))
  }
  if c == '"' {
    let multiline = self.peek_at(1) == Some('"') && self.peek_at(2) == Some('"')
    self.parse_basic_string(multiline)
  } else if c == '\'' {
    let multiline = self.peek_at(1) == Some('\'') &&
      self.peek_at(2) == Some('\'')
    self.parse_literal_string(multiline)
  } else {
    raise self.error_here(InvalidValue(self.here(), c))
  }
}

///|
/// Parses a basic string (`"..."` or `"""..."""` with escapes).
/// The scanning position must be at the opening quote.
fn Scanner::parse_basic_string(
  self : Scanner,
  multiline : Bool,
) -> String raise ParseError {
  ignore(self.bump()) // opening quote
  let sb = StringBuilder::StringBuilder()
  if multiline {
    ignore(self.bump()) // second quote
    ignore(self.bump()) // third quote
    // A newline immediately after the opening delimiter is trimmed.
    if self.peek() == Some('\r') {
      if self.bump_str("\r\n") {
        self.line += 1
        self.col = 1
      }
    } else if self.peek() == Some('\n') {
      ignore(self.bump())
      self.line += 1
      self.col = 1
    }
    while true {
      let c = match self.peek() {
        Some(c) => c
        None => raise self.error_here(UnterminatedString(self.here()))
      }
      if c == '"' {
        // Count the run of quotes: a run of 3..5 closes the string and the
        // surplus quotes (up to two) belong to the content. Longer runs of
        // quotes with no content in between cannot appear in a valid body.
        let mut run = 0
        while self.peek() == Some('"') {
          ignore(self.bump())
          run += 1
        }
        if run >= 3 {
          if run > 5 {
            raise self.error_here(
              InvalidSyntax(self.here(), "too many consecutive quotes"),
            )
          }
          for _i in 0..<(run - 3) {
            sb.write_char('"')
          }
          return sb.to_string()
        }
        for _i in 0..<run {
          sb.write_char('"')
        }
      } else if c == '\\' {
        self.parse_escape(sb, multiline=true)
      } else if c == '\n' {
        ignore(self.bump())
        self.line += 1
        self.col = 1
        sb.write_char('\n')
      } else if c == '\r' {
        // Multi-line strings normalize CRLF to a single newline.
        ignore(self.newline())
        sb.write_char('\n')
      } else if is_forbidden_control(c) {
        raise self.error_here(UnexpectedChar(self.here(), c))
      } else {
        ignore(self.bump())
        sb.write_char(c)
      }
    }
    abort("unreachable")
  } else {
    while true {
      let c = match self.peek() {
        Some(c) => c
        None => raise self.error_here(UnterminatedString(self.here()))
      }
      if c == '"' {
        ignore(self.bump())
        return sb.to_string()
      } else if c == '\\' {
        self.parse_escape(sb, multiline=false)
      } else if c == '\n' || c == '\r' {
        raise self.error_here(
          InvalidSyntax(
            self.here(),
            "newline is not allowed in a single-line string",
          ),
        )
      } else if is_forbidden_control(c) {
        raise self.error_here(UnexpectedChar(self.here(), c))
      } else {
        ignore(self.bump())
        sb.write_char(c)
      }
    }
    abort("unreachable")
  }
}

///|
/// Parses a literal string (`'...'` or `'''...'''`, no escapes).
fn Scanner::parse_literal_string(
  self : Scanner,
  multiline : Bool,
) -> String raise ParseError {
  ignore(self.bump()) // opening quote
  let sb = StringBuilder::StringBuilder()
  if multiline {
    ignore(self.bump())
    ignore(self.bump())
    if self.peek() == Some('\r') {
      if self.bump_str("\r\n") {
        self.line += 1
        self.col = 1
      }
    } else if self.peek() == Some('\n') {
      ignore(self.bump())
      self.line += 1
      self.col = 1
    }
    while true {
      let c = match self.peek() {
        Some(c) => c
        None => raise self.error_here(UnterminatedString(self.here()))
      }
      if c == '\'' {
        let mut run = 0
        while self.peek() == Some('\'') {
          ignore(self.bump())
          run += 1
        }
        if run >= 3 {
          if run > 5 {
            raise self.error_here(
              InvalidSyntax(self.here(), "too many consecutive quotes"),
            )
          }
          for _i in 0..<(run - 3) {
            sb.write_char('\'')
          }
          return sb.to_string()
        }
        for _i in 0..<run {
          sb.write_char('\'')
        }
      } else if c == '\n' {
        ignore(self.bump())
        self.line += 1
        self.col = 1
        sb.write_char('\n')
      } else if c == '\r' {
        ignore(self.newline())
        sb.write_char('\n')
      } else if is_forbidden_control(c) {
        raise self.error_here(UnexpectedChar(self.here(), c))
      } else {
        ignore(self.bump())
        sb.write_char(c)
      }
    }
    abort("unreachable")
  } else {
    while true {
      let c = match self.peek() {
        Some(c) => c
        None => raise self.error_here(UnterminatedString(self.here()))
      }
      if c == '\'' {
        ignore(self.bump())
        return sb.to_string()
      } else if c == '\n' || c == '\r' {
        raise self.error_here(
          InvalidSyntax(
            self.here(),
            "newline is not allowed in a single-line string",
          ),
        )
      } else if is_forbidden_control(c) {
        raise self.error_here(UnexpectedChar(self.here(), c))
      } else {
        ignore(self.bump())
        sb.write_char(c)
      }
    }
    abort("unreachable")
  }
}

///|
/// Parses one escape sequence; the scanning position is at the backslash.
/// In multi-line strings `\` followed by whitespace up to a newline trims
/// that whitespace and all following whitespace ("line ending backslash").
fn Scanner::parse_escape(
  self : Scanner,
  sb : StringBuilder,
  multiline~ : Bool,
) -> Unit raise ParseError {
  let bs_pos = self.here()
  ignore(self.bump()) // backslash
  let c = match self.peek() {
    Some(c) => c
    None => raise self.error_here(UnterminatedString(bs_pos))
  }
  match c {
    'b' => {
      ignore(self.bump())
      sb.write_char('\u{0008}')
    }
    't' => {
      ignore(self.bump())
      sb.write_char('\t')
    }
    'n' => {
      ignore(self.bump())
      sb.write_char('\n')
    }
    'f' => {
      ignore(self.bump())
      sb.write_char('\u{000C}')
    }
    'r' => {
      ignore(self.bump())
      sb.write_char('\r')
    }
    '"' => {
      ignore(self.bump())
      sb.write_char('"')
    }
    '\\' => {
      ignore(self.bump())
      sb.write_char('\\')
    }
    'u' => {
      ignore(self.bump())
      sb.write_char(self.parse_unicode_escape(4))
    }
    'U' => {
      ignore(self.bump())
      sb.write_char(self.parse_unicode_escape(8))
    }
    _ =>
      if multiline {
        // Line-ending backslash: `\` followed by only whitespace up to a
        // newline trims the whitespace, the newline and all whitespace up
        // to the next non-whitespace character.
        let m = self.mark()
        self.skip_inline_ws()
        if self.peek() == Some('\r') || self.peek() == Some('\n') {
          ignore(self.newline())
          while true {
            match self.peek() {
              Some(' ') | Some('\t') => ignore(self.bump())
              Some('\n') => {
                ignore(self.bump())
                self.line += 1
                self.col = 1
              }
              Some('\r') => ignore(self.newline())
              _ => break
            }
          }
          return
        }
        self.reset(m)
        raise self.error_here(InvalidEscape(bs_pos, c))
      } else {
        raise self.error_here(InvalidEscape(bs_pos, c))
      }
  }
}

///|
/// Parses a `\uXXXX` or `\UXXXXXXXX` escape (the marker already consumed).
fn Scanner::parse_unicode_escape(
  self : Scanner,
  digits : Int,
) -> Char raise ParseError {
  let start = self.pos
  let mut value : Int64 = 0L
  for _i in 0..<digits {
    let c = match self.peek() {
      Some(c) => c
      None =>
        raise self.error_here(
          InvalidUnicodeEscape(self.here(), self.text_since(start)),
        )
    }
    if !is_hex_digit(c) {
      raise self.error_here(
        InvalidUnicodeEscape(self.here(), self.text_since(start)),
      )
    }
    value = value * 16L + Int64::from_int(hex_value(c))
    if value > 0x10FFFFL {
      raise self.error_here(
        InvalidUnicodeEscape(self.here(), self.text_since(start)),
      )
    }
    ignore(self.bump())
  }
  // Surrogates are not Unicode scalar values.
  if value >= 0xD800L && value <= 0xDFFFL {
    raise self.error_here(
      InvalidUnicodeEscape(self.here(), self.text_since(start)),
    )
  }
  value.to_int().to_char().unwrap_or('\u{FFFD}')
}
