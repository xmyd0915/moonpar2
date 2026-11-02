///|
let usage = "moonpar2 create [--recovery-blocks N] SET.par2 FILE...\nmoonpar2 verify INDEX.par2 [VOLUME.par2 ...]\nmoonpar2 repair NEW_DIRECTORY INDEX.par2 [VOLUME.par2 ...]"

///|
fn run(args : Array[String]) -> Int32 raise {
  if args == ["--help"] || args == ["-h"] {
    println(usage)
    return 0
  }
  guard args.length() >= 2 else { fail(usage) }
  let op = args[0]
  if op == "create" {
    let mut dest = 1
    let mut parity = 4
    if args[1] == "--recovery-blocks" {
      guard args.length() >= 5 else { fail(usage) }
      guard args[2].length() <= 2 else {
        fail("expected 1 to 32 recovery slices")
      }
      parity = 0
      for c in args[2] {
        if c < '0' || c > '9' {
          fail("expected a decimal recovery block count")
        }
        parity = parity * 10 + c.to_int() - 48
      }
      if parity < 1 || parity > 32 {
        fail("recovery block count must be between 1 and 32")
      }
      dest = 3
    }
    guard args.length() > dest + 1 &&
      args.length() - dest - 1 <= 64 &&
      @par.safe_name(args[dest]) else {
      fail(usage)
    }
    let inputs = []
    let mut budget = @par.MaxSourceBytes
    for i = dest + 1; i < args.length(); i = i + 1 {
      let name = args[i]
      if !@par.safe_name(name) {
        fail("expected a portable filename: " + name)
      }
      guard read(name, budget) is Some(bytes) else {
        fail("missing input: " + name)
      }
      budget = budget - bytes.length()
      inputs.push((name, bytes))
    }
    let bytes = @par.create(inputs, recovery_blocks=parity)
    check_io(write_new(args[dest], bytes))
    println("created " + args[dest])
    return 0
  }
  if op != "repair" && op != "verify" {
    fail(usage)
  }
  let start = if op == "repair" { 2 } else { 1 }
  if args.length() <= start || args.length() - start > 64 {
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
  let base = parent(args[start])
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
      if status.healthy {
        println("ok " + status.name)
      } else {
        let reason = if status.missing { "missing" } else { "damaged" }
        println(
          "\{reason} \{status.name} (\{status.damaged_slices.length()} bad slices)",
        )
        code = 1
      }
    }
    return code
  }
  let outputs = set.repair(sources)
  check_io(new_dir(args[1]))
  for pair in outputs {
    check_io(write_new(args[1] + "/" + pair.0, pair.1))
  }
  println("recovered \{outputs.length()} files into " + args[1])
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
