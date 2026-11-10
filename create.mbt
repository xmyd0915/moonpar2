///|
pub const MaxSourceBytes = 268435456

///|
const MaxSlices = 32768

///|
const MaxFiles = 4096

///|
const MaxParity = 32

///|
const MaxWidth = 16777216

///|
pub const MaxStreamBytes : UInt64 = 549755813888UL

///|
pub const MaxVolumeBytes = 67108864

///|
pub fn create(
  files : Array[(String, Bytes)],
  width? : Int32,
  recovery_blocks~ : Int32 = 4,
  non_recovery_files~ : Array[(String, Bytes)] = [],
) -> Bytes raise {
  let inputs : Array[FileInfo] = []
  let data : Map[String, Bytes] = Map([])
  let mut total = 0
  for gi, group in [files, non_recovery_files] {
    for (name, bytes) in group {
      if bytes.length() > MaxSourceBytes - total {
        fail("use create_stream for sets over 256 MiB")
      }
      total = total + bytes.length()
      inputs.push({
        name,
        size: bytes.length().to_uint64(),
        recoverable: gi == 0,
      })
      data[name] = bytes
    }
  }
  create_stream(
    inputs,
    (name, at, n) => data[name][at.to_int():at.to_int() + n].to_owned(),
    width?,
    recovery_blocks~,
  )
}

///|
test "creation is independent of input order" {
  let one = ("a.txt", b"first")
  let two = ("b.txt", b"second")
  assert_eq(create([one, two], width=4), create([two, one], width=4))
  let packets = read_packets(create([one, two], width=4))
  assert_eq(packets.filter(fn(p) { p.tag == main_tag }).length(), 2)
}
