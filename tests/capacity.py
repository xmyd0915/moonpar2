"""Exercise an exact-size ZIP backup through the built Node CLI."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
from time import perf_counter
import zipfile

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "_build/js/debug/build/cmd/main/main.js"
MIB = 1024**2
MEASUREMENTS = []


def run(folder, probe, label, args, expected=0):
    start = perf_counter()
    p = subprocess.run(["node", "--require", str(probe), str(CLI), *args],
                       cwd=folder, capture_output=True, text=True)
    if p.returncode != expected:
        raise RuntimeError(f"{label}: {p.stdout}\n{p.stderr}")
    rss = next(int(line[4:]) for line in p.stderr.splitlines() if line.startswith("RSS:"))
    elapsed = perf_counter()-start
    MEASUREMENTS.append({"command":label,"seconds":round(elapsed,3),"peak_rss_mib":round(rss/1024,1)})
    print(f"{label:16} {elapsed:.2f} s, peak RSS {rss/1024:.1f} MiB", flush=True)
    return p.stdout + p.stderr


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(MIB), b""):
            h.update(chunk)
    return h.hexdigest()


def exercise(folder, size, reference):
    probe = folder / "rss.cjs"
    probe.write_text("process.on('exit',()=>console.error('RSS:'+process.resourceUsage().maxRSS));")
    archive = folder / "photos.zip"
    note = folder / "catalog.txt"
    note.write_bytes(b"one archive, one catalog\n")
    info = zipfile.ZipInfo("sample.bin", date_time=(2020, 1, 1, 0, 0, 0))
    with zipfile.ZipFile(archive, "w") as z:
        z.writestr(info, b"")
    length = size - archive.stat().st_size - note.stat().st_size
    block = hashlib.shake_256(b"MoonPar2 capacity sample").digest(MIB)
    with zipfile.ZipFile(archive, "w") as z, z.open(info, "w") as out:
        while length:
            n = min(length, len(block))
            out.write(block[:n])
            length -= n
    assert archive.stat().st_size + note.stat().st_size == size
    originals = {p.name: digest(p) for p in (archive, note)}
    inputs = list(originals)
    run(folder, probe, "create", ["create", "--recovery-blocks", "8", "backup.par2", *inputs])
    run(folder, probe, "verify clean", ["verify", "backup.par2"])
    if reference:
        subprocess.run([reference, "v", "-q", "-q", "--full-hash", "backup.par2"],
                       cwd=folder, check=True, stdout=subprocess.DEVNULL)
    if size == 256*MIB:
        (folder / "one.bin").write_bytes(b"x")
        result = run(folder, probe, "over capacity",
                     ["create", "over.par2", *inputs, "one.bin"], 2)
        assert "size budget" in result and not (folder / "over.par2").exists()
    note.unlink()
    with archive.open("r+b") as f:
        f.seek(size // 2)
        value = f.read(1)
        f.seek(-1, 1)
        f.write(bytes([value[0] ^ 0xff]))
    status = run(folder, probe, "verify damage", ["verify", "backup.par2"], 1)
    assert "damaged photos.zip" in status and "missing catalog.txt" in status
    run(folder, probe, "repair", ["repair", "out", "backup.par2"])
    for name, expected in originals.items():
        assert digest(folder / "out" / name) == expected
    with zipfile.ZipFile(folder / "out/photos.zip") as z:
        assert z.testzip() is None
    if reference:
        subprocess.run([reference, "r", "-q", "-q", "-t1", "backup.par2"],
                       cwd=folder, check=True, stdout=subprocess.DEVNULL)
        for name, expected in originals.items():
            assert digest(folder / name) == expected
        # Exercise the reader with different slice boundaries and nonzero
        # parity exponents chosen by the other writer.
        subprocess.run([reference, "c", "-q", "-q", "-t1", "-s65532", "-c3",
                        "-n1", "-f7", "external.par2", *inputs], cwd=folder,
                       check=True, stdout=subprocess.DEVNULL)
        note.unlink()
        with archive.open("r+b") as f:
            f.seek(-1, 2)
            original_byte = f.read(1)
            f.seek(-1, 2)
            f.write(bytes([original_byte[0] ^ 0x80]))
        volumes = [p.name for p in sorted(folder.glob("external*.par2"))]
        run(folder, probe, "external repair", ["repair", "from-external", *volumes])
        for name, expected in originals.items():
            assert digest(folder / "from-external" / name) == expected
    print(f"PASS: {size} bytes, restored ZIP and catalog match original SHA-256", flush=True)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--mib", type=int, choices=range(1, 257), default=8, metavar="1..256")
    ap.add_argument("--par2", help="also verify and repair with par2cmdline 1.4.0")
    ap.add_argument("--report", type=Path)
    args = ap.parse_args()
    with tempfile.TemporaryDirectory(prefix="moonpar2-capacity-") as tmp:
        exercise(Path(tmp), args.mib * MIB, args.par2)
    if args.report:
        args.report.parent.mkdir(parents=True,exist_ok=True)
        args.report.write_text(json.dumps({"bytes":args.mib*MIB,"result":"passed",
                                          "measurements":MEASUREMENTS},indent=2)+"\n",encoding="utf-8")
