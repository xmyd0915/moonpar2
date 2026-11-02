///|
const MaxSourceBytes = 4194304

///|
const MaxSlices = 1024

///|
const MaxFiles = 64

///|
const MaxParity = 32

///|
const MaxWidth = 65536

///|
const MaxVolumeBytes = 16777216

///|
pub fn create(
  files : Array[(String, Bytes)],
  width~ : Int32 = 4096,
  recovery_blocks~ : Int32 = 4,
) -> Bytes raise {
  if files.is_empty() || files.length() > MaxFiles {
    fail("expected 1 to 64 files")
  }
  if width <= 0 || width > MaxWidth || width % 4 != 0 {
    fail("invalid slice size")
  }
  if recovery_blocks < 1 || recovery_blocks > MaxParity {
    fail("expected 1 to 32 recovery slices")
  }
  let names : Map[String, Bool] = {}
  let sources : Array[(Member, Array[Bytes])] = []
  let mut total = 0
  let mut slices = 0
  for item in files {
    let (name, bytes) = item
    if !safe_name(name) || names.contains(name.to_lower()) {
      fail("invalid or duplicate source name: " + name)
    }
    names[name.to_lower()] = true
    if bytes.is_empty() || bytes.length() > MaxSourceBytes - total {
      fail("empty input or source set exceeds 4 MiB")
    }
    total = total + bytes.length()
    slices = slices + (bytes.length() + width - 1) / width
    if slices > MaxSlices {
      fail("too many source slices")
    }
    let blocks = pieces(bytes, width)
    sources.push((describe(name, bytes, blocks), blocks))
  }
  sources.sort_by(fn(a, b) {
    for offset = 15; offset >= 0; offset = offset - 1 {
      let diff = a.0.id[offset].to_int() - b.0.id[offset].to_int()
      if diff != 0 {
        return diff
      }
    }
    0
  })
  let main = @buffer.Buffer()
  main.write_uint64_le(width.to_uint64())
  main.write_int_le(files.length())
  for entry in sources {
    main.write_bytes(entry.0.id)
  }
  let body = main.to_bytes()
  let set_id = md5(body)
  let out = @buffer.Buffer()
  out.write_bytes(write_packet(set_id, main_tag, body))
  out.write_bytes(write_packet(set_id, creator_tag, b"MoonPar2 0.1.0\x00\x00"))
  let words = []
  for entry in sources {
    out.write_bytes(write_packet(set_id, desc_tag, entry.0.desc))
    out.write_bytes(write_packet(set_id, sums_tag, entry.0.sums))
    for block in entry.1 {
      words.push(as_words(block))
    }
  }
  for e = 0; e < recovery_blocks; e = e + 1 {
    let parity = @buffer.Buffer()
    parity.write_int_le(e)
    parity.write_bytes(as_bytes(encode(words, e).unwrap()))
    out.write_bytes(write_packet(set_id, parity_tag, parity.to_bytes()))
  }
  out.to_bytes()
}

///|
test "creation is independent of input order" {
  let one = ("a.txt", b"first")
  let two = ("b.txt", b"second")
  assert_eq(create([one, two], width=4), create([two, one], width=4))
  let packets = read_packets(create([one, two], width=4))
  assert_eq(packets.length(), 10)
}
