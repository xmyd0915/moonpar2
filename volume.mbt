///|
struct RecoverySet {
  width : Int32
  members : Array[Member]
  parity : Map[Int32, Array[Int32]]
  notices : Array[String]
  producers : Array[String]
}

///|
pub fn RecoverySet::warnings(self : RecoverySet) -> Array[String] {
  self.notices.copy()
}

///|
pub fn RecoverySet::creators(self : RecoverySet) -> Array[String] {
  self.producers.copy()
}

///|
pub fn RecoverySet::recovery_blocks(self : RecoverySet) -> Int32 {
  self.parity.length()
}

///|
pub fn RecoverySet::names(self : RecoverySet) -> Array[String] {
  self.members.map(fn(m) { m.name })
}

///|
fn record(map : Map[Bytes, Bytes], body : Bytes) -> Unit raise {
  if body.length() < 16 {
    fail("short member packet")
  }
  let id = body[:16].to_owned()
  if map.get(id) is Some(old) && old != body {
    fail("conflicting member packets")
  }
  map[id] = body
}

///|
pub fn read_set(volumes : Array[Bytes]) -> RecoverySet raise {
  let producers = []
  read_set_impl(volumes, producers) catch {
    e => fail(e.to_string() + "; creators: " + producers.join("; "))
  }
}

///|
fn read_set_impl(
  volumes : Array[Bytes],
  producers : Array[String],
) -> RecoverySet raise {
  let mut total = 0
  let mut main : Bytes? = None
  let mut id : Bytes? = None
  let descriptors : Map[Bytes, Bytes] = Map([])
  let sums : Map[Bytes, Bytes] = Map([])
  let raw_parity : Map[Int32, Bytes] = Map([])
  let notices = []
  for vi = 0; vi < volumes.length(); vi = vi + 1 {
    let volume = volumes[vi]
    if volume.length() > MaxVolumeBytes - total {
      fail("recovery volumes exceed 64 MiB")
    }
    total = total + volume.length()
    let scanned = scan_packets(volume)
    if scanned.skipped > 0 {
      notices.push(
        "volume \{vi + 1}: skipped \{scanned.skipped} damaged or non-packet bytes",
      )
    }
    for packet in scanned.packets {
      if packet.tag == creator_tag {
        let mut end = packet.body.length()
        while end > 0 && packet.body[end - 1] == b'\x00' {
          end = end - 1
        }
        let text = @utf8.decode(packet.body[:end]) catch {
          _ => "<invalid creator text>"
        }
        if !producers.contains(text) {
          producers.push(text)
        }
        continue
      }
      if packet.tag != main_tag &&
        packet.tag != desc_tag &&
        packet.tag != sums_tag &&
        packet.tag != parity_tag {
        continue
      }
      if id is Some(old) && old != packet.id {
        fail("different recovery sets")
      }
      id = Some(packet.id)
      let b = packet.body
      if packet.tag == main_tag {
        if main is Some(old) && old != b {
          fail("conflicting main packets")
        }
        main = Some(b)
      } else if packet.tag == desc_tag {
        record(descriptors, b)
      } else if packet.tag == sums_tag {
        record(sums, b)
      } else if packet.tag == parity_tag {
        if b.length() < 8 {
          fail("short recovery packet")
        }
        let exp = le32(b, 0)
        if exp > 65535U {
          fail("invalid exponent")
        }
        let key = exp.reinterpret_as_int()
        if raw_parity.get(key) is Some(old) && old != b {
          fail("conflicting recovery slices")
        }
        raw_parity[key] = b
        if raw_parity.length() > MaxParity {
          fail("too many recovery slices")
        }
      }
    }
  }
  guard main is Some(header) else {
    fail("missing main packet; creators: " + producers.join("; "))
  }
  if header.length() < 12 || (header.length() - 12) % 16 != 0 {
    fail("invalid main packet")
  }
  let width = le32(header, 0).reinterpret_as_int()
  let count = le32(header, 8).reinterpret_as_int()
  let total_files = (header.length() - 12) / 16
  if le32(header, 4) != 0U ||
    width <= 0 ||
    width > MaxWidth ||
    width % 4 != 0 ||
    count < 0 ||
    total_files < 1 ||
    total_files > MaxFiles ||
    count > total_files {
    fail("unsupported set dimensions")
  }
  let members = []
  let names : Map[String, Bool] = Map([])
  let mut source_total = 0
  let mut slices = 0
  let ids : Map[Bytes, Bool] = Map([])
  for i = 0; i < total_files; i = i + 1 {
    let fid = header[12 + i * 16:28 + i * 16].to_owned()
    if ids.contains(fid) {
      fail("duplicate file identifier")
    }
    ids[fid] = true
    guard descriptors.get(fid) is Some(desc) else {
      fail("missing file description")
    }
    let recoverable = i < count
    let checks = sums.get(fid).unwrap_or(fid)
    if desc.length() <= 56 {
      fail("invalid description")
    }
    let length = le32(desc, 48).reinterpret_as_int()
    if length < 0 ||
      le32(desc, 52) != 0U ||
      length > MaxSourceBytes - source_total {
      fail("unsupported file length")
    }
    source_total = source_total + length
    let blocks = (length + width - 1) / width
    if recoverable {
      slices = slices + blocks
    }
    if slices > MaxSlices ||
      (recoverable && checks.length() != 16 + 20 * blocks) {
      fail("invalid slice count")
    }
    let mut end = desc.length()
    while end > 56 && desc[end - 1] == b'\x00' {
      end = end - 1
    }
    if desc.length() - end > 3 || md5(desc[32:end].to_owned()) != fid {
      fail("invalid file identifier")
    }
    let name = @utf8.decode(desc[56:end])
    claim_path(names, name)
    members.push({
      id: fid,
      name,
      length,
      hash: desc[16:32].to_owned(),
      desc,
      sums: checks,
      recoverable,
    })
  }
  let parity : Map[Int32, Array[Int32]] = Map([])
  for exp, body in raw_parity {
    if body.length() != 4 + width {
      fail("recovery slice size mismatch")
    }
    parity[exp] = as_words(body[4:].to_owned())
  }
  { width, members, parity, notices, producers, }
}

///|
test "read repeated metadata and reject unrelated sets" {
  let a = create([("a", b"aaa")], width=4)
  let b = create([("b", b"bbb")], width=4)
  assert_eq(read_set([a, a]).names(), ["a"])
  assert_true(
    try {
      ignore(read_set([a, b]))
      false
    } catch {
      _ => true
    },
  )
}
