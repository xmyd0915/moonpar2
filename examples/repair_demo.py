"""Create a recovery volume, damage two sample files, and recover both."""
from hashlib import sha256
from pathlib import Path
import subprocess
import tempfile

CLI = Path(__file__).resolve().parents[1] / "_build/js/debug/build/cmd/main/main.js"


def main():
    if not CLI.is_file():
        raise SystemExit("Build first: moon build cmd/main --target js")
    with tempfile.TemporaryDirectory(prefix="moonpar2-demo-") as tmp:
        folder = Path(tmp)
        files = {"notes.txt": b"November archive\n", "scan.bin": bytes(range(256)) * 20}
        for name, data in files.items():
            (folder / name).write_bytes(data)
        cli = ["node", str(CLI)]
        subprocess.run(cli + ["create", "backup.par2", *files], cwd=folder, check=True)
        (folder / "notes.txt").unlink()
        image = bytearray(files["scan.bin"])
        image[-1] ^= 128
        (folder / "scan.bin").write_bytes(image)
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
