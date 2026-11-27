///|
/// Health refers to protected members; check-only damage is reported separately.
#derive(Eq)
pub(all) enum RepairState {
  Healthy
  Repairable
  Insufficient
}

///|
pub extend RepairState with Eq::{equal, not_equal}

///|
/// Equation availability for the currently observed missing slice positions.
pub(all) struct RepairPlan {
  state : RepairState
  damaged_files : Int32
  check_only_damaged_files : Int32
  missing_slices : Int32
  available_recovery_slices : Int32
  independent_recovery_slices : Int32
  additional_recovery_slices : Int32
}

///|
/// Compute rank from columns, retaining at most 32 vectors of at most 32 words.
fn recovery_rank(
  missing : Array[Int32],
  bases : Array[Int32],
  exponents : Array[Int32],
) -> Int32 {
  let size = exponents.length()
  if size == 0 {
    return 0
  }
  let pivots : Array[Array[Int32]?] = Array::make(size, None)
  let mut rank = 0
  for index in missing {
    let column = exponents.map(fn(e) { power(bases[index], e) })
    for row = 0; row < size; row = row + 1 {
      let value = column[row]
      if value == 0 {
        continue
      }
      if pivots[row] is Some(pivot) {
        for j = row; j < size; j = j + 1 {
          column[j] = column[j] ^ multiply(value, pivot[j])
        }
      } else {
        let inverse = power(value, 65534)
        for j = row; j < size; j = j + 1 {
          column[j] = multiply(column[j], inverse)
        }
        pivots[row] = Some(column)
        rank = rank + 1
        break
      }
    }
    if rank == size {
      break
    }
  }
  rank
}

///|
/// Assess recovery equations without reading source data or decoding payloads.
/// Pass current verify/verify_stream results from this same set. Status ordering
/// does not matter, but every member must occur once with valid slice indices.
/// This is a capacity assessment, not a guarantee against changed input, I/O
/// failure or inconsistent whole-file metadata discovered during final repair.
pub fn RecoverySet::plan_repair(
  self : RecoverySet,
  status : Array[FileStatus],
) -> RepairPlan raise {
  if status.length() != self.members.length() {
    fail("repair status does not cover this recovery set")
  }
  let statuses : Map[String, FileStatus] = Map([])
  for item in status {
    if statuses.contains(item.name) {
      fail("duplicate file in repair status")
    }
    if item.healthy && (item.missing || !item.damaged_slices.is_empty()) {
      fail("inconsistent healthy repair status")
    }
    statuses[item.name] = item
  }
  let missing = []
  let mut total = 0
  let mut damaged_files = 0
  let mut check_only_damaged_files = 0
  for entry in self.members {
    guard statuses.get(entry.name) is Some(item) else {
      fail("repair status names do not match this recovery set")
    }
    if item.recoverable != entry.recoverable {
      fail("repair status member role mismatch")
    }
    if !entry.recoverable {
      if !item.damaged_slices.is_empty() {
        fail("check-only repair status contains recovery slices")
      }
      if !item.healthy {
        check_only_damaged_files = check_only_damaged_files + 1
      }
      continue
    }
    if !item.healthy {
      damaged_files = damaged_files + 1
    }
    let count = ((entry.length + self.width.to_uint64() - 1UL) /
    self.width.to_uint64()).to_int()
    let seen : Map[Int32, Bool] = Map([])
    for index in item.damaged_slices {
      if index < 0 || index >= count || seen.contains(index) {
        fail("invalid or repeated damaged slice index")
      }
      seen[index] = true
      missing.push(total + index)
    }
    if item.missing && item.damaged_slices.length() != count {
      fail("missing file repair status omits source slices")
    }
    total = total + count
  }
  let exponents = self.parity.keys().to_array()
  exponents.sort()
  let rank = recovery_rank(missing, slice_bases(total), exponents)
  let state = if damaged_files == 0 {
    Healthy
  } else if rank == missing.length() {
    Repairable
  } else {
    Insufficient
  }
  {
    state,
    damaged_files,
    check_only_damaged_files,
    missing_slices: missing.length(),
    available_recovery_slices: exponents.length(),
    independent_recovery_slices: rank,
    additional_recovery_slices: missing.length() - rank,
  }
}
