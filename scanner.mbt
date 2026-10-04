// Copyright 2026 moonbit-toml contributors
//
// SPDX-License-Identifier: MIT

///|
/// Maximum nesting depth of arrays and inline tables. Bounds parser
/// recursion so hostile inputs fail with a positioned error instead of
/// exhausting the stack.
pub const MAX_NESTING_DEPTH : Int = 200

///|
/// Character scanner over the input with line/column tracking.
/// `pos` is a UTF-16 code unit offset into `input`.
priv struct Scanner {
  input : String
  mut pos : Int
  mut line : Int
  mut col : Int
  mut depth : Int
}

///|
priv struct Mark {
  pos : Int
  line : Int
  col : Int
}

///|
fn Scanner::make(input : String) -> Scanner {
  // A leading UTF-8 BOM (U+FEFF) is tolerated and skipped.
  let mut start = 0
  if input.length() > 0 && input.get_char(0) == Some('\u{FEFF}') {
    start = 1
  }
  { input, pos: start, line: 1, col: start + 1, depth: 0, }
}

///|
/// Enters a nested array / inline table, raising when the nesting limit is
/// exceeded. Must be paired with `leave` on every exit path.
fn Scanner::enter_nesting(self : Scanner) -> Unit raise ParseError {
  self.depth += 1
  if self.depth > MAX_NESTING_DEPTH {
    self.depth -= 1
    raise self.error_here(
      InvalidSyntax(
        self.here(),
        "exceeded maximum nesting depth (\{MAX_NESTING_DEPTH})",
      ),
    )
  }
}

///|
fn Scanner::leave_nesting(self : Scanner) -> Unit {
  self.depth -= 1
}

///|
fn Scanner::mark(self : Scanner) -> Mark {
  { pos: self.pos, line: self.line, col: self.col, }
}

///|
fn Scanner::reset(self : Scanner, m : Mark) -> Unit {
  self.pos = m.pos
  self.line = m.line
  self.col = m.col
}

///|
fn Scanner::at_eof(self : Scanner) -> Bool {
  self.pos >= self.input.length()
}

///|
/// Returns the character at the scanning position (without consuming),
/// or `None` at end of input.
fn Scanner::peek(self : Scanner) -> Char? {
  self.input.get_char(self.pos)
}

///|
/// Returns the character `n` UTF-16 code units ahead of the scanning
/// position, or `None` if out of range.
fn Scanner::peek_at(self : Scanner, n : Int) -> Char? {
  self.input.get_char(self.pos + n)
}

///|
/// Consumes and returns the current character. Must not be called at EOF.
fn Scanner::bump(self : Scanner) -> Char {
  let c = match self.input.get_char(self.pos) {
    Some(c) => c
    None => {
      // Defensive: treat out-of-range as EOF; callers check `peek` first.
      self.pos = self.input.length()
      return '\u{FFFD}'
    }
  }
  self.pos += if c.to_int() > 0xFFFF { 2 } else { 1 }
  self.col += 1
  c
}

///|
fn Scanner::bump_if(self : Scanner, c : Char) -> Bool {
  if self.peek() == Some(c) {
    ignore(self.bump())
    true
  } else {
    false
  }
}

///|
/// If the input at the current position starts with `s`, consumes it.
fn Scanner::bump_str(self : Scanner, s : String) -> Bool {
  let m = self.mark()
  for c in s {
    if self.peek() == Some(c) {
      ignore(self.bump())
    } else {
      self.reset(m)
      return false
    }
  }
  true
}

///|
fn Scanner::error_here(self : Scanner, data : ParseErrorData) -> ParseError {
  let _ = self
  ParseError(data)
}

///|
fn Scanner::here(self : Scanner) -> Position {
  { line: self.line, column: self.col, }
}

///|
/// Captures the raw text between `start` and the current position.
fn Scanner::text_since(self : Scanner, start : Int) -> String {
  self.input[start:self.pos].to_owned()
}

///|
/// Skips spaces and tabs.
fn Scanner::skip_inline_ws(self : Scanner) -> Unit {
  while self.peek() == Some(' ') || self.peek() == Some('\t') {
    ignore(self.bump())
  }
}

///|
/// Skips a comment up to (not including) the line terminator.
/// Raises on control characters inside the comment.
fn Scanner::skip_comment(self : Scanner) -> Unit raise ParseError {
  while self.peek() is Some(c) {
    let code = c.to_int()
    if code == 0x0A || code == 0x0D {
      return
    }
    if is_forbidden_control(c) {
      raise self.error_here(UnexpectedChar(self.here(), c))
    }
    ignore(self.bump())
  }
}

///|
/// Consumes a line terminator: `\n` or `\r\n`. A lone `\r` is an error.
fn Scanner::newline(self : Scanner) -> Bool raise ParseError {
  if self.peek() == Some('\n') {
    ignore(self.bump())
    self.line += 1
    self.col = 1
    true
  } else if self.peek() == Some('\r') {
    ignore(self.bump())
    if self.peek() == Some('\n') {
      ignore(self.bump())
      self.line += 1
      self.col = 1
      true
    } else {
      raise self.error_here(UnexpectedChar(self.here(), '\r'))
    }
  } else {
    false
  }
}

///|
/// Skips whitespace, newlines and comments; used inside arrays and by
/// `parse_value` fragments.
fn Scanner::skip_ws_newlines_comments(self : Scanner) -> Unit raise ParseError {
  while true {
    match self.peek() {
      Some(' ') | Some('\t') => ignore(self.bump())
      Some('\n') => {
        ignore(self.bump())
        self.line += 1
        self.col = 1
      }
      Some('\r') => ignore(self.newline())
      Some('#') => self.skip_comment()
      _ => return
    }
  }
}

///|
/// Consumes the rest of the current line: optional whitespace, an optional
/// comment, then a newline or end of file. Raises otherwise.
fn Scanner::expect_line_end(self : Scanner) -> Unit raise ParseError {
  self.skip_inline_ws()
  if self.peek() == Some('#') {
    self.skip_comment()
  }
  if self.at_eof() {
    return
  }
  if !self.newline() {
    let pos = self.here()
    let c = match self.peek() {
      Some(c) => c
      None => '\u{FFFD}'
    }
    raise self.error_here(UnexpectedChar(pos, c))
  }
}

///|
/// True if `c` can appear in a bare key: ASCII letters, digits, `_`, `-`.
fn is_bare_key_char(c : Char) -> Bool {
  let code = c.to_int()
  (code >= 0x41 && code <= 0x5A) ||
  (code >= 0x61 && code <= 0x7A) ||
  (code >= 0x30 && code <= 0x39) ||
  code == 0x5F ||
  code == 0x2D
}

///|
fn is_digit(c : Char) -> Bool {
  c.is_ascii_digit()
}

///|
fn is_hex_digit(c : Char) -> Bool {
  c.is_ascii_hexdigit()
}

///|
fn hex_value(c : Char) -> Int {
  let code = c.to_int()
  if code >= 0x30 && code <= 0x39 {
    code - 0x30
  } else if code >= 0x61 && code <= 0x66 {
    code - 0x61 + 10
  } else {
    code - 0x41 + 10
  }
}

///|
/// Control characters that are forbidden as raw characters in strings,
/// keys, comments and elsewhere (everything C0 except tab, plus DEL).
fn is_forbidden_control(c : Char) -> Bool {
  let code = c.to_int()
  code <= 0x08 ||
  code == 0x0B ||
  code == 0x0C ||
  (code >= 0x0E && code <= 0x1F) ||
  code == 0x7F
}
