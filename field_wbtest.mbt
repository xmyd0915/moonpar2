///|
test "PAR2 slice constants and inverses" {
  assert_eq(slice_bases(10), [
    2, 4, 16, 128, 256, 2048, 8192, 16384, 4107, 32856,
  ])
  assert_eq(multiply(4107, power(4107, 65534)), 1)
}
