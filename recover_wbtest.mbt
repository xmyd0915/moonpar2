///|
test "reconstruct with independent rows and reject insufficient rank" {
  let blocks = [[3, 9], [77, 65530], [1000, 6]]
  let a = encode(blocks, 3).unwrap()
  let b = encode(blocks, 4).unwrap()
  let lost = [None, Some(blocks[1]), None]
  assert_eq(recover(lost, [3, 4], [a, b]), Some([blocks[0], blocks[2]]))
  assert_eq(recover(lost, [3, 3], [a, a]), None)
  assert_eq(recover(lost, [3], [a]), None)
}
