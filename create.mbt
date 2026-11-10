///|
pub const MaxSourceBytes = 268435456

///|
const MaxSlices = 32768

///|
const MaxFiles = 4096

///|
const MaxParity = 32

///|
const MaxWidth = 262144

///|
pub const MaxVolumeBytes = 67108864

///|
pub fn create(
  files : Array[(String, Bytes)],
  width? : Int32,
  recovery_blocks~ : Int32 = 4,
  non_recovery_files~ : Array[(String, Bytes)] = [],
) -> Bytes raise {
  let all = files.copy()
  for item in non_recovery_files {
    all.push(item)
  }
  if all.is_empty() || all.length() > MaxFiles {
    fail("expected 1 to 4096 files")
  }
  let mut bytes_total = 0
  for item in all {
    if item.1.length() > MaxSourceBytes - bytes_total {
      fail("source set exceeds 256 MiB")
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
  let mut described_slices = 0
  for i = 0; i < all.length(); i = i + 1 {
    let item = all[i]
    let (name, bytes) = item
    claim_path(names, name)
    let recoverable = i < files.length()
    described_slices = described_slices + (bytes.length() + width - 1) / width
    if described_slices > MaxSlices {
      fail("too many metadata slices")
    }
    if recoverable {
      slices = slices + (bytes.length() + width - 1) / width
    }
    if slices > MaxSlices {
      fail("too many source slices")
    }
    sources.push((describe(name, bytes, width, recoverable~), bytes))
  }
  sources.sort_by(fn(a, b) {
    if a.0.recoverable != b.0.recoverable {
      return if a.0.recoverable { -1 } else { 1 }
    }
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
  let metadata = @buffer.Buffer()
  metadata.write_bytes(write_packet(set_id, main_tag, body))
  let creator = @utf8.encode(
    "MoonPar2 0.2.0 https://github.com/xmyd0915/moonpar2",
  )
  let padded_creator = Bytes::makei((creator.length() + 3) / 4 * 4, fn(i) {
    if i < creator.length() {
      creator[i]
    } else {
      b'\x00'
    }
  })
  out.write_bytes(write_packet(set_id, creator_tag, padded_creator))
  let rows = Array::makei(recovery_blocks, fn(_) { Array::make(width / 2, 0) })
  let bases = slice_bases(slices)
  let mut index = 0
  for entry in sources {
    metadata.write_bytes(write_packet(set_id, desc_tag, entry.0.desc))
    metadata.write_bytes(write_packet(set_id, sums_tag, entry.0.sums))
    if !entry.0.recoverable {
      continue
    }
    for at = 0; at < entry.1.length(); at = at + width {
      let block = slice_at(entry.1, at, width)
      for e = 0; e < recovery_blocks; e = e + 1 {
        xor_slice(rows[e], 0, block, power(bases[index], e))
      }
      index = index + 1
    }
  }
  let critical = metadata.to_bytes()
  out.write_bytes(critical)
  for e = 0; e < recovery_blocks; e = e + 1 {
    let parity = @buffer.Buffer()
    parity.write_int_le(e)
    parity.write_bytes(as_bytes(rows[e]))
    out.write_bytes(write_packet(set_id, parity_tag, parity.to_bytes()))
  }
  // A second copy survives loss of a critical packet in a single-volume set.
  out.write_bytes(critical)
  out.to_bytes()
}

///|
test "creation is independent of input order" {
  let one = ("a.txt", b"first")
  let two = ("b.txt", b"second")
  assert_eq(create([one, two], width=4), create([two, one], width=4))
  let packets = read_packets(create([one, two], width=4))
  assert_eq(packets.filter(fn(p) { p.tag == main_tag }).length(), 2)
}
