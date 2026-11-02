///|
/// Rebuild an object from an in-memory store without filesystem access.
fn main {
  let original = b"wind and tide"
  let volume = @par.create([("note.txt", original)], width=4, recovery_blocks=2) catch {
    e => abort(e.to_string())
  }
  let set = @par.read_set([volume]) catch { e => abort(e.to_string()) }
  let store = Map([("note.txt", b"wind and XXXX")])
  let restored = set.repair(store) catch { e => abort(e.to_string()) }
  guard restored == [("note.txt", original)] else { abort("content differs") }
  println("note.txt restored")
}
