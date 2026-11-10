///|
/// Rebuild a complete set in memory. No output is returned until every
/// reconstructed file has passed its packet's whole-file checksum.
pub fn RecoverySet::repair(
  self : RecoverySet,
  files : Map[String, Bytes],
) -> Array[(String, Bytes)] raise {
  let mut total = 0UL
  for entry in self.members {
    total = total + entry.length
  }
  if total > MaxSourceBytes.to_uint64() {
    fail("use streaming repair for sets over 256 MiB")
  }
  let scan = self.scan(files)
  let exps = self.parity.keys().to_array()
  exps.sort()
  let missing = []
  for i = 0; i < scan.blocks.length(); i = i + 1 {
    if scan.blocks[i] is None {
      missing.push(i)
    }
  }
  guard solve(
      scan.blocks.length(),
      missing,
      exps,
      exps.map(fn(e) { as_words(self.parity[e]) }),
      fn(row, offset, j, weight) {
        if scan.blocks[j] is Some(view) {
          xor_slice(row, offset, view, weight)
        }
      },
    )
    is Some(restored) else {
    fail("insufficient independent recovery slices")
  }
  let outputs = []
  let mut pos = 0
  let mut recovered = 0
  for entry in self.members {
    if !entry.recoverable {
      continue
    }
    let file_blocks : Array[BytesView] = []
    let count = (entry.length.to_int() + self.width - 1) / self.width
    for i = 0; i < count; i = i + 1 {
      let block = match scan.blocks[pos] {
        Some(known) => known
        None => {
          let value = restored[recovered]
          recovered = recovered + 1
          as_bytes(value)[:]
        }
      }
      pos = pos + 1
      file_blocks.push(block)
    }
    // Allocate the result once instead of copying an entire file-sized Buffer.
    let bytes = Bytes::makei(entry.length.to_int(), fn(i) {
      file_blocks[i / self.width][i % self.width]
    })
    if md5(bytes) != entry.hash {
      fail("restored checksum mismatch: " + entry.name)
    }
    outputs.push((entry.name, bytes))
  }
  outputs
}

///|
test "recover missing file and the final partial slice of another" {
  let files = [("one", b"abcdefghij"), ("two", b"xyz")]
  let s = read_set([create(files, width=4, recovery_blocks=2)])
  let outputs = Map(s.repair(Map([("one", b"abcdefghXX")])))
  for pair in files {
    assert_eq(outputs.get(pair.0), Some(pair.1))
  }
  let few = read_set([create(files, width=4, recovery_blocks=1)])
  assert_true(
    try {
      ignore(few.repair(Map([("one", b"abcdefghXX")])))
      false
    } catch {
      _ => true
    },
  )
}
