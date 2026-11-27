"""Assemble the standalone CLI with MoonPar2 and standard-library notices."""
import argparse
import os
from pathlib import Path
import shutil

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("output", type=Path)
args = parser.parse_args()
moon = shutil.which("moon")
if not moon:
    parser.error("moon must be on PATH")
moon_home = Path(os.environ.get("MOON_HOME") or Path(moon).resolve().parents[1])
core = moon_home / "lib" / "core"
source = root / "_build/js/debug/build/cmd/main/main.js"
notices = [("MoonPar2", root / "LICENSE"), ("moonbitlang/core", core / "LICENSE"),
           ("moonbitlang/core NOTICE", core / "NOTICE")]
header = []
for component, path in notices:
    header.append("// " + component)
    header.extend("// " + line for line in path.read_text(encoding="utf-8").splitlines())
payload = ("\n".join(header) + "\n").encode("utf-8") + source.read_bytes()
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_bytes(payload)
