///|
test "split volumes retain exact packets and sort recovery groups" {
  let source = create([("data", b"abcdefghij")], width=4, recovery_blocks=5)
  let packets = read_packets(source)
  let shuffled = joined(
    packets.rev().map(fn(p) { write_packet(p.id, p.tag, p.body) }),
  )
  let split = split_volume(shuffled, recovery_blocks_per_volume=2)
  assert_eq(split.length(), 4)
  assert_eq(read_set([split[0]]).recovery_blocks(), 0)
  for i = 1; i < split.length(); i = i + 1 {
    let pieces = read_packets(split[i])
    let exps = pieces
      .filter(fn(p) { p.tag == parity_tag })
      .map(fn(p) { le32(p.body, 0).reinterpret_as_int() })
    assert_eq(exps, if i == 3 { [4] } else { [(i - 1) * 2, (i - 1) * 2 + 1] })
    for p in pieces {
      assert_true(
        packets.any(fn(old) {
          old.id == p.id && old.tag == p.tag && old.body == p.body
        }),
      )
    }
  }
  assert_eq(read_set(split).repair(Map([])), [("data", b"abcdefghij")])
}

///|
test "recovery volumes survive loss of index and a damaged metadata copy" {
  let source = create([("data", b"abcdefgh")], width=4, recovery_blocks=2)
  let volumes = split_volume(source)
  let without_index = []
  for i = 1; i < volumes.length(); i = i + 1 {
    let mut damaged = false
    let pieces = read_packets(volumes[i]).map(fn(p) {
      let raw = write_packet(p.id, p.tag, p.body)
      if p.tag == main_tag && !damaged {
        damaged = true
        Bytes::makei(raw.length(), fn(j) {
          if j == raw.length() - 1 {
            (raw[j].to_int() ^ 1).to_byte()
          } else {
            raw[j]
          }
        })
      } else {
        raw
      }
    })
    without_index.push(joined(pieces))
  }
  let set = read_set(without_index)
  assert_eq(set.warnings().length(), 2)
  assert_eq(set.repair(Map([])), [("data", b"abcdefgh")])
}

///|
test "split preserves Unicode, check-only roles and unique index metadata" {
  let source = create([("目录/🌙", b"moon")], width=4, recovery_blocks=2, non_recovery_files=[
    ("目录/清单", b"check"),
  ])
  let volumes = split_volume(source)
  let index = read_packets(volumes[0])
  assert_eq(index.filter(fn(p) { p.tag == main_tag }).length(), 1)
  assert_eq(index.filter(fn(p) { p.tag == unicode_tag }).length(), 2)
  assert_eq(index.filter(fn(p) { p.tag == creator_tag }).length(), 1)
  let set = read_set([volumes[1]])
  assert_eq(set.repair(Map([])), [("目录/🌙", b"moon")])
  assert_true(
    set.files().any(fn(f) { f.name == "目录/清单" && !f.recoverable }),
  )
  // An already metadata-only index remains a single index.
  assert_eq(split_volume(volumes[0]), [volumes[0]])
}

///|
test "split refuses damaged, incomplete, mixed and invalid groups" {
  let first = create([("a", b"abcd")], width=4)
  let second = create([("b", b"efgh")], width=4)
  let missing = joined(
    read_packets(first)
    .filter(fn(p) { p.tag != main_tag })
    .map(fn(p) { write_packet(p.id, p.tag, p.body) }),
  )
  for
    source in [
      b"",
      first[:first.length() - 1].to_owned(),
      joined([first, second]),
      missing,
    ] {
    assert_true(
      try {
        ignore(split_volume(source))
        false
      } catch {
        _ => true
      },
    )
  }
  for count in [0, -1, 33] {
    assert_true(
      try {
        ignore(split_volume(first, recovery_blocks_per_volume=count))
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "split preserves unknown metadata and deduplicates recovery packets" {
  let source = create([("a", b"abcd")], width=4, recovery_blocks=2)
  let packet = read_packets(source).filter(fn(p) { p.tag == parity_tag })[0]
  let unknown = write_packet(packet.id, b"Example\x00Metadata", b"note")
  let input = joined([
    source,
    unknown,
    write_packet(packet.id, packet.tag, packet.body),
  ])
  let volumes = split_volume(input)
  assert_eq(volumes.length(), 3)
  assert_eq(read_set(volumes).recovery_blocks(), 2)
  for volume in volumes {
    assert_true(
      read_packets(volume).any(fn(p) {
        p.tag == b"Example\x00Metadata" && p.body == b"note"
      }),
    )
  }
  let foreign = write_packet(Bytes::make(16, b'x'), creator_tag, b"name")
  assert_true(
    try {
      ignore(split_volume(joined([source, foreign])))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "split metadata duplication stays within the aggregate read budget" {
  let source = create([("a", b"abcd")], width=4, recovery_blocks=4)
  let id = read_packets(source)[0].id
  let extra = write_packet(
    id,
    b"Example\x00Metadata",
    Bytes::make(8 * 1024 * 1024, b'x'),
  )
  let input = joined([source, extra])
  // Four volumes require nine metadata copies, exceeding the 64 MiB aggregate.
  assert_true(
    try {
      ignore(split_volume(input))
      false
    } catch {
      _ => true
    },
  )
  // A larger recovery group needs only three metadata copies and remains usable.
  let volumes = split_volume(input, recovery_blocks_per_volume=4)
  assert_eq(volumes.length(), 2)
  assert_eq(read_set(volumes).repair(Map([])), [("a", b"abcd")])
}
