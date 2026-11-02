///|
pub(all) struct FileStatus {
  name : String
  healthy : Bool
  missing : Bool
  damaged_slices : Array[Int32]
}

///|
priv struct Scan {
  status : Array[FileStatus]
  blocks : Array[Array[Int32]?]
}

///|
fn RecoverySet::scan(self : RecoverySet, files : Map[String, Bytes]) -> Scan {
  let blocks = []
  let status = []
  for m in self.members {
    let source = files.get(m.name)
    let bad = []
    let count = (m.length + self.width - 1) / self.width
    for i = 0; i < count; i = i + 1 {
      let start = i * self.width
      let end = (start + self.width).min(m.length)
      if source is Some(b) && end <= b.length() {
        let block = Bytes::makei(self.width, fn(j) {
          if start + j < end {
            b[start + j]
          } else {
            b'\x00'
          }
        })
        let offset = 16 + i * 20
        if crc32(block) == le32(m.sums, offset + 16) &&
          md5(block) == m.sums[offset:offset + 16].to_owned() {
          blocks.push(Some(as_words(block)))
          continue
        }
      }
      bad.push(i)
      blocks.push(None)
    }
    let healthy = source is Some(bytes) &&
      bytes.length() == m.length &&
      bad.is_empty() &&
      md5(bytes) == m.hash
    status.push({
      name: m.name,
      healthy,
      missing: source is None,
      damaged_slices: bad,
    })
  }
  { status, blocks, }
}

///|
pub fn RecoverySet::verify(
  self : RecoverySet,
  files : Map[String, Bytes],
) -> Array[FileStatus] {
  self.scan(files).status
}

///|
test "identify missing, truncated and appended input" {
  let s = read_set([create([("a", b"12345")], width=4)])
  assert_eq(s.verify(Map([]))[0].damaged_slices, [0, 1])
  assert_eq(s.verify(Map([("a", b"1234")]))[0].damaged_slices, [1])
  assert_false(s.verify(Map([("a", b"12345extra")]))[0].healthy)
  assert_true(s.verify(Map([("a", b"12345")]))[0].healthy)
}
