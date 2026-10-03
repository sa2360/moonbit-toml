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
