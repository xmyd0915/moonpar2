///|
let usage = "moonpar2 create [--base-dir ROOT] [--recovery-blocks N] [--slice-size BYTES] [--check-only FILE] SET.par2 FILE_OR_DIR...\nmoonpar2 inspect INDEX.par2 [VOLUME.par2 ...]\nmoonpar2 verify [--base-dir ROOT] INDEX.par2 [VOLUME.par2 ...]\nmoonpar2 repair [--base-dir ROOT] NEW_DIRECTORY INDEX.par2 [VOLUME.par2 ...]"

///|
fn number(text : String) -> Int32 raise {
  if text.is_empty() || text.length() > 7 {
    fail("invalid numeric option")
  }
  let mut n = 0
  for c in text {
    if c < '0' || c > '9' {
      fail("expected a decimal number")
    }
    n = n * 10 + c.to_int() - 48
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
    println("MoonPar2 0.2.0")
    return 0
  }
  guard args.length() >= 2 else { fail(usage) }
  let op = args[0]
  let mut base_opt : String? = None
  let mut parity = 4
  let mut width : Int32? = None
  let checks : Array[String] = []
  let mut at = 1
  while at < args.length() && args[at].has_prefix("--") {
    guard at + 1 < args.length() else { fail(usage) }
    match args[at] {
      "--base-dir" => base_opt = Some(args[at + 1])
      "--recovery-blocks" if op == "create" => parity = number(args[at + 1])
      "--slice-size" if op == "create" => width = Some(number(args[at + 1]))
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
    let inputs = []
    let check_inputs = []
    let mut budget = @par.MaxSourceBytes
    let groups = [filenames, check_names]
    for gi = 0; gi < groups.length(); gi = gi + 1 {
      for name in groups[gi] {
        guard read(base + "/" + name, budget) is Some(bytes) else {
          fail("missing input: " + name)
        }
        budget = budget - bytes.length()
        if gi == 0 {
          inputs.push((name, bytes))
        } else {
          check_inputs.push((name, bytes))
        }
      }
    }
    let bytes = @par.create(
      inputs,
      width?,
      recovery_blocks=parity,
      non_recovery_files=check_inputs,
    )
    check_io(write_new(dest, bytes))
    println("created " + dest)
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
  for i = start; i < args.length(); i = i + 1 {
    guard read(args[i], budget) is Some(v) else {
      fail("missing recovery volume: " + args[i])
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
    for status in set.verify(Map([])) {
      let kind = if status.recoverable { "recoverable" } else { "check-only" }
      println("\{kind} \{status.name}")
    }
    return 0
  }
  let base = base_opt.unwrap_or(parent(args[start]))
  check_io(check_path(base))
  let sources : Map[String, Bytes] = Map([])
  let mut source_budget = @par.MaxSourceBytes + @par.MaxVolumeBytes
  for name in set.names() {
    if read(base + "/" + name, source_budget) is Some(b) {
      sources[name] = b
      source_budget = source_budget - b.length()
    }
  }
  if op == "verify" {
    let mut code = 0
    for status in set.verify(sources) {
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
  let outputs = set.repair(sources) catch {
    e => fail(e.to_string() + "; creators: " + set.creators().join("; "))
  }
  check_io(check_path(args[at]))
  check_io(new_dir(args[at]))
  for pair in outputs {
    let path = args[at] + "/" + pair.0
    check_io(check_path(path))
    check_io(mkdir_parents(path))
    check_io(write_new(path, pair.1))
  }
  println("recovered \{outputs.length()} files into " + args[at])
  0
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
