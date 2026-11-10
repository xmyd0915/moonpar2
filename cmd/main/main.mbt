///|
let usage = "moonpar2 create [--base-dir ROOT] [--recovery-blocks N] [--slice-size BYTES] [--volume-blocks N] [--check-only FILE] SET.par2 FILE_OR_DIR...\nmoonpar2 inspect [--no-discovery] INDEX.par2 [VOLUME.par2 ...]\nmoonpar2 verify [--base-dir ROOT] [--no-discovery] INDEX.par2 [VOLUME.par2 ...]\nmoonpar2 repair [--base-dir ROOT] [--no-discovery] NEW_DIRECTORY INDEX.par2 [VOLUME.par2 ...]"

///|
fn number(text : String) -> Int32 raise {
  if text.is_empty() || text.length() > 10 {
    fail("invalid numeric option")
  }
  let mut n = 0
  for c in text {
    if c < '0' || c > '9' {
      fail("expected a decimal number")
    }
    let digit = c.to_int() - 48
    if n > (2147483647 - digit) / 10 {
      fail("numeric option exceeds integer range")
    }
    n = n * 10 + digit
  }
  n
}

///|
fn run(args : Array[String]) -> Int32 raise {
  if args == ["--help"] || args == ["-h"] {
    println(usage)
    return 0
  }
  if args == ["--version"] {
    println("MoonPar2 0.4.0")
    return 0
  }
  guard args.length() >= 2 else { fail(usage) }
  let op = args[0]
  let mut base_opt : String? = None
  let mut parity = 4
  let mut width : Int32? = None
  let mut per_volume : Int32? = None
  let mut discovery = true
  let checks : Array[String] = []
  let mut at = 1
  while at < args.length() && args[at].has_prefix("--") {
    if args[at] == "--no-discovery" && op != "create" {
      discovery = false
      at = at + 1
      continue
    }
    guard at + 1 < args.length() else { fail(usage) }
    match args[at] {
      "--base-dir" => base_opt = Some(args[at + 1])
      "--recovery-blocks" if op == "create" => parity = number(args[at + 1])
      "--slice-size" if op == "create" => width = Some(number(args[at + 1]))
      "--volume-blocks" if op == "create" =>
        per_volume = Some(number(args[at + 1]))
      "--check-only" if op == "create" => checks.push(args[at + 1])
      _ => fail("unknown option: " + args[at])
    }
    at = at + 2
  }
  if op == "create" {
    guard at < args.length() && @par.safe_name(args[at]) else { fail(usage) }
    if parity < 1 || parity > 32 {
      fail("expected 1 to 32 recovery slices")
    }
    if per_volume is Some(n) {
      if n < 1 || n > 32 {
        fail("expected 1 to 32 recovery blocks per volume")
      }
      if !valid_index_name(args[at]) {
        fail(
          "split output requires a .par2 index name; .volN+N.par2 names are reserved for recovery volumes",
        )
      }
    }
    let base = base_opt.unwrap_or(".")
    let dest = base + "/" + args[at]
    check_io(check_path(dest))
    let filenames = []
    for i = at + 1; i < args.length(); i = i + 1 {
      for path in collect(base, args[i]) {
        filenames.push(path)
      }
    }
    let check_names = []
    for name in checks {
      for path in collect(base, name) {
        check_names.push(path)
      }
    }
    if filenames.length() + check_names.length() > 4096 {
      fail("more than 4096 files")
    }
    let inputs : Array[@par.FileInfo] = []
    let groups = [filenames, check_names]
    for gi = 0; gi < groups.length(); gi = gi + 1 {
      for name in groups[gi] {
        guard size_of(base + "/" + name) is Some(size) else {
          fail("missing input: " + name)
        }
        inputs.push({ name, size, recoverable: gi == 0, })
      }
    }
    let bytes = @par.create_stream(
      inputs,
      (name, at, n) => chunk(base + "/" + name, at, n),
      width?,
      recovery_blocks=parity,
    )
    if per_volume is Some(n) {
      let parts = @par.split_volume(bytes, recovery_blocks_per_volume=n)
      let names = [dest]
      let stem = dest[:dest.length() - 5].to_owned()
      for i = 1; i < parts.length(); i = i + 1 {
        let start = (i - 1) * n
        let count = if parity - start < n { parity - start } else { n }
        names.push(
          stem + ".vol" + padded(start) + "+" + padded(count) + ".par2",
        )
      }
      write_volume_set(names, parts)
      for name in names {
        println("created " + name)
      }
    } else {
      check_io(write_new(dest, bytes))
      println("created " + dest)
    }
    return 0
  }
  if op != "inspect" && op != "verify" && op != "repair" {
    fail(usage)
  }
  let start = if op == "repair" { at + 1 } else { at }
  if args.length() <= start || args.length() - start > 256 {
    fail(usage)
  }
  let mut budget = @par.MaxVolumeBytes
  let vols = []
  let paths = discover_volumes(args[start:].to_owned(), discovery)
  for path in paths {
    guard read(path, budget) is Some(v) else {
      fail("missing recovery volume: " + path)
    }
    budget = budget - v.length()
    vols.push(v)
  }
  let set = @par.read_set(vols)
  for message in set.warnings() {
    eprintln("warning: " + message)
  }
  if op == "inspect" {
    for creator in set.creators() {
      println("creator " + creator)
    }
    println("recovery blocks \{set.recovery_blocks()}")
    for status in set.files() {
      let kind = if status.recoverable { "recoverable" } else { "check-only" }
      println("\{kind} \{status.name}")
    }
    return 0
  }
  let base = base_opt.unwrap_or(parent(args[start]))
  check_io(check_path(base))
  if op == "verify" {
    let mut code = 0
    for
      status in set.verify_stream(name => size_of(base + "/" + name), (
        name,
        at,
        n,
      ) => chunk(base + "/" + name, at, n)) {
      let kind = if status.recoverable { "" } else { " [check-only]" }
      if status.healthy {
        println("ok " + status.name + kind)
      } else {
        let reason = if status.missing { "missing" } else { "damaged" }
        println(
          "\{reason} \{status.name} (\{status.damaged_slices.length()} bad slices)\{kind}",
        )
        code = 1
      }
    }
    return code
  }
  repair_disk(set, base, args[at]) catch {
    e => fail(e.to_string() + "; creators: " + set.creators().join("; "))
  }
  println(
    "recovered \{set.files().filter(fn(f){f.recoverable}).length()} files into " +
    args[at],
  )

  0
}

///|
fn padded(n : Int32) -> String {
  if n < 10 {
    "00\{n}"
  } else if n < 100 {
    "0\{n}"
  } else {
    n.to_string()
  }
}

///|
fn main {
  let args = @env.args()
  let code = run(args[2:].to_owned()) catch {
    e => {
      eprintln(e.to_string())
      2
    }
  }
  exit_code(code)
}
