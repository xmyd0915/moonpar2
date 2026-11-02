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
fn slice_at(data : Bytes, start : Int32, width : Int32) -> BytesView {
  if data.length() - start >= width {
    return data[start:start + width]
  }
  let padded = Bytes::makei(width, fn(j) {
    if start + j < data.length() {
      data[start + j]
    } else {
      b'\x00'
    }
  })
  padded[:]
}

///|
fn xor_slice(
  row : Array[Int32],
  offset : Int32,
  data : BytesView,
  factor : Int32,
) -> Unit {
  if factor == 0 {
    return
  }
  let log = field_logs[factor]
  for j = 0; j < data.length() / 2; j = j + 1 {
    let word = data[j * 2].to_int() | (data[j * 2 + 1].to_int() << 8)
    if word != 0 {
      let e = log + field_logs[word]
      row[offset + j] = row[offset + j] ^
        field_powers[if e >= 65535 { e - 65535 } else { e }]
    }
  }
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
fn describe(name : String, data : Bytes, width : Int32) -> Member {
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
  for at = 0; at < data.length(); at = at + width {
    let b = slice_at(data, at, width)
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
  assert_eq(slice_at(b"12345", 4, 4).to_owned(), b"5\x00\x00\x00")
}
