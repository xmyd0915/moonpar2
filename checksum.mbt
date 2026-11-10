///|
fn le32(data : BytesView, at : Int32) -> UInt32 {
  let mut value = 0U
  for j = 0; j < 4; j = j + 1 {
    value = value | (data[at + j].to_uint() << (8 * j))
  }
  value
}

///|
let crc_table : FixedArray[UInt32] = FixedArray::makei(256, fn(i) {
  let mut x = i.reinterpret_as_uint()
  for bit = 0; bit < 8; bit = bit + 1 {
    x = (x >> 1) ^ (if (x & 1U) != 0U { 0xedb88320U } else { 0U })
  }
  x
})

///|
fn crc32(data : BytesView) -> UInt32 {
  let mut crc = 0xffffffffU
  for byte in data {
    crc = (crc >> 8) ^
      crc_table[((crc ^ byte.to_uint()) & 255U).reinterpret_as_int()]
  }
  crc ^ 0xffffffffU
}

// RFC 1321 constants, floor(2^32 * abs(sin(i+1))).

///|
let md5_constants : Array[UInt32] = [
  0xd76aa478U, 0xe8c7b756U, 0x242070dbU, 0xc1bdceeeU, 0xf57c0fafU, 0x4787c62aU, 0xa8304613U,
  0xfd469501U, 0x698098d8U, 0x8b44f7afU, 0xffff5bb1U, 0x895cd7beU, 0x6b901122U, 0xfd987193U,
  0xa679438eU, 0x49b40821U, 0xf61e2562U, 0xc040b340U, 0x265e5a51U, 0xe9b6c7aaU, 0xd62f105dU,
  0x2441453U, 0xd8a1e681U, 0xe7d3fbc8U, 0x21e1cde6U, 0xc33707d6U, 0xf4d50d87U, 0x455a14edU,
  0xa9e3e905U, 0xfcefa3f8U, 0x676f02d9U, 0x8d2a4c8aU, 0xfffa3942U, 0x8771f681U, 0x6d9d6122U,
  0xfde5380cU, 0xa4beea44U, 0x4bdecfa9U, 0xf6bb4b60U, 0xbebfbc70U, 0x289b7ec6U, 0xeaa127faU,
  0xd4ef3085U, 0x4881d05U, 0xd9d4d039U, 0xe6db99e5U, 0x1fa27cf8U, 0xc4ac5665U, 0xf4292244U,
  0x432aff97U, 0xab9423a7U, 0xfc93a039U, 0x655b59c3U, 0x8f0ccc92U, 0xffeff47dU, 0x85845dd1U,
  0x6fa87e4fU, 0xfe2ce6e0U, 0xa3014314U, 0x4e0811a1U, 0xf7537e82U, 0xbd3af235U, 0x2ad7d2bbU,
  0xeb86d391U,
]

///|
let rotations : Array[Int32] = [
  7, 12, 17, 22, 5, 9, 14, 20, 4, 11, 16, 23, 6, 10, 15, 21,
]

///|
fn minimum(a : UInt64, b : UInt64) -> UInt64 {
  if a < b {
    a
  } else {
    b
  }
}

///|
priv struct Digest {
  state : Array[UInt32]
  mut total : UInt64
  tail : Array[Byte]
}

///|
fn Digest::new() -> Digest {
  {
    state: [0x67452301U, 0xefcdab89U, 0x98badcfeU, 0x10325476U],
    total: 0UL,
    tail: [],
  }
}

///|
fn compress(state : Array[UInt32], words : FixedArray[UInt32]) -> Unit {
  let mut a = state[0]
  let mut b = state[1]
  let mut c = state[2]
  let mut d = state[3]
  for i = 0; i < 64; i = i + 1 {
    let (f, g) = if i < 16 {
      ((b & c) | ((b ^ 0xffffffffU) & d), i)
    } else if i < 32 {
      ((d & b) | ((d ^ 0xffffffffU) & c), (5 * i + 1) % 16)
    } else if i < 48 {
      (b ^ c ^ d, (3 * i + 5) % 16)
    } else {
      (c ^ (b | (d ^ 0xffffffffU)), 7 * i % 16)
    }
    let t = a + f + md5_constants[i] + words[g]
    let s = rotations[i / 16 * 4 + i % 4]
    let next = b + ((t << s) | (t >> (32 - s)))
    a = d
    d = c
    c = b
    b = next
  }
  state[0] = state[0] + a
  state[1] = state[1] + b
  state[2] = state[2] + c
  state[3] = state[3] + d
}

///|
fn Digest::update(self : Digest, data : BytesView) -> Unit {
  self.total = self.total + data.length().to_uint64()
  let words = FixedArray::make(16, 0U)
  let mut pos = 0
  if !self.tail.is_empty() {
    while self.tail.length() < 64 && pos < data.length() {
      self.tail.push(data[pos])
      pos = pos + 1
    }
    if self.tail.length() == 64 {
      let block = Bytes::makei(64, fn(i) { self.tail[i] })
      for i = 0; i < 16; i = i + 1 {
        words[i] = le32(block, i * 4)
      }
      compress(self.state, words)
      self.tail.clear()
    }
  }
  while pos + 64 <= data.length() {
    for i = 0; i < 16; i = i + 1 {
      words[i] = le32(data, pos + i * 4)
    }
    compress(self.state, words)
    pos = pos + 64
  }
  while pos < data.length() {
    self.tail.push(data[pos])
    pos = pos + 1
  }
}

///|
fn Digest::finish(self : Digest) -> Bytes {
  let bits = self.total * 8UL
  let padding = @buffer.Buffer()
  padding.write_byte(b'\x80')
  let zeros = (119 - self.tail.length()) % 64
  for _i = 0; _i < zeros; _i = _i + 1 {
    padding.write_byte(b'\x00')
  }
  padding.write_uint64_le(bits)
  self.update(padding.to_bytes())
  let out = @buffer.Buffer()
  for word in self.state {
    out.write_uint_le(word)
  }
  out.to_bytes()
}

///|
fn md5(data : BytesView) -> Bytes {
  let d = Digest::new()
  d.update(data)
  d.finish()
}

///|
test "published MD5 and CRC32 vectors" {
  assert_eq(
    md5(b"abc"),
    b"\x90\x01\x50\x98\x3c\xd2\x4f\xb0\xd6\x96\x3f\x7d\x28\xe1\x7f\x72",
  )
  assert_eq(crc32(b"123456789"), 0xcbf43926U)
}
