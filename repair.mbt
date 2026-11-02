///|
/// Rebuild a complete set in memory. No output is returned until every
/// reconstructed file has passed its packet's whole-file checksum.
pub fn RecoverySet::repair(
  self : RecoverySet,
  files : Map[String, Bytes],
) -> Array[(String, Bytes)] raise {
  let scan = self.scan(files)
  let exps = self.parity.keys().to_array()
  exps.sort()
  guard recover(scan.blocks, exps, exps.map(fn(e) { self.parity[e] }))
    is Some(restored) else {
    fail("insufficient independent recovery slices")
  }
  let outputs = []
  let mut pos = 0
  let mut recovered = 0
  for member in self.members {
    let buf = @buffer.Buffer()
    let count = (member.length + self.width - 1) / self.width
    for i = 0; i < count; i = i + 1 {
      let words = match scan.blocks[pos] {
        Some(known) => known
        None => {
          let value = restored[recovered]
          recovered = recovered + 1
          value
        }
      }
      pos = pos + 1
      let len = (member.length - i * self.width).min(self.width)
      buf.write_bytes(as_bytes(words)[:len])
    }
    let bytes = buf.to_bytes()
    if md5(bytes) != member.hash {
      fail("restored checksum mismatch: " + member.name)
    }
    outputs.push((member.name, bytes))
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
