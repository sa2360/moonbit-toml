// Copyright 2026 moonbit-toml contributors
//
// SPDX-License-Identifier: MIT

///|
/// Parses `src` and returns the root table; fails the test on error.
fn must_parse(src : String) -> Table raise {
  parse(src) catch {
    err => fail("unexpected parse error: \{err.message()}, input=\{src}")
  }
}

///|
/// Parses `src` and expects success (result discarded).
fn parse_ok(src : String) -> Unit raise {
  let _ = must_parse(src)
}

///|
/// Parses `src` and expects a parse error; fails the test on success.
fn must_fail(src : String) -> Unit raise {
  try parse(src) catch {
    _ => return
  } noraise {
    _ => fail("expected parse error, input=\{src}")
  }
}

///|
test "key value pairs" {
  let doc = must_parse("a = 1\nb = \"x\"\nc = true\nd = 2.5\ne = [1, 2]")
  @debug.assert_eq(doc.get_int("a"), Some(1L))
  @debug.assert_eq(doc.get_string("b"), Some("x"))
  @debug.assert_eq(doc.get_bool("c"), Some(true))
  @debug.assert_eq(doc.get_double("d"), Some(2.5))
  @debug.assert_eq(doc.get_array("e").unwrap().length(), 2)
}

///|
test "strings" {
  let doc = must_parse(
    "a = \"I'm a string. \\\"You can quote me\\\". A tab \\u0009 and \\U0001F600 emoji\"",
  )
  @debug.assert_eq(
    doc.get_string("a"),
    Some(
      "I'm a string. \"You can quote me\". A tab \u{0009} and \u{1F600} emoji",
    ),
  )
  let doc2 = must_parse("p = \"\\\\path\\\\to\\\\file\"")
  @debug.assert_eq(doc2.get_string("p"), Some("\\path\\to\\file"))
  let doc3 = must_parse("lit = 'C:\\Users\\node\\r26'")
  @debug.assert_eq(doc3.get_string("lit"), Some("C:\\Users\\node\\r26"))
}

///|
test "multiline strings" {
  let doc = must_parse("ml1 = \"\"\"\nRoses are red\nViolets are blue\"\"\"")
  @debug.assert_eq(
    doc.get_string("ml1"),
    Some("Roses are red\nViolets are blue"),
  )
  let doc2 = must_parse(
    "ml2 = \"\"\"\\\n  the quick \\\n    brown fox \\\n    jumps over \\\n    the lazy dog.\"\"\"",
  )
  @debug.assert_eq(
    doc2.get_string("ml2"),
    Some("the quick brown fox jumps over the lazy dog."),
  )
  let doc3 = must_parse(
    "q = \"\"\"Here are two quotation marks: \"\". Simple enough.\"\"\"",
  )
  @debug.assert_eq(
    doc3.get_string("q"),
    Some("Here are two quotation marks: \"\". Simple enough."),
  )
  let doc4 = must_parse(
    "lit = '''\nThe first newline is\ntrimmed in raw strings.\n'''",
  )
  @debug.assert_eq(
    doc4.get_string("lit"),
    Some("The first newline is\ntrimmed in raw strings.\n"),
  )
}

///|
test "integers" {
  let doc = must_parse(
    "a = +99\nb = 42\nc = 0\nd = -17\ne = 1_000\nf = 5_349_221\ng = 0xDEADBEEF\nh = 0xdead_beef\ni = 0o01234567\nj = 0b11010110\nk = 9223372036854775807\nm = -9223372036854775808",
  )
  @debug.assert_eq(doc.get_int("a"), Some(99L))
  @debug.assert_eq(doc.get_int("b"), Some(42L))
  @debug.assert_eq(doc.get_int("c"), Some(0L))
  @debug.assert_eq(doc.get_int("d"), Some(-17L))
  @debug.assert_eq(doc.get_int("e"), Some(1000L))
  @debug.assert_eq(doc.get_int("f"), Some(5349221L))
  @debug.assert_eq(doc.get_int("g"), Some(3735928559L))
  @debug.assert_eq(doc.get_int("h"), Some(3735928559L))
  @debug.assert_eq(doc.get_int("i"), Some(342391L))
  @debug.assert_eq(doc.get_int("j"), Some(214L))
  @debug.assert_eq(doc.get_int("k"), Some(9223372036854775807L))
  @debug.assert_eq(doc.get_int("m"), Some(-9223372036854775808L))
}

///|
test "invalid integers" {
  must_fail("a = 01")
  must_fail("a = _1")
  must_fail("a = 1_")
  must_fail("a = 1__2")
  must_fail("a = 0x")
  must_fail("a = 0x_1")
  must_fail("a = 9223372036854775808")
  must_fail("a = -9223372036854775809")
  must_fail("a = +_1")
  must_fail("a = 1.")
  must_fail("a = .1")
}

///|
test "floats" {
  let doc = must_parse(
    "a = 3.14\nb = +1.0\nc = 3e2\nd = 3E+2\ne = -2E-2\nf = 6.626e-34\ng = 224_617.445_991_228\nh = inf\ni = +inf\nj = -inf\nk = nan\nl = 5e-324",
  )
  @debug.assert_eq(doc.get_double("a"), Some(3.14))
  @debug.assert_eq(doc.get_double("b"), Some(1.0))
  @debug.assert_eq(doc.get_double("c"), Some(300.0))
  @debug.assert_eq(doc.get_double("d"), Some(300.0))
  @debug.assert_eq(doc.get_double("e"), Some(-0.02))
  @debug.assert_eq(doc.get_double("f"), Some(6.626e-34))
  @debug.assert_eq(doc.get_double("g"), Some(224617.445991228))
  @debug.assert_eq(doc.get_double("h").unwrap().is_pos_inf(), true)
  @debug.assert_eq(doc.get_double("j").unwrap().is_neg_inf(), true)
  @debug.assert_eq(doc.get_double("k").unwrap().is_nan(), true)
  @debug.assert_eq(doc.get_double("l"), Some(5.0e-324))
}

///|
test "booleans" {
  let doc = must_parse("a = true\nb = false")
  @debug.assert_eq(doc.get_bool("a"), Some(true))
  @debug.assert_eq(doc.get_bool("b"), Some(false))
  must_fail("a = truex")
  must_fail("a = false1")
}

///|
test "datetimes" {
  let doc = must_parse(
    "odt1 = 1979-05-27T07:32:00Z\nodt2 = 1979-05-27T00:32:00-07:00\nodt3 = 1979-05-27T00:32:00.999999-07:00\nodt4 = 1979-05-27 07:32:00Z\nldt1 = 1979-05-27T07:32:00\nldt2 = 1979-05-27T00:32:00.999999\nd1 = 1979-05-27\nt1 = 07:32:00\nt2 = 00:32:00.999999\nt3 = 07:32",
  )
  let dt1 = doc.get_datetime("odt1").unwrap()
  @debug.assert_eq(dt1.kind_name(), "datetime")
  @debug.assert_eq(dt1.offset, 0)
  @debug.assert_eq(doc.get_datetime("odt2").unwrap().offset, -420)
  @debug.assert_eq(
    doc.get_datetime("odt3").unwrap().time.unwrap().nanos,
    999999000,
  )
  @debug.assert_eq(doc.get_datetime("odt4").unwrap().kind_name(), "datetime")
  @debug.assert_eq(
    doc.get_datetime("ldt1").unwrap().kind_name(),
    "datetime-local",
  )
  @debug.assert_eq(
    doc.get_datetime("ldt2").unwrap().kind_name(),
    "datetime-local",
  )
  @debug.assert_eq(doc.get_datetime("d1").unwrap().kind_name(), "date-local")
  @debug.assert_eq(doc.get_datetime("t1").unwrap().kind_name(), "time-local")
  @debug.assert_eq(doc.get_datetime("t2").unwrap().kind_name(), "time-local")
  @debug.assert_eq(doc.get_datetime("t3").unwrap().kind_name(), "time-local")
  @debug.assert_eq(doc.get_datetime("t3").unwrap().time.unwrap().second, 0)
}

///|
test "invalid datetimes" {
  must_fail("a = 1979-13-27")
  must_fail("a = 1979-05-00")
  must_fail("a = 1979-05-27T25:32:00Z")
  must_fail("a = 1979-05-27T07:62:00Z")
  must_fail("a = 07:62:00")
  must_fail("a = 1979-05-27T07:32:00+24:00")
  must_fail("a = 1979-05-27T")
  must_fail("a = 1979-05-27x")
}

///|
test "arrays" {
  let doc = must_parse(
    "a = [1, 2, 3]\nb = [\"red\", \"yellow\", \"green\"]\nc = [[1, 2], [3, 4, 5]]\nd = [\"all\", 'strings', \"\"\"are the same\"\"\", '''type''']\ne = [0.1, 0.2, 0.5, 2560.5]\nf = [\"Foo Bar <foo@example.com>\", { name = \"Baz\", email = \"baz@example.com\" }]\ng = [\n  1, 2, 3\n]\nh = [\n  1,\n  2, # this is ok\n]\ni = []\nj = [1, 2, 3,]",
  )
  @debug.assert_eq(doc.get_array("a").unwrap().length(), 3)
  @debug.assert_eq(
    doc.get_array("c").unwrap()[0].as_array().unwrap().length(),
    2,
  )
  @debug.assert_eq(doc.get_array("i").unwrap().length(), 0)
  @debug.assert_eq(doc.get_array("j").unwrap().length(), 3)
}

///|
test "inline tables" {
  let doc = must_parse(
    "name = { first = \"Tom\", last = \"Werner\" }\npoint = { x = 1, y = 2 }\nanimal = { type.name = \"pug\" }\nempty = {}",
  )
  let name = doc.get_table("name").unwrap()
  @debug.assert_eq(name.get_string("first"), Some("Tom"))
  let animal = doc.get_table("animal").unwrap()
  @debug.assert_eq(animal.get_path("type.name").unwrap().as_str(), Some("pug"))
  @debug.assert_eq(doc.get_table("empty").unwrap().length(), 0)
  must_fail("a = {x = 1,\ny = 2}")
  must_fail("a = {x = 1, x = 2}")
}

///|
test "tables and dotted keys" {
  let doc = must_parse(
    "[table-1]\nkey1 = \"some string\"\nkey2 = 123\n\n[table-2]\nkey1 = \"another\"\n\n[dog.\"tater.man\"]\ntype.name = \"pug\"\n\n[a.b.c]\nd = 1\n\n[x.y.z.w]\n",
  )
  let t1 = doc.get_table("table-1").unwrap()
  @debug.assert_eq(t1.get_string("key1"), Some("some string"))
  let dog = doc.get_table("dog").unwrap().get_table("tater.man").unwrap()
  @debug.assert_eq(dog.get_path("type.name").unwrap().as_str(), Some("pug"))
  let abc = doc.get_path("a.b.c").unwrap().as_table().unwrap()
  @debug.assert_eq(abc.get_int("d"), Some(1L))
}

///|
test "array of tables" {
  let doc = must_parse(
    "[[products]]\nname = \"Hammer\"\nsku = 738594937\n\n[[products]]\n\n[[products]]\nname = \"Nail\"\nsku = 284758393\ncolor = \"gray\"\n\n[[fruit]]\nname = \"apple\"\n[fruit.physical]\ncolor = \"red\"\n[[fruit.variety]]\nname = \"red delicious\"\n\n[[fruit]]\nname = \"banana\"\n[[fruit.variety]]\nname = \"plantain\"",
  )
  let products = doc.get_array("products").unwrap()
  @debug.assert_eq(products.length(), 3)
  let fruit = doc.get_array("fruit").unwrap()
  @debug.assert_eq(fruit.length(), 2)
  let apple = fruit[0].as_table().unwrap()
  @debug.assert_eq(
    apple.get_path("physical.color").unwrap().as_str(),
    Some("red"),
  )
  @debug.assert_eq(apple.get_array("variety").unwrap().length(), 1)
}

///|
test "duplicate keys are errors" {
  must_fail("a = 1\na = 2")
  must_fail("[fruit]\napple = \"red\"\n[fruit]\napple = \"green\"")
  must_fail("[fruit]\napple.color = \"red\"\n[fruit.apple]")
  must_fail("name = \"Tom\"\nname = \"Pradyun\"")
  must_fail("a.b = 1\na.b = 2")
}

///|
test "table extension rules" {
  // super-table defined after sub-table: valid (implicit tables can be
  // reopened by a header, new keys may be added)
  parse_ok("[x.y.z.w]\n[x]\nq = 43\n")
  // but the implicitly used path may not be redefined as a value
  must_fail("[x.y.z.w]\n[x]\ny = 2\n")
  // redefining a dotted-key table with a header: invalid
  must_fail("[fruit]\napple = \"red\"\n[fruit.apple]\ntexture = \"smooth\"")
  // inline tables are closed
  must_fail("a = {x = 1}\n[a]\ny = 2")
  must_fail("a = {x = 1}\n[a.b]\ny = 2")
  // array of tables then table header: conflict
  must_fail("[[a]]\nb = 1\n[a]\nc = 2")
  // extending a sub-table of a dotted key is fine
  parse_ok(
    "[fruit]\napple.color = \"red\"\n[fruit.apple.texture]\nsmooth = true",
  )
}

///|
test "comments and whitespace" {
  let doc = must_parse(
    "# full line comment\na = 1  # trailing comment\n\n  # indented comment\n\nb = 2",
  )
  @debug.assert_eq(doc.get_int("a"), Some(1L))
  @debug.assert_eq(doc.get_int("b"), Some(2L))
  must_fail("a = 1 extra")
}

///|
test "error positions" {
  let msg = try parse("a = 1\nb = @") catch {
    err => err.message()
  } noraise {
    _ => fail("expected parse error")
  }
  @debug.assert_eq(msg.contains("line 2"), true)
}

///|
test "value fragments via parse_value" {
  @debug.assert_eq(parse_value("1_000").as_int(), Some(1000L))
  @debug.assert_eq(parse_value("[1, 2]").as_array().unwrap().length(), 2)
  @debug.assert_eq(parse_value("1979-05-27T07:32:00Z").type_name(), "datetime")
}
