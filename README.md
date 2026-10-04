# moonbit-toml

A [TOML v1.0.0](https://toml.io/en/v1.0.0) parser and serializer for [MoonBit](https://www.moonbitlang.com), with **full compliance** against the official [toml-test](https://github.com/toml-lang/toml-test) v1.0.0 suite.

Published on mooncakes.io as [`sa2360/toml`](https://mooncakes.io/docs/#/sa2360/toml/).

```bash
moon add sa2360/toml
```

## Highlights

- **100% toml-test v1.0.0 compliance** — all 96 valid and 185 invalid cases of the official suite pass. The suite is embedded in the repo: `moon test` alone runs all 275 conformance cases plus unit tests.
- **Round-trip guarantee** — every valid suite case is additionally parsed → encoded → re-parsed and required to be structurally equal.
- **Order-preserving tables** — key definition order is kept, so encoding is stable and diffs are readable.
- **Precise errors** — every parse failure carries a 1-based line/column and a structured cause (`UnexpectedChar`, `DuplicateKey`, `TableConflict`, …).
- **Strict UTF-8** — the bundled `toml2json` CLI validates UTF-8 byte sequences (rejecting surrogates, overlong forms and out-of-range code points).
- Pure MoonBit, no FFI. Works on wasm, wasm-gc, js and native backends.

## Usage

```moonbit
// moon.mod: import { "sa2360/toml" }
```

### Parsing

```moonbit
let doc = @toml.parse("title = \"Example\"\n[owner]\nname = \"Tom\"")
doc.get_string("title")            // Some("Example")
doc.get_path("owner.name")         // Some(Str("Tom")) — dotted path lookup
doc.get_int("port")                // Option[Int64]
doc.get_double / get_bool / get_array / get_table / get_datetime
```

`parse` raises a structured `ParseError`; `err.message()` renders e.g.
`line 3, column 5: duplicate key 'apple'`. Single values can be decoded with
`@toml.parse_value("1_000")`.

### Serializing

```moonbit
let text = @toml.encode(doc)        // full document ([table] sections, [[array of tables]])
let inline = @toml.encode_value(v)  // a single value in inline form
```

`encode` writes sub-tables as `[a.b]` sections and arrays of tables as
`[[a.b]]`, preserving first-definition key order. The output round-trips.

### JSON interop

```moonbit
let json = value.to_json()          // -> moonbitlang/core Json
let text = value.to_json_string()   // compact JSON string
let back = @toml.Value::from_json(json)  // JSON -> TOML (raises on null)
```

`to_json`: integers keep full 64-bit precision through their textual
representation, datetimes become strings in canonical TOML notation, and
`inf` / `-inf` / `nan` become the strings `"inf"` / `"-inf"` / `"nan"`
(JSON has no representation for them). `Value` implements the standard
`ToJson`, `Eq` and `Debug` traits.

`from_json` conventions: JSON `null` raises `FromJsonError::JsonNull`;
integral numbers within 64-bit range become integers (so JSON `2.0`
reads back as the integer `2` — JSON cannot distinguish them); JSON
strings never become datetimes.

A runnable demo lives in `cmd/example`: `moon run cmd/example`.

### Value model

```moonbit
pub(all) enum Value {
  Str(String); Int(Int64); Float(Double); Bool(Bool)
  Datetime(Datetime); Array(Array[Value]); Table(Table)
}
```

TOML integers are 64-bit signed. Datetimes keep their four forms
(`datetime`, `datetime-local`, `date-local`, `time-local`) as components;
sub-second precision is stored as nanoseconds (input beyond 9 digits is
truncated). `Value::equal` compares structurally: tables order-insensitively,
`NaN` equals `NaN`, `Z` equals `+00:00`.

## The CLI

```bash
moon build --target native cmd/toml2json
_build/native/debug/build/cmd/toml2json/toml2json.exe config.toml
```

Prints the document as [toml-test protocol](https://github.com/toml-lang/toml-test#the-protocol)
tagged JSON (`{"type": "integer", "value": "42"}`), exiting non-zero with a
positioned error message on invalid input.

## Testing

```bash
moon test                        # 316 tests: unit + embedded toml-test suite + doc examples
moon test --target native        # same suite on the native backend
moon bench                       # parse / encode / to_json benchmarks (+ core JSON reference)
moon build --target native cmd/toml2json
python scripts/run_toml_test.py  # official protocol runner over the CLI (281 cases)
```

Nesting of arrays and inline tables is bounded at 200 levels
(`MAX_NESTING_DEPTH`): hostile inputs fail with a positioned error
instead of exhausting the stack.

On a 2026 laptop (wasm backend), parsing a ~1400-line / 200-section
synthetic document takes about 1.8 ms, re-encoding it about 0.5 ms. The
same document parsed by moonbitlang/core's JSON parser takes ~0.5 ms —
JSON is a much simpler grammar (and the core parser is heavily
optimized), which is the honest reference point; for configuration-sized
inputs the difference is negligible.

The conformance cases are generated from the vendored suite in
`toml-test-tests/` ([Apache-2.0](./toml-test-tests/COPYING)) by
`scripts/gen_conformance.py`, which converts toml-test's expected tagged JSON
into MoonBit value literals at generation time.

## Layout

```
value.mbt            Value / Table / Datetime model, accessors, equality
error.mbt            Position, ParseErrorData, ParseError
scanner.mbt          cursor, whitespace/comment/newline handling, char classes
strings.mbt          the four string kinds and escape validation
numbers.mbt          integers, floats, datetimes (with range checks)
parser.mbt           document/table/keyval/array/inline-table + definition rules
encode.mbt           serializer (documents and inline values)
json.mbt             JSON interop (to_json, ToJson impl)
cmd/toml2json/       native CLI emitting toml-test tagged JSON
cmd/example/         runnable demo: parse, read, re-encode, convert to JSON
scripts/             conformance generator + CLI runner
toml-test-tests/     vendored official suite (v1.0.0)
```

## License

MIT — see [LICENSE](./LICENSE). The vendored `toml-test-tests/` suite is
Apache-2.0, Copyright the toml-test authors.

---

## moonbit-toml(中文说明)

面向 [MoonBit](https://www.moonbitlang.com) 的 [TOML v1.0.0](https://toml.io/en/v1.0.0) 解析与序列化库,通过官方 [toml-test](https://github.com/toml-lang/toml-test) v1.0.0 全量合规测试(96 个 valid + 185 个 invalid 用例,100%)。已发布到 [mooncakes.io](https://mooncakes.io/docs/#/sa2360/toml/):`moon add sa2360/toml`。

### 特性

- **官方套件全量合规**:测试集已内嵌进仓库,`moon test` 一条命令即可运行全部 275 个合规用例与单元测试(共 299 个);
- **往返保证**:每个 valid 用例都会执行 解析 → 序列化 → 再解析,要求结果结构相等;
- **保序表**:保留键的首定义顺序,序列化输出稳定;
- **精确错误**:每个解析错误都带 1-based 行号/列号与结构化原因(如 `DuplicateKey`、`TableConflict`);
- **严格 UTF-8**:CLI 校验字节序列(拒绝代理区、超长编码、越界码点);
- 纯 MoonBit 实现,无 FFI,wasm / native 双端行为一致。

### 快速上手

```moonbit
let doc = @toml.parse("title = \"Example\"\n[owner]\nname = \"Tom\"")
doc.get_string("title")     // Some("Example")
doc.get_path("owner.name")  // Some(Str("Tom"))

let text = @toml.encode(doc) // 序列化回 TOML 文档
let json = @toml.Value::Table(doc).to_json_string() // 转 JSON(整数精度无损)
```

错误处理采用 MoonBit 惯用的 raise 风格:

```moonbit
let doc = @toml.parse(input) catch {
  err => println(err.message()) // 例如:line 3, column 5: duplicate key 'apple'
}
```

- **可解释的 API 文档**:核心函数带有由 `moon check`/`moon test` 校验的文档示例(```mbt check),mooncakes 文档页直接渲染;
- `Value` 实现了标准 `Eq` / `Debug` trait(表序无关、NaN 相等、Z 等价 +00:00),可直接用于 `@debug.assert_eq`;

可运行的示例在 `cmd/example`:`moon run cmd/example`。

### 测试

```bash
moon test                        # 316 个测试:单元测试 + 内嵌 toml-test 全量套件 + 文档示例
moon test --target native        # 同一套件在 native 后端
moon bench                       # parse / encode / to_json 基准(含 core JSON 参照)
moon build --target native cmd/toml2json
python scripts/run_toml_test.py  # 官方协议 runner(281 个用例,含字节级 UTF-8 用例)
```

数组与内联表的嵌套深度上限为 200 层(`MAX_NESTING_DEPTH`),恶意输入会得到带行列号的报错而不是栈溢出崩溃。

性能参考(wasm 后端,约 1400 行 / 200 节合成文档):parse 约 1.8ms,encode 约 0.5ms;同一文档 core 的 JSON 解析器约 0.5ms——JSON 语法简单得多且核心库深度优化,这是如实的参照点,配置文件体量下差异可忽略。

### 已知取舍

- 日期时间中小数秒超过 9 位时按纳秒截断(输出侧尾部零会被规范化);
- `Table::get_path` 按字面 `.` 分段,无法寻址“名字本身带点且需要引号”的键;
- 多行字符串中的 CRLF 统一归一化为 LF(TOML 规范明确允许实现自行归一化);
- 日期时间中秒不可省略(RFC 3339 的 partial-time 允许省略仅适用于纯时间值,如 `07:32`)。

## License

MIT(见 [LICENSE](./LICENSE));内嵌的 `toml-test-tests/` 测试集为 Apache-2.0,版权归 toml-test 作者所有。
