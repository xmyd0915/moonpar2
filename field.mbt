///|
/// Multiply two 16-bit words in the field specified by PAR2.
fn multiply(left : Int32, right : Int32) -> Int32 {
  if left == 0 || right == 0 {
    return 0
  }
  let e = field_logs[left] + field_logs[right]
  field_powers[if e >= 65535 { e - 65535 } else { e }]
}

///|
let field_powers : FixedArray[Int32] = {
  let values = FixedArray::make(65535, 0)
  let mut x = 1
  for i = 0; i < 65535; i = i + 1 {
    values[i] = x
    x = x << 1
    if x >= 65536 {
      x = x ^ 0x1100b
    }
  }
  values
}

///|
let field_logs : FixedArray[Int32] = {
  let values = FixedArray::make(65536, 0)
  for i = 0; i < 65535; i = i + 1 {
    values[field_powers[i]] = i
  }
  values
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
