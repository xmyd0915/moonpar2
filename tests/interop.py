"""Exercise the built CLI and an independently installed par2cmdline."""
import argparse
import hashlib
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "_build/js/debug/build/cmd/main/main.js"


def call(command, folder, expected=0):
    proc = subprocess.run(command, cwd=folder, capture_output=True, text=True)
    if proc.returncode != expected:
        raise RuntimeError(f"{command} exited {proc.returncode}:\n{proc.stdout}\n{proc.stderr}")
    return proc.stdout


def sha(data):
    return hashlib.sha256(data).hexdigest()


def exercise(folder, reference, create_with_reference):
    originals = {
        "alpha.bin": bytes((i * 37 + i // 19) % 256 for i in range(12405)),
        "photo.dat": bytes(range(149)),
        "notes.txt": b"bring a spare drive\n",
    }
    for name, data in originals.items():
        (folder / name).write_bytes(data)
    cli = ["node", str(CLI)]
    if create_with_reference:
        call([reference, "c", "-q", "-t1", "-s256", "-c3", "-f3", "-n1",
              "set.par2", *originals], folder)
    else:
        for invalid in ("0", "33", "x"):
            call(cli + ["create", "--recovery-blocks", invalid, "bad.par2", *originals],
                 folder, 2)
            assert not (folder / "bad.par2").exists()
        call(cli + ["create", "set.par2", *originals], folder)
        call(cli + ["create", "set.par2", *originals], folder, 2)
    volumes = [p.name for p in sorted(folder.glob("*.par2"))]
    call(cli + ["verify", *volumes], folder)
    call([reference, "v", "-q", "-t1", "--full-hash", "set.par2"], folder)
    damaged = bytearray(originals["alpha.bin"])
    damaged[-1] ^= 0xB7
    (folder / "alpha.bin").write_bytes(damaged)
    (folder / "photo.dat").unlink()
    status = call(cli + ["verify", *volumes], folder, 1)
    assert "damaged alpha.bin" in status and "missing photo.dat" in status
    failed = folder / "no-parity"
    if create_with_reference:
        call(cli + ["repair", str(failed), "set.par2"], folder, 2)
        assert not failed.exists()
    call(cli + ["repair", "restored", *volumes], folder)
    out = folder / "restored"
    for name, data in originals.items():
        assert sha((out / name).read_bytes()) == sha(data)
    assert (folder / "alpha.bin").read_bytes() == damaged
    assert not (folder / "photo.dat").exists()
    call(cli + ["repair", "restored", *volumes], folder, 2)
    call([reference, "r", "-q", "-t1", "set.par2"], folder)
    for name, data in originals.items():
        assert sha((folder / name).read_bytes()) == sha(data)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--par2", default="par2", help="reference executable on PATH or absolute path")
    args = parser.parse_args()
    for other_writer in [False, True]:
        with tempfile.TemporaryDirectory(prefix="moonpar2-") as tmp:
            exercise(Path(tmp), args.par2, other_writer)
        print("PASS: " + ("par2cmdline" if other_writer else "MoonPar2") +
              " volume, both readers and repairs, SHA-256 matches")
