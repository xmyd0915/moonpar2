// Return recovered slices in input order, or None for an unsolvable system.

///|
pub fn recover(
  data : Array[Array[Int32]?],
  exponents : Array[Int32],
  parity : Array[Array[Int32]],
) -> Array[Array[Int32]]? {
  if parity.length() != exponents.length() || data.length() > 32768 {
    return None
  }
  for exp in exponents {
    if exp < 0 || exp > 65535 {
      return None
    }
  }
  for block in data {
    if block is Some(words) {
      for w in words {
        if w < 0 || w > 65535 {
          return None
        }
      }
    }
  }
  for words in parity {
    for w in words {
      if w < 0 || w > 65535 {
        return None
      }
    }
  }
  let missing = []
  for i = 0; i < data.length(); i = i + 1 {
    if data[i] is None {
      missing.push(i)
    }
  }
  let width = if parity.is_empty() { 0 } else { parity[0].length() }
  if !missing.is_empty() {
    for b in data {
      if b is Some(words) && words.length() != width {
        return None
      }
    }
  }
  solve(data.length(), missing, exponents, parity, fn(row, offset, j, weight) {
    if data[j] is Some(block) {
      for w = 0; w < width; w = w + 1 {
        row[offset + w] = row[offset + w] ^ multiply(weight, block[w])
      }
    }
  })
}

///|
fn solve(
  count : Int32,
  missing : Array[Int32],
  exponents : Array[Int32],
  parity : Array[Array[Int32]],
  subtract : (Array[Int32], Int32, Int32, Int32) -> Unit,
) -> Array[Array[Int32]]? {
  let n = missing.length()
  if n == 0 {
    return Some([])
  }
  if parity.length() < n {
    return None
  }
  let width = parity[0].length()
  let bases = slice_bases(count)
  let rows : Array[Array[Int32]] = []
  for i = 0; i < parity.length(); i = i + 1 {
    if parity[i].length() != width {
      return None
    }
    let weights = bases.map(fn(base) { power(base, exponents[i]) })
    let row = missing.map(fn(index) { weights[index] })
    for word in parity[i] {
      row.push(word)
    }
    for j = 0; j < count; j = j + 1 {
      subtract(row, n, j, weights[j])
    }
    rows.push(row)
  }
  for col = 0; col < n; col = col + 1 {
    let mut pivot = col
    while pivot < rows.length() && rows[pivot][col] == 0 {
      pivot = pivot + 1
    }
    if pivot == rows.length() {
      return None
    }
    let tmp = rows[col]
    rows[col] = rows[pivot]
    rows[pivot] = tmp
    let inverse = power(rows[col][col], 65534)
    for k = col; k < n + width; k = k + 1 {
      rows[col][k] = multiply(rows[col][k], inverse)
    }
    for j = 0; j < rows.length(); j = j + 1 {
      if j == col {
        continue
      }
      let factor = rows[j][col]
      if factor == 0 {
        continue
      }
      for k = col; k < n + width; k = k + 1 {
        rows[j][k] = rows[j][k] ^ multiply(factor, rows[col][k])
      }
    }
  }
  Some(Array::makei(n, fn(i) { Array::makei(width, fn(w) { rows[i][n + w] }) }))
}
