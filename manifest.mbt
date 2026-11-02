///|
priv struct Member {
  id : Bytes
  name : String
  length : Int32
  hash : Bytes
  desc : Bytes
  sums : Bytes
}

///|
pub fn safe_name(name : String) -> Bool {
  if name.is_empty() ||
    name.length() > 180 ||
    name.has_prefix(".") ||
    name.has_suffix(".") ||
    name.has_suffix(" ") {
    return false
  }
  for c in name {
    if !((c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '-' ||
      c == '_' ||
      c == '.' ||
      c == ' ') {
      return false
    }
  }
  let base = name.to_lower().split(".").next().unwrap().to_owned()
  if ["con", "prn", "aux", "nul"].contains(base) {
    return false
  }
  for i = 0; i <= 9; i = i + 1 {
    if base == "com\{i}" || base == "lpt\{i}" {
      return false
    }
  }
  true
}

///|
fn pieces(data : Bytes, width : Int32) -> Array[Bytes] {
  Array::makei((data.length() + width - 1) / width, fn(i) {
    Bytes::makei(width, fn(j) {
      let at = i * width + j
      if at < data.length() {
        data[at]
      } else {
        b'\x00'
      }
    })
  })
}

///|
fn as_words(block : Bytes) -> Array[Int32] {
  Array::makei(block.length() / 2, fn(i) {
    block[i * 2].to_int() | (block[i * 2 + 1].to_int() << 8)
  })
}

///|
fn as_bytes(words : Array[Int32]) -> Bytes {
  Bytes::makei(words.length() * 2, fn(i) {
    (words[i / 2] >> (8 * (i % 2))).to_byte()
  })
}

///|
fn describe(name : String, data : Bytes, blocks : Array[Bytes]) -> Member {
  let prefix = md5(data[:data.length().min(16384)].to_owned())
  let buf = @buffer.Buffer()
  buf.write_bytes(prefix)
  buf.write_uint64_le(data.length().to_uint64())
  let filename = @utf8.encode(name)
  buf.write_bytes(filename)
  let id = md5(buf.to_bytes())
  for i = 0; i < (4 - filename.length() % 4) % 4; i = i + 1 {
    buf.write_byte(b'\x00')
  }
  let hash = md5(data)
  let desc = joined([id, hash, buf.to_bytes()])
  let sums = @buffer.Buffer()
  sums.write_bytes(id)
  for b in blocks {
    sums.write_bytes(md5(b))
    sums.write_uint_le(crc32(b))
  }
  { id, name, length: data.length(), hash, desc, sums: sums.to_bytes(), }
}

///|
test "portable names and partial slice padding" {
  assert_true(safe_name("photo 1.jpg"))
  for bad in ["../x", "NUL.txt", ".", "AUX", "COM1.cfg", "a/b", "a:"] {
    assert_false(safe_name(bad))
  }
  assert_eq(pieces(b"12345", 4), [b"1234", b"5\x00\x00\x00"])
}
