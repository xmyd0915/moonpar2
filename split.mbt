///|
/// Return an index followed by independently readable recovery volumes.
/// Each recovery volume contains two copies of the non-recovery packets.
/// Packet contents and recovery exponents are preserved; only grouping changes.
pub fn split_volume(
  volume : Bytes,
  recovery_blocks_per_volume~ : Int32 = 1,
) -> Array[Bytes] raise {
  if recovery_blocks_per_volume < 1 || recovery_blocks_per_volume > MaxParity {
    fail("expected 1 to 32 recovery slices per volume")
  }
  if volume.length() > MaxVolumeBytes {
    fail("recovery volumes exceed 64 MiB")
  }
  let packets = read_packets(volume)
  if packets.is_empty() {
    fail("missing packets to split")
  }
  let id = packets[0].id
  for packet in packets {
    if packet.id != id {
      fail("different recovery sets")
    }
  }
  // Validate completeness and conflicting duplicates before repartitioning.
  ignore(read_set([volume]))
  let metadata = @buffer.Buffer()
  let seen : Map[Bytes, Bool] = Map([])
  let recovery : Map[Int32, Bytes] = Map([])
  let mut recovery_size = 0
  for packet in packets {
    let encoded = write_packet(packet.id, packet.tag, packet.body)
    if packet.tag == parity_tag {
      let exp = le32(packet.body, 0).reinterpret_as_int()
      if !recovery.contains(exp) {
        recovery[exp] = encoded
        recovery_size = recovery_size + encoded.length()
      }
    } else if !seen.contains(encoded) {
      seen[encoded] = true
      metadata.write_bytes(encoded)
    }
  }
  let exponents = recovery.keys().to_array()
  exponents.sort()
  let groups = (exponents.length() + recovery_blocks_per_volume - 1) /
    recovery_blocks_per_volume
  let meta = metadata.to_bytes()
  // Account for repeated metadata before allocating any output volumes.
  let total = meta.length().to_uint64() * (1 + 2 * groups).to_uint64() +
    recovery_size.to_uint64()
  if total > MaxVolumeBytes.to_uint64() {
    fail("split volumes exceed 64 MiB; use more recovery slices per volume")
  }
  let output = [meta]
  let mut at = 0
  while at < exponents.length() {
    let parts = [meta]
    let end = if exponents.length() < at + recovery_blocks_per_volume {
      exponents.length()
    } else {
      at + recovery_blocks_per_volume
    }
    while at < end {
      parts.push(recovery[exponents[at]])
      at = at + 1
    }
    parts.push(meta)
    output.push(joined(parts))
  }
  output
}
