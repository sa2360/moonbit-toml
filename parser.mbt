// Copyright 2026 moonbit-toml contributors
//
// SPDX-License-Identifier: MIT

///|
priv struct Parser {
  sc : Scanner
  root : Table
  mut cur : Table
}

///|
/// Parses a full TOML document and returns the root table.
///
/// Raises `ParseError` when the input is not a valid TOML v1.0.0 document;
/// the error carries the 1-based line/column of the problem.
///
/// # Example
///
/// ```mbt check
/// test {
///   let doc = @toml.parse(
///     "title = \"demo\"\n[server]\nhost = \"127.0.0.1\"\nport = 8080",
///   )
///   @test.assert_eq(doc.get_string("title"), Some("demo"))
///   @test.assert_eq(doc.get_path("server.port"), Some(@toml.Value::Int(8080L)))
/// }
/// ```
pub fn parse(input : String) -> Table raise ParseError {
  let sc = Scanner::make(input)
  let root = Table::make(Explicit)
  let parser = { sc, root, cur: root, }
  parser.parse_document()
  root
}

///|
/// Parses a single TOML value fragment such as `"1_000"`, `"[1, 2]"` or
/// `"1979-05-27T07:32:00Z"`. Useful for decoding individual settings.
///
/// # Example
///
/// ```mbt check
/// test {
///   @test.assert_eq(@toml.parse_value("1_000").as_int(), Some(1000L))
///   @test.assert_eq(@toml.parse_value("1979-05-27").type_name(), "date-local")
/// }
/// ```
pub fn parse_value(input : String) -> Value raise ParseError {
  let sc = Scanner::make(input)
  sc.skip_ws_newlines_comments()
  let v = sc.parse_value()
  sc.skip_ws_newlines_comments()
  if !sc.at_eof() {
    raise sc.error_here(
      InvalidSyntax(sc.here(), "trailing characters after value"),
    )
  }
  v
}

///|
fn Parser::parse_document(self : Parser) -> Unit raise ParseError {
  while true {
    self.sc.skip_inline_ws()
    if self.sc.at_eof() {
      return
    }
    let c = self.sc.peek()
    match c {
      Some('#') => {
        self.sc.skip_comment()
        self.sc.expect_line_end()
      }
      Some('\n') | Some('\r') => ignore(self.sc.newline())
      Some('[') => self.parse_table_header()
      Some(_) => {
        self.parse_keyval(self.cur)
        self.sc.expect_line_end()
      }
      None => return
    }
  }
}

///|
/// Parses a `[table]` or `[[array of tables]]` header line.
fn Parser::parse_table_header(self : Parser) -> Unit raise ParseError {
  let pos = self.sc.here()
  ignore(self.sc.bump()) // '['
  let is_aot = self.sc.bump_if('[')
  let path = self.sc.parse_key_path()
  self.sc.skip_inline_ws()
  if !self.sc.bump_if(']') {
    raise self.sc.error_here(
      InvalidSyntax(self.sc.here(), "expected ']' to close the table header"),
    )
  }
  if is_aot {
    if !self.sc.bump_if(']') {
      raise self.sc.error_here(
        InvalidSyntax(
          self.sc.here(),
          "expected ']]' to close the array-of-tables header",
        ),
      )
    }
  }
  self.sc.expect_line_end()
  if is_aot {
    self.define_array_of_tables(path, pos)
  } else {
    self.define_table(path, pos)
  }
}

///|
/// Parses a dotted key path: `simple.key` or `"quoted".key`.
fn Scanner::parse_key_path(self : Scanner) -> Array[String] raise ParseError {
  let parts : Array[String] = []
  while true {
    self.skip_inline_ws()
    parts.push(self.parse_simple_key())
    self.skip_inline_ws()
    if !self.bump_if('.') {
      break
    }
  }
  parts
}

///|
/// Parses one key component: a bare key or a quoted (single-line) string.
fn Scanner::parse_simple_key(self : Scanner) -> String raise ParseError {
  let c = match self.peek() {
    Some(c) => c
    None => raise self.error_here(UnexpectedEof(self.here()))
  }
  if c == '"' {
    self.parse_basic_string(false)
  } else if c == '\'' {
    self.parse_literal_string(false)
  } else if is_bare_key_char(c) {
    let start = self.pos
    while self.peek() is Some(c) && is_bare_key_char(c) {
      ignore(self.bump())
    }
    self.text_since(start)
  } else {
    raise self.error_here(UnexpectedChar(self.here(), c))
  }
}

///|
/// Parses `key = value` into the given table, applying the dotted-key
/// definition rules.
fn Parser::parse_keyval(self : Parser, owner : Table) -> Unit raise ParseError {
  let pos = self.sc.here()
  let path = self.sc.parse_key_path()
  self.sc.skip_inline_ws()
  if !self.sc.bump_if('=') {
    raise self.sc.error_here(
      InvalidSyntax(self.sc.here(), "expected '=' after key"),
    )
  }
  self.sc.skip_inline_ws()
  let value = self.sc.parse_value()
  insert_dotted(owner, path, value, pos)
}

///|
/// Dispatches value parsing by the first character.
fn Scanner::parse_value(self : Scanner) -> Value raise ParseError {
  let c = match self.peek() {
    Some(c) => c
    None => raise self.error_here(UnexpectedEof(self.here()))
  }
  if c == '"' {
    Value::Str(self.parse_string_value())
  } else if c == '\'' {
    Value::Str(self.parse_string_value())
  } else if c == '[' {
    self.parse_array()
  } else if c == '{' {
    self.parse_inline_table()
  } else if c == 't' {
    if self.bump_str("true") {
      Value::Bool(true)
    } else {
      raise self.error_here(InvalidValue(self.here(), 't'))
    }
  } else if c == 'f' {
    if self.bump_str("false") {
      Value::Bool(false)
    } else {
      raise self.error_here(InvalidValue(self.here(), 'f'))
    }
  } else if is_digit(c) || c == '+' || c == '-' || c == 'i' || c == 'n' {
    self.parse_number_or_datetime()
  } else {
    raise self.error_here(InvalidValue(self.here(), c))
  }
}

///|
fn Scanner::parse_array(self : Scanner) -> Value raise ParseError {
  self.enter_nesting()
  let v = self.parse_array_body()
  self.leave_nesting()
  v
}

///|
fn Scanner::parse_array_body(self : Scanner) -> Value raise ParseError {
  ignore(self.bump()) // '['
  let items : Array[Value] = []
  while true {
    self.skip_ws_newlines_comments()
    if self.bump_if(']') {
      return Value::Array(items)
    }
    items.push(self.parse_value())
    self.skip_ws_newlines_comments()
    if self.bump_if(',') {
      continue
    }
    if self.bump_if(']') {
      return Value::Array(items)
    }
    // Produce a helpful message for a missing comma.
    match self.peek() {
      Some(c) =>
        if c != ']' && c != '#' {
          raise self.error_here(
            InvalidSyntax(self.here(), "expected ',' or ']' in array"),
          )
        }
      None => raise self.error_here(UnexpectedEof(self.here()))
    }
    raise self.error_here(UnexpectedEof(self.here()))
  }
  abort("unreachable")
}

///|
fn Scanner::parse_inline_table(self : Scanner) -> Value raise ParseError {
  self.enter_nesting()
  let v = self.parse_inline_table_body()
  self.leave_nesting()
  v
}

///|
fn Scanner::parse_inline_table_body(self : Scanner) -> Value raise ParseError {
  ignore(self.bump()) // '{'
  let table = Table::make(Inline)
  self.skip_inline_ws()
  if self.bump_if('}') {
    return Value::Table(table)
  }
  while true {
    self.skip_inline_ws()
    let pos = self.here()
    let path = self.parse_key_path()
    self.skip_inline_ws()
    if !self.bump_if('=') {
      raise self.error_here(
        InvalidSyntax(self.here(), "expected '=' after key"),
      )
    }
    self.skip_inline_ws()
    let value = self.parse_value()
    insert_dotted(table, path, value, pos)
    self.skip_inline_ws()
    if self.bump_if(',') {
      self.skip_inline_ws()
      // A newline is not allowed between inline table entries.
      if self.peek() == Some('\n') || self.peek() == Some('\r') {
        raise self.error_here(
          InvalidSyntax(
            self.here(),
            "inline tables must be written on a single line",
          ),
        )
      }
      continue
    }
    if self.bump_if('}') {
      return Value::Table(table)
    }
    match self.peek() {
      Some('\n') | Some('\r') =>
        raise self.error_here(
          InvalidSyntax(
            self.here(),
            "inline tables must be written on a single line",
          ),
        )
      Some(c) => raise self.error_here(UnexpectedChar(self.here(), c))
      None => raise self.error_here(UnexpectedEof(self.here()))
    }
  }
  abort("unreachable")
}

///|
/// Applies a `[table]` header at `path`, enforcing TOML definition rules.
fn Parser::define_table(
  self : Parser,
  path : Array[String],
  pos : Position,
) -> Unit raise ParseError {
  let key_chain = join_key_path(path)
  let final_idx = path.length() - 1
  let mut t = self.root
  for i in 0..<final_idx {
    let k = path[i]
    t = self.navigate(t, k, pos, key_chain)
  }
  let k = path[final_idx]
  match t.get(k) {
    Some(Value::Table(sub)) =>
      match sub.defined {
        Implicit => {
          sub.defined = Explicit
          self.cur = sub
        }
        Explicit => raise self.sc.error_here(DuplicateKey(pos, key_chain))
        Dotted => raise self.sc.error_here(TableConflict(pos, key_chain))
        Inline => raise self.sc.error_here(TableConflict(pos, key_chain))
      }
    Some(_) => raise self.sc.error_here(DuplicateKey(pos, key_chain))
    None => {
      let sub = Table::make(Explicit)
      t.set(k, Value::Table(sub))
      self.cur = sub
    }
  }
}

///|
/// Applies a `[[array of tables]]` header at `path`.
fn Parser::define_array_of_tables(
  self : Parser,
  path : Array[String],
  pos : Position,
) -> Unit raise ParseError {
  let key_chain = join_key_path(path)
  let final_idx = path.length() - 1
  let mut t = self.root
  for i in 0..<final_idx {
    let k = path[i]
    t = self.navigate(t, k, pos, key_chain)
  }
  let k = path[final_idx]
  match t.get(k) {
    Some(Value::Array(items)) =>
      if is_array_of_tables(items) {
        let elem = Table::make(Explicit)
        elem.aot = true
        items.push(Value::Table(elem))
        self.cur = elem
      } else {
        raise self.sc.error_here(TableConflict(pos, key_chain))
      }
    Some(_) => raise self.sc.error_here(TableConflict(pos, key_chain))
    None => {
      let elem = Table::make(Explicit)
      elem.aot = true
      t.set(k, Value::Array([Value::Table(elem)]))
      self.cur = elem
    }
  }
}

///|
/// Navigates one path segment as an intermediate step of a header walk.
fn Parser::navigate(
  self : Parser,
  t : Table,
  k : String,
  pos : Position,
  key_chain : String,
) -> Table raise ParseError {
  match t.get(k) {
    Some(Value::Table(sub)) =>
      match sub.defined {
        Inline => raise self.sc.error_here(TableConflict(pos, key_chain))
        _ => sub
      }
    Some(Value::Array(items)) =>
      // Walking into an array of tables continues inside its last element
      // (e.g. `[fruit.physical]` after `[[fruit]]`).
      if is_array_of_tables(items) {
        match items[items.length() - 1] {
          Value::Table(last) => last
          _ => abort("unreachable")
        }
      } else {
        raise self.sc.error_here(TableConflict(pos, key_chain))
      }
    Some(_) => raise self.sc.error_here(TableConflict(pos, key_chain))
    None => {
      let sub = Table::make(Implicit)
      t.set(k, Value::Table(sub))
      sub
    }
  }
}

///|
fn join_key_path(path : Array[String]) -> String {
  let sb = StringBuilder::StringBuilder()
  for i, part in path {
    if i > 0 {
      sb.write_char('.')
    }
    sb.write_string(part)
  }
  sb.to_string()
}

///|
fn is_array_of_tables(items : Array[Value]) -> Bool {
  let mut all = items.length() > 0
  for item in items {
    match item {
      Value::Table(t) => if !t.aot { all = false }
      _ => all = false
    }
  }
  all
}

///|
/// Implements dotted-key insertion with the TOML collision rules:
/// intermediate tables may be reused if they are implicit, dotted or
/// header-defined, but never inline; the final key must be new.
fn insert_dotted(
  owner : Table,
  path : Array[String],
  value : Value,
  pos : Position,
) -> Unit raise ParseError {
  let key_chain = join_key_path(path)
  let final_idx = path.length() - 1
  let mut t = owner
  for i in 0..<final_idx {
    let k = path[i]
    match t.get(k) {
      Some(Value::Table(sub)) =>
        match sub.defined {
          Inline => raise ParseError(TableConflict(pos, key_chain))
          _ => t = sub
        }
      Some(_) => raise ParseError(DuplicateKey(pos, key_chain))
      None => {
        let sub = Table::make(Dotted)
        t.set(k, Value::Table(sub))
        t = sub
      }
    }
  }
  let k = path[final_idx]
  if t.get(k) is Some(_) {
    raise ParseError(DuplicateKey(pos, key_chain))
  }
  t.set(k, value)
}
