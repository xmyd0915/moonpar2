"""Recover a directory tree despite simultaneous source and PAR2 damage."""
from hashlib import sha256
from pathlib import Path
import subprocess
import struct
import tempfile

CLI = Path(__file__).resolve().parents[1] / "_build/js/debug/build/cmd/main/main.js"


def main():
    if not CLI.is_file():
        raise SystemExit("Build first: moon build cmd/main --target js")
    with tempfile.TemporaryDirectory(prefix="moonpar2-demo-") as tmp:
        folder = Path(tmp)
        files = {"documents/notes.txt": b"November archive\n",
                 "photos/2026/scan.bin": bytes(range(256)) * 20,
                 "documents/empty.txt": b""}
        for name, data in files.items():
            (folder / name).parent.mkdir(parents=True, exist_ok=True)
            (folder / name).write_bytes(data)
        cli = ["node", str(CLI)]
        subprocess.run(cli + ["create", "backup.par2", "documents", "photos"], cwd=folder, check=True)
        (folder / "documents/notes.txt").unlink()
        (folder / "documents/empty.txt").unlink()
        image = bytearray(files["photos/2026/scan.bin"])
        image[-1] ^= 128
        (folder / "photos/2026/scan.bin").write_bytes(image)
        volume = bytearray((folder / "backup.par2").read_bytes())
        at = 0
        while at < len(volume):
            size, = struct.unpack_from("<Q", volume, at + 8)
            if volume[at+48:at+64] == b"PAR 2.0\0RecvSlic":
                volume[at+size-1] ^= 1
                break
            at += size
        (folder / "backup.par2").write_bytes(volume)
        subprocess.run(cli + ["inspect", "backup.par2"], cwd=folder, check=True)
        status = subprocess.run(cli + ["verify", "backup.par2"], cwd=folder)
        if status.returncode != 1:
            raise RuntimeError("expected damaged or missing files")
        subprocess.run(cli + ["repair", "restored", "backup.par2"], cwd=folder, check=True)
        for name, original in files.items():
            digest = sha256((folder / "restored" / name).read_bytes()).hexdigest()
            if digest != sha256(original).hexdigest():
                raise RuntimeError("restored content differs: " + name)
            print(f"{name}: SHA-256 matches ({digest})")


if __name__ == "__main__":
    main()
