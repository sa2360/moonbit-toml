// Copyright 2026 moonbit-toml contributors
//
// SPDX-License-Identifier: MIT

///|
/// A position (1-based line and column) inside a TOML document.
pub(all) struct Position {
  line : Int
  column : Int
} derive(Eq, Debug)

///|
/// Structured description of a TOML parse failure.
pub(all) enum ParseErrorData {
  /// A character appeared where it is not allowed.
  UnexpectedChar(Position, Char)
  /// The document ended in the middle of a construct.
  UnexpectedEof(Position)
  /// A string (or multi-line string) was never closed.
  UnterminatedString(Position)
  /// An invalid escape sequence such as `\q`.
  InvalidEscape(Position, Char)
  /// A `\uXXXX` / `\UXXXXXXXX` escape that is out of range or a surrogate.
  InvalidUnicodeEscape(Position, String)
  /// An integer or float literal that violates TOML syntax or the 64-bit range.
  InvalidNumber(Position, String)
  /// A date/time literal that violates RFC 3339 style syntax.
  InvalidDatetime(Position, String)
  /// A value that does not start any known TOML production.
  InvalidValue(Position, Char)
  /// The same key (or table) was defined twice.
  DuplicateKey(Position, String)
  /// A `[table]` / `[[array of tables]]` header conflicts with existing data.
  TableConflict(Position, String)
  /// Anything else, with a human readable description.
  InvalidSyntax(Position, String)
} derive(Eq, Debug)

///|
/// The error type raised by `parse` and `parse_value`.
pub suberror ParseError {
  ParseError(ParseErrorData)
} derive(Debug)

///|
fn ParseErrorData::message(self : ParseErrorData) -> String {
  match self {
    UnexpectedChar(pos, c) =>
      "line \{pos.line}, column \{pos.column}: unexpected character '\{c}'"
    UnexpectedEof(pos) =>
      "line \{pos.line}, column \{pos.column}: unexpected end of input"
    UnterminatedString(pos) =>
      "line \{pos.line}, column \{pos.column}: unterminated string"
    InvalidEscape(pos, c) =>
      "line \{pos.line}, column \{pos.column}: invalid escape sequence '\\\{c}'"
    InvalidUnicodeEscape(pos, text) =>
      "line \{pos.line}, column \{pos.column}: invalid unicode escape '\{text}'"
    InvalidNumber(pos, text) =>
      "line \{pos.line}, column \{pos.column}: invalid number '\{text}'"
    InvalidDatetime(pos, text) =>
      "line \{pos.line}, column \{pos.column}: invalid datetime '\{text}'"
    InvalidValue(pos, c) =>
      "line \{pos.line}, column \{pos.column}: invalid value starting with '\{c}'"
    DuplicateKey(pos, key) =>
      "line \{pos.line}, column \{pos.column}: duplicate key '\{key}'"
    TableConflict(pos, key) =>
      "line \{pos.line}, column \{pos.column}: conflicting table definition for '\{key}'"
    InvalidSyntax(pos, msg) =>
      "line \{pos.line}, column \{pos.column}: \{msg}"
  }
}

///|
impl Show for ParseError with output(self, logger) {
  logger.write_object(self.message())
}

///|
/// A short human readable description of the error, e.g.
/// `line 3, column 5: duplicate key 'apple'`.
pub fn ParseError::message(self : ParseError) -> String {
  match self {
    ParseError(data) => data.message()
  }
}
