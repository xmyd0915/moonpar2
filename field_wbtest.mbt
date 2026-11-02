///|
test "PAR2 slice constants and inverses" {
  assert_eq(slice_bases(10), [
    2, 4, 16, 128, 256, 2048, 8192, 16384, 4107, 32856,
  ])
  assert_eq(multiply(4107, power(4107, 65534)), 1)
}

///|
test "field tables agree with polynomial multiplication for every word" {
  for factor in [0, 1, 2, 0x8000, 0xffff] {
    for word = 0; word < 65536; word = word + 1 {
      let mut actual = 0
      let mut a = word
      let mut b = factor
      while b > 0 {
        if (b & 1) != 0 {
          actual = actual ^ a
        }
        a = if (a & 0x8000) != 0 { (a << 1) ^ 0x1100b } else { a << 1 }
        b = b >> 1
      }
      assert_eq(multiply(word, factor), actual)
    }
  }
}
