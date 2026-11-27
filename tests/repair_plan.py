"""Read-only repair planning, matrix rank and agreement with actual recovery."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CLI = ["node", str(ROOT / "_build/js/debug/build/cmd/main/main.js")]
PARITY = b"PAR 2.0\0RecvSlic"
DATA = {"数据/long.bin": b"abcdefghijkl", "数据/note.txt": b"note", "数据/empty": b""}
FIELDS = ("damaged recoverable files", "damaged check-only files", "missing slices",
          "recovery blocks", "independent equations")
RESULTS = []


def call(args, folder, expected=0):
    p = subprocess.run([str(x) for x in args], cwd=folder, capture_output=True,
                       encoding="utf-8", errors="replace")
    assert p.returncode == expected, (args, p.returncode, p.stdout, p.stderr)
    return p.stdout, p.stderr


def snapshot(folder):
    result = {}
    for path in folder.rglob("*"):
        relative = path.relative_to(folder).as_posix()
        if path.is_dir():
            result[relative] = "directory"
        else:
            stat = path.stat()
            result[relative] = (stat.st_size, stat.st_mtime_ns,
                                hashlib.sha256(path.read_bytes()).hexdigest())
    return result


def record(name):
    RESULTS.append({"case": name, "result": "passed"})
    print("PASS:", name, flush=True)


def check(folder, data=DATA):
    for name, contents in data.items():
        assert (folder / name).read_bytes() == contents, name


def packets(raw):
    offset = 0
    while offset < len(raw):
        assert raw[offset:offset + 8] == b"PAR2\0PKT"
        size, = struct.unpack_from("<Q", raw, offset + 8)
        packet = raw[offset:offset + size]
        assert len(packet) == size and hashlib.md5(packet[32:]).digest() == packet[16:32]
        yield packet
        offset += size


def exercise(root):
    # A plan must work even when every filesystem mutation primitive is unavailable.
    probe = root / "read-only.cjs"
    probe.write_text("""
const fs=require('node:fs'),open=fs.openSync;
for(const key of ['writeFileSync','appendFileSync','writeSync','mkdirSync','mkdtempSync',
                 'copyFileSync','linkSync','renameSync','rmSync','unlinkSync','truncateSync']){
  fs[key]=()=>{throw Error('plan attempted filesystem mutation: '+key);};
}
fs.openSync=function(path,flags,...args){
  if(typeof flags==='string'?!/^r[s]?$/.test(flags):(flags&3)!==0)
    throw Error('plan attempted writable open');
  return open.call(this,path,flags,...args);
};
""", encoding="utf-8")
    readonly = ["node", "--require", probe, CLI[1]]
    original = root / "original"
    original.mkdir()
    for name, contents in DATA.items():
        path = original / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(contents)
    (original / "catalog.txt").write_bytes(b"check-only information")
    call(CLI + ["create", "--slice-size", "4", "--recovery-blocks", "4",
                "--volume-blocks", "1", "--check-only", "catalog.txt", "set.par2", "数据"], original)

    def fixture(label, damage=False):
        folder = root / label
        shutil.copytree(original, folder)
        if damage:
            (folder / "数据/note.txt").unlink()
            (folder / "数据/long.bin").write_bytes(b"XXXXefghijkl")
        return folder

    def plan(folder, args, state, numbers, expected=0):
        before = snapshot(folder)
        stdout, stderr = call(readonly + ["plan", *args], folder, expected)
        assert snapshot(folder) == before, "plan modified input files or directory layout"
        lines = stdout.splitlines()
        assert "plan " + state in lines, (stdout, stderr)
        for field, number in zip(FIELDS, numbers):
            assert f"{field} {number}" in lines, (field, stdout, stderr)
        return stdout, stderr

    folder = fixture("healthy")
    plan(folder, ["set.par2"], "healthy", [0, 0, 0, 4, 0])
    record("healthy protected set reports no missing slices without writing")

    folder = fixture("repairable", True)
    plan(folder, ["set.par2"], "repairable", [2, 0, 2, 4, 2])
    before = snapshot(folder)
    call(CLI + ["repair", "out", "set.par2"], folder)
    check(folder / "out")
    assert not (folder / "out/catalog.txt").exists()
    after = snapshot(folder)
    assert all(after[name] == value for name, value in before.items())
    record("two missing slices plan repairable and actual repair matches originals")

    folder = fixture("insufficient")
    (folder / "数据/long.bin").unlink()
    (folder / "数据/note.txt").unlink()
    # Both missing files occupy four slices; deliberately retain only three equations.
    (folder / "set.vol003+001.par2").unlink()
    plan(folder, ["set.par2"], "insufficient", [2, 0, 4, 3, 3], 1)
    before = snapshot(folder)
    call(CLI + ["repair", "out", "set.par2"], folder, 2)
    assert snapshot(folder) == before
    record("insufficient plan agrees with repair failure and unchanged sources")

    folder = fixture("selected-volumes", True)
    plan(folder, ["--no-discovery", "set.par2"], "insufficient", [2, 0, 2, 0, 0], 1)
    plan(folder, ["--no-discovery", "set.vol000+001.par2"], "insufficient", [2, 0, 2, 1, 1], 1)
    chosen = ["--no-discovery", "set.vol000+001.par2", "set.vol001+001.par2"]
    plan(folder, chosen, "repairable", [2, 0, 2, 2, 2])
    call(CLI + ["repair", "--no-discovery", "out", *chosen[1:]], folder)
    check(folder / "out")
    record("index and explicitly selected remaining volumes produce different exact plans")

    folder = fixture("lost-volume", True)
    (folder / "set.vol000+001.par2").write_bytes(b"damaged volume")
    _, stderr = plan(folder, ["set.par2"], "repairable", [2, 0, 2, 3, 2])
    assert "warning:" in stderr
    call(CLI + ["repair", "out", "set.par2"], folder)
    check(folder / "out")
    record("damaged-volume diagnostics and surviving equations agree with recovery")

    folder = fixture("check-only")
    (folder / "catalog.txt").write_bytes(b"changed")
    plan(folder, ["set.par2"], "healthy", [0, 1, 0, 4, 0])
    call(CLI + ["verify", "set.par2"], folder, 1)
    (folder / "catalog.txt").unlink()
    plan(folder, ["set.par2"], "healthy", [0, 1, 0, 4, 0])
    record("check-only corruption and absence do not imply protected-file repair")

    folder = fixture("empty-and-long")
    (folder / "数据/empty").unlink()
    (folder / "数据/long.bin").write_bytes(DATA["数据/long.bin"] + b"trailing data")
    plan(folder, ["--no-discovery", "set.par2"], "repairable", [2, 0, 0, 0, 0])
    call(CLI + ["repair", "--no-discovery", "out", "set.par2"], folder)
    check(folder / "out")
    record("empty-file and excess-tail repair need no recovery equations")

    folder = fixture("explicit-base", True)
    metadata = folder / "metadata"
    metadata.mkdir()
    for path in list(folder.glob("*.par2")):
        path.rename(metadata / path.name)
    plan(folder, ["--base-dir", str(folder), "metadata/set.par2"], "repairable", [2, 0, 2, 4, 2])
    call(CLI + ["repair", "--base-dir", str(folder), "out", "metadata/set.par2"], folder)
    check(folder / "out")
    record("explicit base directory is shared by planning and repair")

    folder = fixture("dependent-equations", True)
    zero = next(p for p in packets((folder / "set.vol000+001.par2").read_bytes()) if p[48:64] == PARITY)
    # In GF(2^16), exponent 65535 gives the same all-ones row as exponent zero.
    dependent = bytearray(zero)
    struct.pack_into("<I", dependent, 64, 65535)
    dependent[16:32] = hashlib.md5(dependent[32:]).digest()
    (folder / "dependent.par2").write_bytes((folder / "set.par2").read_bytes() + zero + dependent)
    plan(folder, ["--no-discovery", "dependent.par2"], "insufficient", [2, 0, 2, 2, 1], 1)
    call(CLI + ["repair", "--no-discovery", "out", "dependent.par2"], folder, 2)
    assert not (folder / "out").exists()
    record("dependent recovery equations are not counted as independent repair capacity")

    folder = fixture("bad-input")
    before = snapshot(folder)
    call(readonly + ["plan", "missing.par2"], folder, 2)
    assert snapshot(folder) == before
    record("missing recovery input is an error without filesystem side effects")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="moonpar2-plan-") as temporary:
        exercise(Path(temporary))
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps({"cases": RESULTS}, indent=2) + "\n", encoding="utf-8")
