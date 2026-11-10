///|
test "incremental MD5 matches the million-a published vector" {
  let d = Digest::new()
  let block = Bytes::make(1000, b'a')
  for _i = 0; _i < 1000; _i = _i + 1 {
    d.update(block)
  }
  assert_eq(
    d.finish(),
    b"\x77\x07\xd6\xae\x4e\x02\x7c\x70\xee\xa2\xa9\x35\xc2\x29\x6f\x21",
  )
}

///|
test "streaming repair writes bounded chunks and detects changed sources" {
  let original = b"abcdefghij"
  let volume = create_stream(
    [{ name: "目录/数据", size: 10UL, recoverable: true, }],
    (_, at, n) => original[at.to_int():at.to_int() + n].to_owned(),
    width=4,
    recovery_blocks=3,
  )
  let set = read_set([volume])
  let restored = @buffer.Buffer()
  set.repair_stream(_ => None, (_, _, _) => b"", (_, _, b) => {
    assert_true(b.length() <= 4)
    restored.write_bytes(b)
  })
  assert_eq(restored.to_bytes(), original)
  let mut calls = 0
  assert_true(
    try {
      ignore(
        create_stream(
          [{ name: "x", size: 4UL, recoverable: true, }],
          (_, _, _) => {
            calls = calls + 1
            if calls == 1 {
              b"abcd"
            } else {
              b"ABCD"
            }
          },
          width=4,
        ),
      )
      false
    } catch {
      _ => true
    },
  )
}

///|
test "Unicode Filename overrides fallback and is checked for traversal" {
  let raw = create([("fallback.txt", b"abcd")], width=4)
  let frames = read_packets(raw)
  let desc = frames.filter(fn(p) { p.tag == desc_tag })[0]
  let name = @utf16.encode("目录/🌙.txt", bom=false, endianness=Little)
  let u = write_packet(
    desc.id,
    unicode_tag,
    joined([
      desc.body[:16].to_owned(),
      name,
      Bytes::make((4 - name.length() % 4) % 4, b'\x00'),
    ]),
  )
  let set = read_set([raw, u])
  assert_eq(set.names(), ["目录/🌙.txt"])
  assert_eq(set.repair(Map([])), [("目录/🌙.txt", b"abcd")])
  let bad = @utf16.encode("../outside", bom=false, endianness=Little)
  let hostile = write_packet(
    desc.id,
    unicode_tag,
    joined([
      desc.body[:16].to_owned(),
      bad,
      Bytes::make((4 - bad.length() % 4) % 4, b'\x00'),
    ]),
  )
  assert_true(
    try {
      ignore(read_set([raw, hostile]))
      false
    } catch {
      _ => true
    },
  )
}
