// Copyright 2026 moonbit-toml contributors
//
// SPDX-License-Identifier: MIT

///|
/// Date part of a TOML datetime: a calendar date.
/// `year` is 0..=9999, `month` 1..=12, `day` 1..=31.
pub(all) struct DateParts {
  year : Int
  month : Int
  day : Int
} derive(Eq, Debug)

///|
/// Time part of a TOML datetime. `second` may be 60 for leap seconds,
/// `nanos` is the sub-second part in nanoseconds (0..=999999999).
pub(all) struct TimeParts {
  hour : Int
  minute : Int
  second : Int
  nanos : Int
} derive(Eq, Debug)

///|
/// A TOML datetime value. Depending on which of `date` / `time` are present
/// and whether an offset was written, this is one of the four TOML datetime
/// forms:
///
/// - offset date-time (`date` + `time` + `has_offset`)
/// - local date-time (`date` + `time`, no offset)
/// - local date (`date` only)
/// - local time (`time` only)
///
/// `offset` is in minutes east of UTC (e.g. `-07:00` is `-420`).
pub(all) struct Datetime {
  date : DateParts?
  time : TimeParts?
  offset : Int
  has_offset : Bool
} derive(Eq, Debug)

///|
/// Definition kind of a table, used by the parser to enforce the
/// "no redefinition" rules of the TOML specification.
priv enum Definedness {
  /// Created as an intermediate while walking a longer path.
  Implicit
  /// Directly defined by a `[table]` header.
  Explicit
  /// Created by a dotted key (`a.b = 1` creates `a` as dotted).
  Dotted
  /// Written as an inline table literal `{ a = 1 }`.
  Inline
}

///|
/// An ordered TOML table. `Table` preserves the order in which keys were
/// first defined (see `keys`), and provides lookup by key and by dotted path.
pub struct Table {
  priv entries : Map[String, Value]
  priv order : Array[String]
  priv mut defined : Definedness
  priv mut aot : Bool
}

///|
/// A TOML value: the payload type of every entry in a `Table`.
pub(all) enum Value {
  Str(String)
  Int(Int64)
  Float(Double)
  Bool(Bool)
  Datetime(Datetime)
  Array(Array[Value])
  Table(Table)
}

///|
/// Creates an empty table.
pub fn Table::new() -> Table {
  { entries: Map([]), order: [], defined: Implicit, aot: false, }
}

///|
fn Table::make(defined : Definedness) -> Table {
  { entries: Map([]), order: [], defined, aot: false, }
}

///|
/// Builds a table from an array of key/value pairs, keeping the given order.
/// Later entries with an already present key replace the earlier value
/// (but keep the position of the first occurrence).
pub fn Table::from_array(entries : Array[(String, Value)]) -> Table {
  let t = Table::new()
  for entry in entries {
    t.set(entry.0, entry.1)
  }
  t
}

///|
/// Number of keys in the table.
pub fn Table::length(self : Table) -> Int {
  self.order.length()
}

///|
/// Returns true if the table has no entries.
pub fn Table::is_empty(self : Table) -> Bool {
  self.order.is_empty()
}

///|
/// Keys of the table in first-definition order.
pub fn Table::keys(self : Table) -> Iter[String] {
  self.order.iter()
}

///|
/// Sets `key` to `value`. If the key already exists its value is replaced
/// and its position in the key order is kept.
pub fn Table::set(self : Table, key : String, value : Value) -> Unit {
  if self.entries.contains(key) {
    self.entries[key] = value
  } else {
    self.entries[key] = value
    self.order.push(key)
  }
}

///|
/// Returns the value stored under `key`, or `None`.
pub fn Table::get(self : Table, key : String) -> Value? {
  self.entries.get(key)
}

///|
/// Returns true if the table contains `key`.
pub fn Table::contains(self : Table, key : String) -> Bool {
  self.entries.contains(key)
}

///|
/// Removes `key` from the table. Returns the removed value, or `None`.
pub fn Table::remove(self : Table, key : String) -> Value? {
  let v = self.entries.get(key)
  if v is Some(_) {
    self.entries.remove(key)
    let mut i = 0
    let len = self.order.length()
    while i < len {
      if self.order[i] == key {
        ignore(self.order.remove(i))
        break
      }
      i += 1
    }
  }
  v
}

///|
/// Looks up a dotted path such as `"database.server.port"`.
/// Note: path segments are split on '.' and never treated as quoted keys,
/// so this helper cannot address keys whose *own name* contains a dot.
pub fn Table::get_path(self : Table, path : String) -> Value? {
  let mut cur : Value? = Some(Value::Table(self))
  for seg_view in path.split(".") {
    let seg = seg_view.to_owned()
    let table : Table? = match cur {
      Some(Value::Table(t)) => Some(t)
      _ => None
    }
    cur = match table {
      Some(t) => t.get(seg)
      None => None
    }
    if cur is None {
      return None
    }
  }
  cur
}

///|
fn Table::equal_values(self : Table, other : Table) -> Bool {
  if self.order.length() != other.order.length() {
    return false
  }
  for k in self.order {
    match (self.entries.get(k), other.entries.get(k)) {
      (Some(a), Some(b)) => if !a.equal(b) { return false }
      _ => return false
    }
  }
  true
}

///|
/// Structural equality between TOML values. Tables compare key/value-wise
/// (order insensitive), NaN equals NaN, and datetimes compare by components
/// (so `1979-05-27T07:32:00Z` equals `1979-05-27T07:32:00+00:00`).
pub fn Value::equal(self : Value, other : Value) -> Bool {
  match (self, other) {
    (Str(a), Str(b)) => a == b
    (Int(a), Int(b)) => a == b
    (Float(a), Float(b)) => a == b || (a.is_nan() && b.is_nan())
    (Bool(a), Bool(b)) => a == b
    (Datetime(a), Datetime(b)) => a == b
    (Array(a), Array(b)) =>
      if a.length() == b.length() {
        let mut i = 0
        let len = a.length()
        while i < len {
          if !a[i].equal(b[i]) {
            return false
          }
          i += 1
        }
        true
      } else {
        false
      }
    (Table(a), Table(b)) => a.equal_values(b)
    _ => false
  }
}

///|
/// Implements the standard `Eq` trait using `Value::equal` semantics
/// (order-insensitive tables, NaN equals NaN, offset-equivalent datetimes).
pub impl Eq for Value with fn equal(self, other) {
  self.equal(other)
}

///|
/// Implements the standard `Debug` trait with a structural representation,
/// so TOML values can be used in `@debug.assert_eq` diffs.
pub impl Debug for Value with fn to_repr(self) {
  match self {
    Str(s) => Repr::opaque_("Str", Repr::string(s))
    Int(i) => Repr::opaque_("Int", Repr::integer(i.to_string()))
    Float(f) => Repr::opaque_("Float", Repr::double(f))
    Bool(b) => Repr::opaque_("Bool", Repr::bool(b))
    Datetime(dt) => Repr::opaque_("Datetime", Repr::string(encode_datetime(dt)))
    Array(items) => {
      let children : Array[Repr] = []
      for item in items {
        children.push(@debug.Debug::to_repr(item))
      }
      Repr::opaque_("Array", Repr::array(children))
    }
    Table(t) => {
      let fields : Map[String, Repr] = Map([])
      for k in t.keys() {
        let v = match t.get(k) {
          Some(v) => v
          None => abort("unreachable")
        }
        fields[k] = @debug.Debug::to_repr(v)
      }
      Repr::record(fields)
    }
  }
}

///|
/// The TOML type name of the value, one of:
/// `string`, `integer`, `float`, `boolean`, `datetime`, `datetime-local`,
/// `date-local`, `time-local`, `array`, `table`.
pub fn Value::type_name(self : Value) -> String {
  match self {
    Str(_) => "string"
    Int(_) => "integer"
    Float(_) => "float"
    Bool(_) => "boolean"
    Datetime(dt) => dt.kind_name()
    Array(_) => "array"
    Table(_) => "table"
  }
}

///|
/// The TOML type name of the datetime form: `datetime`, `datetime-local`,
/// `date-local` or `time-local`.
pub fn Datetime::kind_name(self : Datetime) -> String {
  match (self.date, self.time) {
    (Some(_), Some(_)) =>
      if self.has_offset {
        "datetime"
      } else {
        "datetime-local"
      }
    (Some(_), None) => "date-local"
    (None, Some(_)) => "time-local"
    (None, None) => "datetime-local"
  }
}

///|
/// Accessor: the string content if the value is a string.
pub fn Value::as_str(self : Value) -> String? {
  match self {
    Str(s) => Some(s)
    _ => None
  }
}

///|
/// Accessor: the integer content if the value is an integer.
pub fn Value::as_int(self : Value) -> Int64? {
  match self {
    Int(i) => Some(i)
    _ => None
  }
}

///|
/// Accessor: the float content if the value is a float.
pub fn Value::as_double(self : Value) -> Double? {
  match self {
    Float(f) => Some(f)
    _ => None
  }
}

///|
/// Accessor: the boolean content if the value is a boolean.
pub fn Value::as_bool(self : Value) -> Bool? {
  match self {
    Bool(b) => Some(b)
    _ => None
  }
}

///|
/// Accessor: the datetime content if the value is a datetime.
pub fn Value::as_datetime(self : Value) -> Datetime? {
  match self {
    Datetime(dt) => Some(dt)
    _ => None
  }
}

///|
/// Accessor: the element array if the value is an array.
pub fn Value::as_array(self : Value) -> Array[Value]? {
  match self {
    Array(a) => Some(a)
    _ => None
  }
}

///|
/// Accessor: the table content if the value is a table.
pub fn Value::as_table(self : Value) -> Table? {
  match self {
    Table(t) => Some(t)
    _ => None
  }
}

///|
/// Typed accessor on tables: the string under `key`, if present and a string.
pub fn Table::get_string(self : Table, key : String) -> String? {
  match self.get(key) {
    Some(Value::Str(s)) => Some(s)
    _ => None
  }
}

///|
/// Typed accessor on tables: the integer under `key`, if present and an integer.
pub fn Table::get_int(self : Table, key : String) -> Int64? {
  match self.get(key) {
    Some(Value::Int(i)) => Some(i)
    _ => None
  }
}

///|
/// Typed accessor on tables: the float under `key`, if present and a float.
pub fn Table::get_double(self : Table, key : String) -> Double? {
  match self.get(key) {
    Some(Value::Float(f)) => Some(f)
    _ => None
  }
}

///|
/// Typed accessor on tables: the boolean under `key`, if present and a boolean.
pub fn Table::get_bool(self : Table, key : String) -> Bool? {
  match self.get(key) {
    Some(Value::Bool(b)) => Some(b)
    _ => None
  }
}

///|
/// Typed accessor on tables: the datetime under `key`, if present and a datetime.
pub fn Table::get_datetime(self : Table, key : String) -> Datetime? {
  match self.get(key) {
    Some(Value::Datetime(dt)) => Some(dt)
    _ => None
  }
}

///|
/// Typed accessor on tables: the array under `key`, if present and an array.
pub fn Table::get_array(self : Table, key : String) -> Array[Value]? {
  match self.get(key) {
    Some(Value::Array(a)) => Some(a)
    _ => None
  }
}

///|
/// Typed accessor on tables: the table under `key`, if present and a table.
pub fn Table::get_table(self : Table, key : String) -> Table? {
  match self.get(key) {
    Some(Value::Table(t)) => Some(t)
    _ => None
  }
}
