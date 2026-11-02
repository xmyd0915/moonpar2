///|
pub const MaxSourceBytes = 67108864

///|
const MaxSlices = 4096

///|
const MaxFiles = 64

///|
const MaxParity = 32

///|
const MaxWidth = 262144

///|
pub const MaxVolumeBytes = 16777216

///|
pub fn create(
  files : Array[(String, Bytes)],
  width? : Int32,
  recovery_blocks~ : Int32 = 4,
) -> Bytes raise {
  if files.is_empty() || files.length() > MaxFiles {
    fail("expected 1 to 64 files")
  }
  let mut bytes_total = 0
  for item in files {
    if item.1.is_empty() || item.1.length() > MaxSourceBytes - bytes_total {
      fail("empty input or source set exceeds 64 MiB")
    }
    bytes_total = bytes_total + item.1.length()
  }
  let width = width.unwrap_or_else(fn() {
    let mut w = 4096
    if bytes_total > 4194304 {
      while w < MaxWidth && w * 256 < bytes_total {
        w = w * 2
      }
    }
    w
  })
  if width <= 0 || width > MaxWidth || width % 4 != 0 {
    fail("invalid slice size")
  }
  if recovery_blocks < 1 || recovery_blocks > MaxParity {
    fail("expected 1 to 32 recovery slices")
  }
  let names : Map[String, Bool] = Map([])
  let sources : Array[(Member, Bytes)] = []
  let mut slices = 0
  for item in files {
    let (name, bytes) = item
    if !safe_name(name) || names.contains(name.to_lower()) {
      fail("invalid or duplicate source name: " + name)
    }
    names[name.to_lower()] = true
    slices = slices + (bytes.length() + width - 1) / width
    if slices > MaxSlices {
      fail("too many source slices")
    }
    sources.push((describe(name, bytes, width), bytes))
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
  let rows = Array::makei(recovery_blocks, fn(_) { Array::make(width / 2, 0) })
  let bases = slice_bases(slices)
  let mut index = 0
  for entry in sources {
    out.write_bytes(write_packet(set_id, desc_tag, entry.0.desc))
    out.write_bytes(write_packet(set_id, sums_tag, entry.0.sums))
    for at = 0; at < entry.1.length(); at = at + width {
      let block = slice_at(entry.1, at, width)
      for e = 0; e < recovery_blocks; e = e + 1 {
        xor_slice(rows[e], 0, block, power(bases[index], e))
      }
      index = index + 1
    }
  }
  for e = 0; e < recovery_blocks; e = e + 1 {
    let parity = @buffer.Buffer()
    parity.write_int_le(e)
    parity.write_bytes(as_bytes(rows[e]))
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
