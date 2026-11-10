///|
/// Adapt callbacks to a random-access store; this small fixture stays in memory.
fn demo() -> Unit raise {
  let name = "照片/旅行/🌙.txt"
  let original = b"wind and tide"
  let volume = @par.create_stream(
    [{ name, size: original.length().to_uint64(), recoverable: true, }],
    (_, offset, length) => {
      original[offset.to_int():offset.to_int() + length].to_owned()
    },
    width=4,
    recovery_blocks=4,
  )
  let set = @par.read_set([volume])
  let staging = @buffer.Buffer()
  // A missing source has no size. All four slices are rebuilt from the volume.
  set.repair_stream(_ => None, (_, _, _) => b"", (path, offset, bytes) => {
    assert_eq(path, name)
    assert_eq(offset, staging.length().to_uint64())
    staging.write_bytes(bytes)
  })
  // Publish only after repair_stream has returned successfully.
  let restored = staging.to_bytes()
  assert_eq(restored, original)
  let statuses = set.verify_stream(_ => Some(restored.length().to_uint64()), (
    _,
    offset,
    length,
  ) => restored[offset.to_int():offset.to_int() + length].to_owned())
  assert_true(statuses[0].healthy)
  println("Unicode file restored through streaming callbacks")
}

///|
fn main {
  demo() catch {
    e => abort(e.to_string())
  }
}
