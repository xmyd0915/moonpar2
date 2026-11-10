"""Split-volume discovery, independent recovery and transactional publication."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CLI = ["node", str(ROOT / "_build/js/debug/build/cmd/main/main.js")]
STEM = "备份🌙"
INDEX = STEM + ".par2"
VOLUMES = [f"{STEM}.vol{i:03}+002.par2" for i in (0, 2, 4)]
DATA = {"文档/说明.txt": "恢复这份说明".encode(),
        "照片/旅行🌙/记录.bin": bytes(range(251)) * 7,
        "文档/empty": b""}
RESULTS = []


def call(args, folder, expected=0):
    p = subprocess.run([str(x) for x in args], cwd=folder, capture_output=True,
                       encoding="utf-8", errors="replace")
    assert p.returncode == expected, (args, p.returncode, p.stdout, p.stderr)
    return p.stdout + p.stderr


def result(name):
    RESULTS.append({"case": name, "result": "passed"})
    print("PASS:", name, flush=True)


def put(folder, data=DATA):
    for name, contents in data.items():
        path = folder / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(contents)


def damage(folder):
    (folder / "文档/说明.txt").unlink()
    path = folder / "照片/旅行🌙/记录.bin"
    contents = bytearray(path.read_bytes())
    contents[-1] ^= 0xff
    path.write_bytes(contents)


def check(folder, data=DATA):
    for name, contents in data.items():
        assert hashlib.sha256((folder / name).read_bytes()).digest() == hashlib.sha256(contents).digest(), name


def create(folder, preload=None):
    prefix = CLI if preload is None else ["node", "--require", str(preload), CLI[1]]
    return prefix + ["create", "--recovery-blocks", "6", "--slice-size", "256",
                     "--volume-blocks", "2", INDEX, "文档", "照片"]


def exercise(root, reference):
    original = root / "original"
    original.mkdir()
    put(original)
    call(create(original), original)
    assert sorted(p.name for p in original.glob("*.par2")) == sorted([INDEX, *VOLUMES])
    assert "recovery blocks 0" in call(CLI + ["inspect", "--no-discovery", INDEX], original)
    assert "recovery blocks 6" in call(CLI + ["inspect", INDEX], original)
    call([reference, "v", "-q", "-t1", "--full-hash", INDEX], original)
    result("split Unicode directory set, index-only reference verification")

    def fixture(label):
        folder = root / label
        shutil.copytree(original, folder)
        damage(folder)
        return folder

    folder = fixture("index-repair")
    call(CLI + ["repair", "out", INDEX], folder)
    check(folder / "out")
    shutil.rmtree(folder / "out")
    call([reference, "r", "-q", "-t1", INDEX], folder)
    check(folder)
    result("index discovers all recovery volumes; both tools repair independently")

    folder = fixture("volume-repair")
    assert "recovery blocks 6" in call(CLI + ["inspect", VOLUMES[1]], folder)
    call(CLI + ["repair", "out", VOLUMES[1]], folder)
    check(folder / "out")
    result("any recovery volume discovers its sibling volumes")

    folder = fixture("missing-index")
    (folder / INDEX).unlink()
    call(CLI + ["repair", "out", VOLUMES[2]], folder)
    check(folder / "out")
    result("self-contained recovery volumes rebuild without an index")

    folder = fixture("damaged-volume")
    (folder / VOLUMES[0]).write_bytes(b"damaged recovery volume")
    status = call(CLI + ["inspect", INDEX], folder)
    assert "recovery blocks 4" in status and "warning:" in status
    call(CLI + ["repair", "out", INDEX], folder)
    check(folder / "out")
    result("unusable recovery volume is reported while surviving volumes repair")

    folder = fixture("explicit-only")
    call(CLI + ["repair", "--no-discovery", "no-output", INDEX], folder, 2)
    assert not (folder / "no-output").exists()
    status = call(CLI + ["inspect", "--no-discovery", VOLUMES[1]], folder)
    assert "recovery blocks 2" in status
    call(CLI + ["repair", "--no-discovery", "out", VOLUMES[1]], folder)
    check(folder / "out")
    result("no-discovery uses exactly the explicit recovery inputs")

    folder = fixture("deduplicated")
    probe = folder / "read-counts.cjs"
    probe.write_text("""
const fs=require('node:fs'),p=require('node:path');
const open=fs.openSync,counts={};
fs.openSync=function(path,...args){
  if(/\\.par2$/i.test(String(path))){const key=p.resolve(path);counts[key]=(counts[key]||0)+1;}
  return open.call(this,path,...args);
};
process.on('exit',()=>console.error('READ_COUNTS:'+JSON.stringify(counts)));
""", encoding="utf-8")
    status = call(["node", "--require", probe, CLI[1], "inspect", INDEX,
                   VOLUMES[0], folder / VOLUMES[0]], folder)
    assert "recovery blocks 6" in status
    counts = json.loads(next(line[len("READ_COUNTS:"):] for line in status.splitlines()
                             if line.startswith("READ_COUNTS:")))
    assert len(counts) == 4 and all(count == 1 for count in counts.values()), counts
    call(CLI + ["repair", "out", INDEX, VOLUMES[0], folder / VOLUMES[0]], folder)
    check(folder / "out")
    result("overlapping explicit, absolute and discovered inputs are deduplicated")

    folder = fixture("strict-names")
    for name in (STEM + "-other.vol000+002.par2", STEM + ".volx+002.par2",
                 STEM + ".vol000+002.par2.bak", STEM + ".vol000-002.par2"):
        (folder / name).write_bytes(b"must not be read")
    status = call(CLI + ["inspect", INDEX], folder)
    assert "recovery blocks 6" in status and "warning:" not in status
    call(CLI + ["repair", "out", INDEX], folder)
    check(folder / "out")
    result("discovery excludes neighboring prefixes and non-volume suffixes")

    folder = fixture("matching-directory")
    (folder / (STEM + ".vol006+002.par2")).mkdir()
    call(CLI + ["repair", "out", INDEX], folder, 2)
    assert not (folder / "out").exists()
    result("matching non-file volume is refused before recovery output")

    folder = fixture("case-insensitive")
    upper_index = STEM + ".PAR2"
    upper_volume = STEM + ".VOL002+002.PAR2"
    (folder / INDEX).rename(folder / upper_index)
    (folder / VOLUMES[1]).rename(folder / upper_volume)
    status = call(CLI + ["inspect", upper_index], folder)
    assert "recovery blocks 6" in status
    call(CLI + ["repair", "out", upper_volume], folder)
    check(folder / "out")
    result("discovery accepts uppercase PAR2 extensions and volume markers")

    folder = root / "existing-volume"
    folder.mkdir()
    put(folder)
    marker = b"existing content must remain"
    (folder / VOLUMES[1]).write_bytes(marker)
    call(create(folder), folder, 2)
    assert (folder / VOLUMES[1]).read_bytes() == marker
    assert sorted(p.name for p in folder.glob("*.par2")) == [VOLUMES[1]]
    assert not list(folder.glob(".moonpar2-*"))
    result("existing volume rejects the entire publication without overwriting")

    for fallback in (False, True):
        folder = root / ("copy-failure" if fallback else "link-failure")
        folder.mkdir()
        put(folder)
        preload = folder / "publication-failure.cjs"
        preload.write_text("""
const fs=require('node:fs');
const link=fs.linkSync,write=fs.writeFileSync;
let published=0;
const inject=()=>{if(++published===2)throw Object.assign(Error('simulated publish failure'),{code:'EIO'});};
""" + ("""
fs.linkSync=function(){throw Object.assign(Error('test copy fallback'),{code:'EPERM'});};
fs.writeFileSync=function(fd,...args){
  if(typeof fd==='number'&&++published===2){
    write.call(this,fd,Buffer.from('partial output'));
    throw Object.assign(Error('simulated publish failure'),{code:'EIO'});
  }
  return write.call(this,fd,...args);
};
""" if fallback else """
fs.linkSync=function(...args){inject();return link.apply(this,args);};
"""), encoding="utf-8")
        status = call(create(folder, preload), folder, 2)
        assert "simulated publish failure" in status
        assert not list(folder.glob("*.par2"))
        assert not list(folder.glob(".moonpar2-*"))
        call(create(folder), folder)
        call(CLI + ["verify", INDEX], folder)
        result(("exclusive-write fallback" if fallback else "hard-link") + " publication failure rolls back all new volumes; retry succeeds")

    folder = root / "external-writer"
    folder.mkdir()
    external = {name: b for name, b in DATA.items() if b}
    put(folder, external)
    call([reference, "c", "-q", "-t1", "-s256", "-c6", "-n3", INDEX, *external], folder)
    damage(folder)
    call(CLI + ["repair", "out", INDEX], folder)
    check(folder / "out", external)
    shutil.rmtree(folder / "out")
    (folder / INDEX).unlink()
    volume = sorted(folder.glob("*.par2"))[0]
    call(CLI + ["repair", "no-index", volume], folder)
    check(folder / "no-index", external)
    result("par2cmdline-written multi-volume set discovers and repairs with or without index")

    folder = root / "numeric-options"
    folder.mkdir()
    (folder / "tiny").write_bytes(b"wide recovery slice")
    call(CLI + ["create", "--slice-size", "16777216", "--recovery-blocks", "1",
                "wide.par2", "tiny"], folder)
    call(CLI + ["verify", "wide.par2"], folder)
    call(CLI + ["create", "--slice-size", "2147483648", "overflow.par2", "tiny"], folder, 2)
    assert not (folder / "overflow.par2").exists()
    result("16 MiB slice option is accepted while overflowing decimal input is rejected")

    folder = root / "reserved-index-name"
    folder.mkdir()
    (folder / "tiny").write_bytes(b"split index naming")
    call(CLI + ["create", "--volume-blocks", "2", "--recovery-blocks", "4",
                "backup.vol123+456.par2", "tiny"], folder, 2)
    assert not list(folder.glob("*.par2"))
    assert not list(folder.glob(".moonpar2-*"))
    result("split index refuses a reserved recovery-volume filename before writing")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--par2", required=True)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="moonpar2-volumes-") as temporary:
        exercise(Path(temporary), args.par2)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps({"cases": RESULTS}, indent=2) + "\n", encoding="utf-8")
