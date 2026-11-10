///|
pub(all) struct FileInfo {
  name : String
  size : UInt64
  recoverable : Bool
}

///|
pub fn RecoverySet::files(self : RecoverySet) -> Array[FileInfo] {
  self.members.map(fn(m) {
    { name: m.name, size: m.length, recoverable: m.recoverable, }
  })
}

///|
fn read_exact(
  reader : (String, UInt64, Int32) -> Bytes raise,
  name : String,
  at : UInt64,
  length : Int32,
) -> Bytes raise {
  let b = reader(name, at, length)
  if b.length() != length {
    fail("short or changed source: " + name)
  }
  b
}

///|
fn describe_stream(
  file : FileInfo,
  width : Int32,
  reader : (String, UInt64, Int32) -> Bytes raise,
) -> Member raise {
  let digest = Digest::new()
  let prefix = @buffer.Buffer()
  let sums = @buffer.Buffer()
  let mut pos = 0UL
  while pos < file.size {
    let n = minimum(width.to_uint64(), file.size - pos).to_int()
    let b = read_exact(reader, file.name, pos, n)
    digest.update(b)
    if pos < 16384UL {
      prefix.write_bytes(b[:minimum(n.to_uint64(), 16384UL - pos).to_int()])
    }
    if file.recoverable {
      let block = slice_at(b, 0, width)
      sums.write_bytes(md5(block))
      sums.write_uint_le(crc32(block))
    }
    pos = pos + n.to_uint64()
  }
  let description = @buffer.Buffer()
  description.write_bytes(md5(prefix.to_bytes()))
  description.write_uint64_le(file.size)
  let encoded = @utf8.encode(file.name)
  description.write_bytes(encoded)
  let id = md5(description.to_bytes())
  for i = 0; i < (4 - encoded.length() % 4) % 4; i = i + 1 {
    description.write_byte(b'\x00')
  }
  let hash = digest.finish()
  {
    id,
    name: file.name,
    length: file.size,
    hash,
    desc: joined([id, hash, description.to_bytes()]),
    sums: joined([id, sums.to_bytes()]),
    recoverable: file.recoverable,
  }
}

///|
/// Two passes over caller-supplied random access input; source contents are never retained.
pub fn create_stream(
  files : Array[FileInfo],
  reader : (String, UInt64, Int32) -> Bytes raise,
  width? : Int32,
  recovery_blocks~ : Int32 = 4,
) -> Bytes raise {
  if files.is_empty() || files.length() > MaxFiles {
    fail("expected 1 to 4096 files")
  }
  if recovery_blocks < 1 || recovery_blocks > MaxParity {
    fail("expected 1 to 32 recovery slices")
  }
  let paths : Map[String, Bool] = Map([])
  let mut total = 0UL
  for file in files {
    claim_path(paths, file.name)
    if file.size > MaxStreamBytes - total {
      fail("source sizes exceed streaming address range")
    }
    total = total + file.size
  }
  let width = width.unwrap_or_else(fn() {
    let mut w = 4096
    while w < MaxWidth && w.to_uint64() * 1024UL < total {
      w = w * 2
    }
    w
  })
  if width <= 0 || width > MaxWidth || width % 4 != 0 {
    fail("invalid slice size")
  }
  if width > 33554432 / recovery_blocks {
    fail(
      "recovery working set exceeds 32 MiB; use fewer recovery blocks or a smaller slice size",
    )
  }
  let mut count = 0
  for file in files {
    if file.recoverable {
      let n = (file.size + width.to_uint64() - 1UL) / width.to_uint64()
      if n > (MaxSlices - count).to_uint64() {
        fail("too many source slices; increase slice size")
      }
      count = count + n.to_int()
    }
  }
  let members = files.map(f => describe_stream(f, width, reader))
  members.sort_by(fn(a, b) {
    if a.recoverable != b.recoverable {
      return if a.recoverable { -1 } else { 1 }
    }
    for i = 15; i >= 0; i = i - 1 {
      let d = a.id[i].to_int() - b.id[i].to_int()
      if d != 0 {
        return d
      }
    }
    0
  })
  let main = @buffer.Buffer()
  main.write_uint64_le(width.to_uint64())
  main.write_int_le(files.filter(fn(f) { f.recoverable }).length())
  for m in members {
    main.write_bytes(m.id)
  }
  let set_id = md5(main.to_bytes())
  let meta = @buffer.Buffer()
  meta.write_bytes(write_packet(set_id, main_tag, main.to_bytes()))
  for m in members {
    meta.write_bytes(write_packet(set_id, desc_tag, m.desc))
    if m.recoverable {
      meta.write_bytes(write_packet(set_id, sums_tag, m.sums))
    }
    if @utf8.encode(m.name).length() != m.name.length() {
      meta.write_bytes(write_packet(set_id, unicode_tag, unicode_body(m)))
    }
  }
  let rows = Array::makei(recovery_blocks, fn(_) { Array::make(width / 2, 0) })
  let bases = slice_bases(count)
  let mut index = 0
  for m in members {
    if !m.recoverable {
      continue
    }
    let mut at = 0UL
    let mut bi = 0
    while at < m.length {
      let b = read_exact(
        reader,
        m.name,
        at,
        minimum(width.to_uint64(), m.length - at).to_int(),
      )
      let block = slice_at(b, 0, width)
      if md5(block) != m.sums[16 + bi * 20:32 + bi * 20].to_owned() {
        fail("source changed during creation: " + m.name)
      }
      for e = 0; e < recovery_blocks; e = e + 1 {
        xor_slice(rows[e], 0, block, power(bases[index], e))
      }
      at = at + b.length().to_uint64()
      bi = bi + 1
      index = index + 1
    }
  }
  let out = @buffer.Buffer()
  let creator = @utf8.encode(
    "MoonPar2 0.4.0 https://github.com/xmyd0915/moonpar2",
  )
  out.write_bytes(
    write_packet(
      set_id,
      creator_tag,
      joined([creator, Bytes::make((4 - creator.length() % 4) % 4, b'\x00')]),
    ),
  )
  let metadata = meta.to_bytes()
  out.write_bytes(metadata)
  for e = 0; e < recovery_blocks; e = e + 1 {
    let b = @buffer.Buffer()
    b.write_int_le(e)
    b.write_bytes(as_bytes(rows[e]))
    out.write_bytes(write_packet(set_id, parity_tag, b.to_bytes()))
  }
  out.write_bytes(metadata)
  let result = out.to_bytes()
  if result.length() > MaxVolumeBytes {
    fail("recovery volume exceeds 64 MiB")
  }
  result
}

///|
priv struct StreamScan {
  status : Array[FileStatus]
  good : Array[Bool]
}

///|
fn RecoverySet::scan_stream(
  self : RecoverySet,
  size : (String) -> UInt64? raise,
  reader : (String, UInt64, Int32) -> Bytes raise,
) -> StreamScan raise {
  let status = []
  let good = []
  for m in self.members {
    let actual = size(m.name)
    let bad = []
    let digest = Digest::new()
    let mut at = 0UL
    let mut bi = 0
    while at < m.length {
      let n = minimum(self.width.to_uint64(), m.length - at).to_int()
      let present = actual is Some(nbytes) && nbytes >= at + n.to_uint64()
      let valid = if present {
        let bytes = read_exact(reader, m.name, at, n)
        digest.update(bytes)
        if m.recoverable {
          let block = slice_at(bytes, 0, self.width)
          crc32(block) == le32(m.sums, 32 + bi * 20) &&
          md5(block) == m.sums[16 + bi * 20:32 + bi * 20].to_owned()
        } else {
          true
        }
      } else {
        false
      }
      if m.recoverable {
        good.push(valid)
        if !valid {
          bad.push(bi)
        }
      }
      at = at + n.to_uint64()
      bi = bi + 1
    }
    let healthy = actual == Some(m.length) &&
      bad.is_empty() &&
      digest.finish() == m.hash
    status.push({
      name: m.name,
      healthy,
      missing: actual is None,
      damaged_slices: bad,
      recoverable: m.recoverable,
    })
  }
  { status, good, }
}

///|
pub fn RecoverySet::verify_stream(
  self : RecoverySet,
  size : (String) -> UInt64? raise,
  reader : (String, UInt64, Int32) -> Bytes raise,
) -> Array[FileStatus] raise {
  self.scan_stream(size, reader).status
}

///|
/// Writes to a caller-provided staging sink. Publish the sink only on success.
pub fn RecoverySet::repair_stream(
  self : RecoverySet,
  size : (String) -> UInt64? raise,
  reader : (String, UInt64, Int32) -> Bytes raise,
  writer : (String, UInt64, Bytes) -> Unit raise,
) -> Unit raise {
  let scan = self.scan_stream(size, reader)
  let missing = []
  for i = 0; i < scan.good.length(); i = i + 1 {
    if !scan.good[i] {
      missing.push(i)
    }
  }
  let exponents = self.parity.keys().to_array()
  exponents.sort()
  if missing.length() > exponents.length() {
    fail("insufficient independent recovery slices")
  }
  let residual = if missing.is_empty() {
    []
  } else {
    exponents.map(fn(e) { as_words(self.parity[e]) })
  }
  let bases = slice_bases(scan.good.length())
  let mut index = 0
  if !missing.is_empty() {
    for m in self.members {
      if !m.recoverable {
        continue
      }
      let mut at = 0UL
      let mut bi = 0
      while at < m.length {
        let n = minimum(self.width.to_uint64(), m.length - at).to_int()
        if scan.good[index] {
          let data = read_exact(reader, m.name, at, n)
          let block = slice_at(data, 0, self.width)
          if md5(block) != m.sums[16 + bi * 20:32 + bi * 20].to_owned() {
            fail("source changed during repair")
          }
          for ri = 0; ri < exponents.length(); ri = ri + 1 {
            xor_slice(
              residual[ri],
              0,
              block,
              power(bases[index], exponents[ri]),
            )
          }
        }
        index = index + 1
        bi = bi + 1
        at = at + n.to_uint64()
      }
    }
  }
  guard decode_residual(missing, bases, exponents, residual) is Some(rebuilt) else {
    fail("insufficient independent recovery slices")
  }
  let reconstructed : Map[Int32, Bytes] = Map([])
  for i = 0; i < missing.length(); i = i + 1 {
    reconstructed[missing[i]] = as_bytes(rebuilt[i])
  }
  index = 0
  for m in self.members {
    if !m.recoverable {
      continue
    }
    let digest = Digest::new()
    let mut at = 0UL
    if m.length == 0UL {
      writer(m.name, 0UL, b"")
    }
    while at < m.length {
      let n = minimum(self.width.to_uint64(), m.length - at).to_int()
      let b = if reconstructed.get(index) is Some(r) {
        r[:n].to_owned()
      } else {
        read_exact(reader, m.name, at, n)
      }
      digest.update(b)
      writer(m.name, at, b)
      at = at + n.to_uint64()
      index = index + 1
    }
    if digest.finish() != m.hash {
      fail("restored checksum mismatch: " + m.name)
    }
  }
}
