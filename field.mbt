///|
/// Multiply two 16-bit words in the field specified by PAR2.
fn multiply(left : Int32, right : Int32) -> Int32 {
  let mut a = left
  let mut b = right
  let mut result = 0
  while b != 0 {
    if (b & 1) != 0 {
      result = result ^ a
    }
    b = b >> 1
    a = a << 1
    if a >= 65536 {
      a = a ^ 0x1100b
    }
  }
  result
}

///|
fn power(value : Int32, exponent : Int32) -> Int32 {
  let mut base = value
  let mut n = exponent
  let mut result = 1
  while n > 0 {
    if (n & 1) != 0 {
      result = multiply(result, base)
    }
    base = multiply(base, base)
    n = n >> 1
  }
  result
}

///|
fn slice_bases(count : Int32) -> Array[Int32] {
  let bases = []
  for k = 1; bases.length() < count; k = k + 1 {
    if k % 3 != 0 && k % 5 != 0 && k % 17 != 0 && k % 257 != 0 {
      bases.push(power(2, k))
    }
  }
  bases
}
