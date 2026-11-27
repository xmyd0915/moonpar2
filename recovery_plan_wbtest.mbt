///|
test "repair plan separates protected health and check-only damage" {
  let set = read_set([
    create([("数据", b"abcdefgh")], width=4, non_recovery_files=[
      ("清单", b"check"),
    ]),
  ])
  let plan = set.plan_repair(set.verify(Map([("数据", b"abcdefgh")])))
  assert_true(plan.state == Healthy)
  assert_eq(plan.damaged_files, 0)
  assert_eq(plan.check_only_damaged_files, 1)
  assert_eq(plan.missing_slices, 0)
  assert_eq(plan.independent_recovery_slices, 0)
  assert_eq(plan.additional_recovery_slices, 0)
}

///|
test "repair plan handles missing empty files, truncation and appended bytes" {
  let empty = read_set([create([("empty", b"")])])
  let plan = empty.plan_repair(empty.verify(Map([])))
  assert_true(plan.state == Repairable)
  assert_eq(plan.damaged_files, 1)
  assert_eq(plan.missing_slices, 0)
  let set = read_set([
    create([("a", b"abcdefghij")], width=4, recovery_blocks=1),
  ])
  let truncated = set.plan_repair(set.verify(Map([("a", b"abcdefgh")])))
  assert_true(truncated.state == Repairable)
  assert_eq(truncated.missing_slices, 1)
  assert_eq(truncated.independent_recovery_slices, 1)
  let appended = set.plan_repair(set.verify(Map([("a", b"abcdefghij-extra")])))
  assert_true(appended.state == Repairable)
  assert_eq(appended.missing_slices, 0)
  let missing = set.plan_repair(set.verify(Map([])))
  assert_true(missing.state == Insufficient)
  assert_eq(missing.missing_slices, 3)
  assert_eq(missing.independent_recovery_slices, 1)
  assert_eq(missing.additional_recovery_slices, 2)
}

///|
test "repair plan measures rank instead of counting recovery packets" {
  let original = create([("a", b"abcdefgh")], width=4, recovery_blocks=2)
  let packets = read_packets(original)
  let zero = packets.filter(fn(p) { p.tag == parity_tag })[0]
  // Exponents 0 and 65535 are different but produce identical coefficients.
  let dependent = packets.map(fn(p) {
    if p.tag == parity_tag && le32(p.body, 0) == 1U {
      write_packet(
        p.id,
        p.tag,
        joined([b"\xff\xff\x00\x00", zero.body[4:].to_owned()]),
      )
    } else {
      write_packet(p.id, p.tag, p.body)
    }
  })
  let singular = read_set(dependent)
  let plan = singular.plan_repair(singular.verify(Map([])))
  assert_true(plan.state == Insufficient)
  assert_eq(plan.available_recovery_slices, 2)
  assert_eq(plan.independent_recovery_slices, 1)
  assert_eq(plan.additional_recovery_slices, 1)
  let normal = read_set([original])
  let complete = normal.plan_repair(normal.verify(Map([])))
  assert_true(complete.state == Repairable)
  assert_eq(complete.independent_recovery_slices, 2)
}

///|
test "repair plan uses missing positions and agrees with actual decoding" {
  let bytes = b"abcdefghijkl"
  let source = create([("a", bytes)], width=4, recovery_blocks=2)
  let encoded = encode(
    [as_words(b"abcd"), as_words(b"efgh"), as_words(b"ijkl")],
    21845,
  ).unwrap()
  let packets = read_packets(source).map(fn(p) {
    if p.tag == parity_tag && le32(p.body, 0) == 1U {
      write_packet(
        p.id,
        p.tag,
        joined([b"\x55\x55\x00\x00", as_bytes(encoded)]),
      )
    } else {
      write_packet(p.id, p.tag, p.body)
    }
  })
  let set = read_set(packets)
  // Source constants 2^1 and 2^4 coincide when raised to exponent 21845.
  let singular_input = Map([("a", b"XXXXefghXXXX")])
  let singular = set.plan_repair(set.verify(singular_input))
  assert_eq(singular.missing_slices, 2)
  assert_eq(singular.independent_recovery_slices, 1)
  assert_true(singular.state == Insufficient)
  assert_true(
    try {
      ignore(set.repair(singular_input))
      false
    } catch {
      _ => true
    },
  )
  // Changing the missing positions changes rank despite identical packet counts.
  let repairable_input = Map([("a", b"XXXXXXXXijkl")])
  let repairable = set.plan_repair(set.verify(repairable_input))
  assert_eq(repairable.missing_slices, 2)
  assert_eq(repairable.independent_recovery_slices, 2)
  assert_true(repairable.state == Repairable)
  assert_eq(set.repair(repairable_input), [("a", bytes)])
}

///|
test "repair plan agrees for streamed statuses and reordered files" {
  let input = Map([("a", b"abcd"), ("b", b"efghij")])
  let set = read_set([create([("a", b"abcd"), ("b", b"efghij")], width=4)])
  let status = set.verify_stream(
    name => if name == "b" { None } else { Some(4UL) },
    (name, at, n) => input[name][at.to_int():at.to_int() + n].to_owned(),
  )
  let plan = set.plan_repair(status.rev())
  assert_true(plan.state == Repairable)
  assert_eq(plan.missing_slices, 2)
  assert_eq(plan.independent_recovery_slices, 2)
  assert_eq(plan.damaged_files, 1)
}

///|
test "repair plan rejects mismatched and inconsistent statuses" {
  let set = read_set([create([("a", b"abcdefgh")], width=4)])
  assert_true(
    try {
      ignore(set.plan_repair([]))
      false
    } catch {
      _ => true
    },
  )
  for
    item in [
      {
        name: "other",
        healthy: false,
        missing: true,
        damaged_slices: [0, 1],
        recoverable: true,
      },
      {
        name: "a",
        healthy: false,
        missing: true,
        damaged_slices: [0, 1],
        recoverable: false,
      },
      {
        name: "a",
        healthy: true,
        missing: true,
        damaged_slices: [],
        recoverable: true,
      },
      {
        name: "a",
        healthy: true,
        missing: false,
        damaged_slices: [0],
        recoverable: true,
      },
      {
        name: "a",
        healthy: false,
        missing: false,
        damaged_slices: [-1],
        recoverable: true,
      },
      {
        name: "a",
        healthy: false,
        missing: false,
        damaged_slices: [2],
        recoverable: true,
      },
      {
        name: "a",
        healthy: false,
        missing: false,
        damaged_slices: [0, 0],
        recoverable: true,
      },
      {
        name: "a",
        healthy: false,
        missing: true,
        damaged_slices: [0],
        recoverable: true,
      },
    ] {
    assert_true(
      try {
        ignore(set.plan_repair([item]))
        false
      } catch {
        _ => true
      },
    )
  }
  let pair = read_set([create([("a", b"abcd"), ("b", b"efgh")], width=4)])
  let status = pair.verify(Map([]))
  assert_true(
    try {
      ignore(pair.plan_repair([status[0], status[0]]))
      false
    } catch {
      _ => true
    },
  )
  let checks = read_set([create([], non_recovery_files=[("check", b"x")])])
  assert_true(
    try {
      ignore(
        checks.plan_repair([
          {
            name: "check",
            healthy: false,
            missing: false,
            damaged_slices: [0],
            recoverable: false,
          },
        ]),
      )
      false
    } catch {
      _ => true
    },
  )
}

///|
test "repair plan keeps rank work bounded for the maximum missing slice count" {
  let set = read_set([
    create([("a", Bytes::make(32768 * 4, b'x'))], width=4, recovery_blocks=32),
  ])
  let plan = set.plan_repair(set.verify(Map([])))
  assert_true(plan.state == Insufficient)
  assert_eq(plan.missing_slices, 32768)
  assert_eq(plan.independent_recovery_slices, 32)
  assert_eq(plan.additional_recovery_slices, 32736)
}
