// Copyright 2026 moonbit-toml contributors
//
// SPDX-License-Identifier: MIT

///|
/// A small end-to-end demo of the library: parse a document, read values,
/// re-encode it, and convert it to JSON.
///
/// Run with: `moon run cmd/example`
fn main raise {
  let src =
    #|  # 服务配置示例
    #|  title = "demo"
    #|
    #|  [server]
    #|  host = "127.0.0.1"
    #|  port = 8080
    #|  tags = ["alpha", "beta"]
    #|
    #|  [[users]]
    #|  name = "Alice"
    #|  admin = true
    #|
    #|  [[users]]
    #|  name = "Bob"
    #|  admin = false
    #|  joined = 2026-10-03T09:30:00Z
  let doc = @toml.parse(src)

  println("== 读取字段 ==")
  println("server.host  = " + @toml.encode_value(read(doc, "server.host")))
  println("server.port  = " + @toml.encode_value(read(doc, "server.port")))
  let users = doc.get_array("users").unwrap()
  println("users.length = " + users.length().to_string())
  println(
    "users[0].name = " +
    users[0].as_table().unwrap().get_string("name").unwrap_or("<missing>"),
  )
  let bob = users[1].as_table().unwrap()
  println(
    "users[1].joined = " +
    @toml.encode_datetime(bob.get_datetime("joined").unwrap()),
  )

  println("")
  println("== 重新序列化 ==")
  println(@toml.encode(doc))

  println("== 转 JSON ==")
  println(@toml.Value::Table(doc).to_json_string())
}

///|
/// Dotted-path lookup with a fallback value.
fn read(doc : @toml.Table, path : String) -> @toml.Value {
  doc.get_path(path).unwrap_or(@toml.Value::Str("<missing>"))
}
