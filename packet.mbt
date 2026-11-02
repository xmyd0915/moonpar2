///|
let magic = b"PAR2\x00PKT"

///|
let main_tag = b"PAR 2.0\x00Main\x00\x00\x00\x00"

///|
let desc_tag = b"PAR 2.0\x00FileDesc"

///|
let sums_tag = b"PAR 2.0\x00IFSC\x00\x00\x00\x00"

///|
let parity_tag = b"PAR 2.0\x00RecvSlic"

///|
let creator_tag = b"PAR 2.0\x00Creator\x00"

///|
struct Packet {
  id : Bytes
  tag : Bytes
  body : Bytes
}

///|
fn joined(parts : Array[Bytes]) -> Bytes {
  let buf = @buffer.Buffer()
  for part in parts {
    buf.write_bytes(part)
  }
  buf.to_bytes()
}

///|
fn write_packet(id : Bytes, tag : Bytes, body : Bytes) -> Bytes {
  let content = joined([id, tag, body])
  let buf = @buffer.Buffer()
  buf.write_bytes(magic)
  buf.write_uint64_le((64 + body.length()).to_uint64())
  buf.write_bytes(md5(content))
  buf.write_bytes(content)
  buf.to_bytes()
}

///|
fn read_packets(raw : Bytes) -> Array[Packet] raise {
  let out = []
  let mut p = 0
  while p < raw.length() {
    if raw.length() - p < 64 || raw[p:p + 8].to_owned() != magic {
      fail("invalid PAR2 packet header")
    }
    let len = le32(raw, p + 8).reinterpret_as_int()
    if len < 64 ||
      len % 4 != 0 ||
      len > raw.length() - p ||
      le32(raw, p + 12) != 0U {
      fail("invalid packet length")
    }
    let end = p + len
    if md5(raw[p + 32:end].to_owned()) != raw[p + 16:p + 32].to_owned() {
      fail("packet checksum mismatch")
    }
    out.push({
      id: raw[p + 32:p + 48].to_owned(),
      tag: raw[p + 48:p + 64].to_owned(),
      body: raw[p + 64:end].to_owned(),
    })
    p = end
  }
  out
}

///|
test "a flipped packet body fails validation" {
  let id = Bytes::make(16, b'0')
  let raw = write_packet(id, main_tag, b"abcd")
  assert_eq(read_packets(raw)[0].body, b"abcd")
  let changed = joined([raw[:raw.length() - 1].to_owned(), b"X"])
  let ok = try {
    ignore(read_packets(changed))
    false
  } catch {
    _ => true
  }
  assert_true(ok)
}
