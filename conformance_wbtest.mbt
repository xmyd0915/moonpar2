///|
test "nested, empty and check-only members keep their distinct roles" {
  let files = [("tree/a/data", b"hello"), ("tree/empty", b"")]
  let set = read_set([
    create(files, width=4, recovery_blocks=2, non_recovery_files=[
      ("catalog/readme", b"check me"),
    ]),
  ])
  let output = Map(set.repair(Map([])))
  for item in files {
    assert_eq(output.get(item.0), Some(item.1))
  }
  assert_eq(output.get("catalog/readme"), None)
  let states = set.verify(output)
  for status in states {
    if status.name == "catalog/readme" {
      assert_false(status.recoverable)
      assert_true(status.missing)
    } else {
      assert_true(status.healthy)
    }
  }
}

///|
test "empty and non-recovery-only sets need no data equations" {
  let empty = read_set([create([("empty", b"")])])
  assert_eq(empty.repair(Map([])), [("empty", b"")])
  let checks = read_set([create([], non_recovery_files=[("a", b"text")])])
  assert_true(checks.verify(Map([("a", b"text")]))[0].healthy)
  assert_eq(checks.repair(Map([])), [])
}

///|
test "damaged frame resynchronization survives inserted and trailing bytes" {
  let raw = create([("dir/a", b"hello")], width=4)
  let frames = read_packets(raw)
  let pieces = [b"junk!"]
  let mut lost = false
  for p in frames {
    let bytes = write_packet(p.id, p.tag, p.body)
    if p.tag == parity_tag && !lost {
      pieces.push(joined([bytes[:bytes.length() - 1].to_owned(), b"X"]))
      lost = true
    } else {
      pieces.push(bytes)
    }
    pieces.push(b"!") // Subsequent headers no longer have 4-byte alignment.
  }
  pieces.push(b"PAR2\x00PKT")
  let set = read_set([joined(pieces)])
  assert_eq(set.recovery_blocks(), 3)
  assert_false(set.warnings().is_empty())
  assert_eq(set.repair(Map([])), [("dir/a", b"hello")])
}

///|
test "unsafe paths and colliding filesystem layouts are rejected" {
  for
    name in [
      "../x", "/abs", "C:/x", "a//b", "a/../b", "a/./b", "a/NUL.txt", "a/NUL .txt",
      "a\\b", "a/b.", "a/b ", "a/",
    ] {
    assert_false(safe_path(name))
  }
  for name in ["a/b", "a/.config", "a/report (final).txt"] {
    assert_true(safe_path(name))
  }
  for names in [["a", "a/b"], ["a/b", "a"], ["A/b", "a/B"]] {
    assert_true(
      try {
        ignore(create(names.map(fn(n) { (n, b"x") })))
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "unknown packet and duplicate metadata do not alter recovery" {
  let raw = create([("a", b"data")], width=4)
  let unknown = write_packet(
    Bytes::make(16, b'x'),
    b"Other App\x00\x00\x00\x00\x00\x00\x00",
    b"abcd",
  )
  let set = read_set([unknown, raw, raw])
  assert_eq(set.recovery_blocks(), 4)
  assert_eq(set.repair(Map([])), [("a", b"data")])
}

///|
test "corrupt length cannot hide a later good packet" {
  let raw = create([("a", b"data")], width=4)
  let broken = Bytes::makei(64, fn(i) { if i < 8 { magic[i] } else { b'\xff' } })
  assert_eq(read_set([joined([broken, raw])]).repair(Map([])), [("a", b"data")])
}

///|
test "every truncation of a short packet stays within bounds" {
  let raw = write_packet(Bytes::make(16, b'0'), main_tag, b"data")
  for n = 0; n < raw.length(); n = n + 1 {
    assert_eq(scan_packets(raw[:n].to_owned()).packets.length(), 0)
  }
}

///|
test "all 32768 standard source constants remain distinct" {
  let seen : Map[Int32, Bool] = Map([])
  for base in slice_bases(32768) {
    assert_false(seen.contains(base))
    seen[base] = true
  }
}

///|
test "valid checksums cannot conceal conflicting recovery contents" {
  let raw = create([("a", b"data")], width=4)
  let p = read_packets(raw).filter(fn(p) { p.tag == parity_tag })[0]
  let changed = Bytes::makei(p.body.length(), fn(i) {
    if i == 4 {
      (p.body[i].to_int() ^ 1).to_byte()
    } else {
      p.body[i]
    }
  })
  assert_true(
    try {
      ignore(read_set([raw, write_packet(p.id, p.tag, changed)]))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "lost critical metadata and oversized length fail without panicking" {
  let frames = read_packets(create([("a", b"data")], width=4))
  let missing = frames
    .filter(fn(p) { p.tag != desc_tag })
    .map(fn(p) { write_packet(p.id, p.tag, p.body) })
  assert_true(
    try {
      ignore(read_set(missing))
      false
    } catch {
      _ => true
    },
  )
  let huge = frames.map(fn(p) {
    if p.tag == desc_tag {
      let body = Bytes::makei(p.body.length(), fn(i) {
        if i == 52 {
          b'\x01'
        } else {
          p.body[i]
        }
      })
      write_packet(p.id, p.tag, body)
    } else {
      write_packet(p.id, p.tag, p.body)
    }
  })
  assert_true(
    try {
      ignore(read_set(huge))
      false
    } catch {
      _ => true
    },
  )
}
