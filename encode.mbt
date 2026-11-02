///|
pub fn encode(blocks : Array[Array[Int32]], exponent : Int32) -> Array[Int32]? {
  if blocks.is_empty() ||
    blocks.length() > 32768 ||
    exponent < 0 ||
    exponent > 65535 {
    return None
  }
  let result = Array::make(blocks[0].length(), 0)
  let bases = slice_bases(blocks.length())
  for i = 0; i < blocks.length(); i = i + 1 {
    if blocks[i].length() != result.length() {
      return None
    }
    let factor = power(bases[i], exponent)
    for j = 0; j < result.length(); j = j + 1 {
      let word = blocks[i][j]
      if word < 0 || word > 65535 {
        return None
      }
      result[j] = result[j] ^ multiply(word, factor)
    }
  }
  Some(result)
}

///|
test "recovery exponents weight source slices differently" {
  assert_eq(encode([[1, 2], [3, 4]], 0), Some([2, 6]))
  assert_eq(encode([[1, 2], [3, 4]], 1), Some([14, 20]))
  assert_eq(encode([[3], [4, 0]], 2), None)
}
