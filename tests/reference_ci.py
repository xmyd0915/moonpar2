"""Fetch the pinned upstream oracle and run both directions of interoperability."""
from hashlib import sha256
from io import BytesIO
from pathlib import Path, PurePosixPath
import os
import subprocess
import sys
import tempfile
from urllib.request import urlopen
from zipfile import ZipFile

ASSETS = {
    "win32": ("win-x64", "par2.exe", "200130143dba1e12f9d1be567d5a446e785d2093e5d735225d8ad0539125b71c"),
    "linux": ("linux-amd64", "par2", "6360228699d66b0141e2583b4f4b17260344c28f599bfe2e28db596b26703105"),
}


def main():
    platform, binary, digest = ASSETS[sys.platform]
    url = ("https://github.com/Parchive/par2cmdline/releases/download/v1.4.0/"
           f"par2cmdline-1.4.0-{platform}.zip")
    with urlopen(url, timeout=60) as response:
        archive = response.read()
    if sha256(archive).hexdigest() != digest:
        raise ValueError("unexpected reference archive digest")
    with tempfile.TemporaryDirectory() as tmp:
        exe = Path(tmp) / binary
        with ZipFile(BytesIO(archive)) as payload:
            name, = [n for n in payload.namelist() if PurePosixPath(n).name == binary]
            exe.write_bytes(payload.read(name))
        os.chmod(exe, 0o755)
        subprocess.run([sys.executable, str(Path(__file__).with_name("interop.py")),
                        "--par2", str(exe)], check=True)


if __name__ == "__main__":
    main()
