///|
priv struct Member {
  id : Bytes
  name : String
  length : UInt64
  hash : Bytes
  desc : Bytes
  sums : Bytes
  recoverable : Bool
}

///|
pub fn safe_name(name : String) -> Bool {
  if name.is_empty() ||
    name.length() > 255 ||
    name == "." ||
    name == ".." ||
    name.has_suffix(".") ||
    name.has_suffix(" ") {
    return false
  }
  for c in name {
    if c < ' ' ||
      c == '\u007f' ||
      ['/', '\\', ':', '<', '>', '"', '|', '?', '*'].contains(c) {
      return false
    }
  }
  let mut base = name.to_lower().split(".").next().unwrap().to_owned()
  while base.has_suffix(" ") {
    base = base[:base.length() - 1].to_owned()
  }
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
/// Portable, root-relative PAR2 path. Never accepts an absolute or parent path.
pub fn safe_path(path : String) -> Bool {
  if path.is_empty() || path.length() > 4096 {
    return false
  }
  let parts = path.split("/").to_array()
  if parts.length() > 64 {
    return false
  }
  for part in parts {
    if !safe_name(part.to_owned()) {
      return false
    }
  }
  true
}

///|
fn claim_path(names : Map[String, Bool], path : String) -> Unit raise {
  if !safe_path(path) {
    fail("unsafe or unsupported relative path: " + path)
  }
  let key = path.to_lower()
  if names.contains(key) {
    fail("duplicate or case-colliding path: " + path)
  }
  for old, _ in names {
    if key.has_prefix(old + "/") || old.has_prefix(key + "/") {
      fail("file/directory path collision: " + path)
    }
  }
  names[key] = true
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
test "portable names and partial slice padding" {
  assert_true(safe_name("photo 1.jpg"))
  for bad in ["../x", "NUL.txt", ".", "AUX", "COM1.cfg", "a/b", "a:"] {
    assert_false(safe_name(bad))
  }
  assert_eq(slice_at(b"12345", 4, 4).to_owned(), b"5\x00\x00\x00")
}
