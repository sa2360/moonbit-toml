// Copyright 2026 moonbit-toml contributors
//
// SPDX-License-Identifier: MIT

///|
/// A synthetic document: 200 sections with the common TOML types.
let bench_source : String = {
  let sb = StringBuilder::StringBuilder()
  sb.write_string(
    "title = \"toml benchmark\"\nowner = { name = \"bench\", id = 1 }\n",
  )
  for i in 0..<200 {
    sb.write_string(
      "\n[section_\{i}]\nname = \"item \{i}\"\nid = \{i}\nratio = 0.\{i}25\nactive = true\nports = [8080, 9090, \{i}]\nstamp = 2026-10-03T12:00:00Z\ntags = [\"a\", \"b\", \"c\"]\n",
    )
  }
  sb.to_string()
}

///|
test "bench parse 200-section document" (it : @bench.T) {
  it.bench(fn() {
    it.keep(parse(bench_source) catch { _ => abort("bench parse failed") })
  })
}

///|
test "bench encode 200-section document" (it : @bench.T) {
  let doc = parse(bench_source)
  it.bench(fn() { it.keep(encode(doc)) })
}

///|
test "bench to_json 200-section document" (it : @bench.T) {
  let doc = parse(bench_source)
  it.bench(fn() { it.keep(Value::Table(doc).to_json_string()) })
}

///|
/// The same logical document serialized as JSON, for an in-ecosystem
/// comparison against moonbitlang/core's JSON parser.
let bench_source_json : String = {
  let sb = StringBuilder::StringBuilder()
  sb.write_string(
    "{\"title\":\"toml benchmark\",\"owner\":{\"name\":\"bench\",\"id\":1}",
  )
  for i in 0..<200 {
    sb.write_string(
      ",\"section_\{i}\":{\"name\":\"item \{i}\",\"id\":\{i},\"ratio\":0.\{i}25,\"active\":true,\"ports\":[8080,9090,\{i}],\"stamp\":\"2026-10-03T12:00:00Z\",\"tags\":[\"a\",\"b\",\"c\"]}",
    )
  }
  sb.write_string("}")
  sb.to_string()
}

///|
test "bench json parse (same document, core json) " (it : @bench.T) {
  it.bench(fn() {
    it.keep(
      @json.parse(bench_source_json) catch {
        _ => abort("json parse failed")
      },
    )
  })
}
