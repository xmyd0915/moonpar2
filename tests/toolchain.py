"""Record the compiler actually used by this checkout's CI and release builds."""
from pathlib import Path
import re
import subprocess

expected = "1.0.0-rc1+3c0520448"
versions = subprocess.check_output(["moon", "version", "--all"], text=True)
print(versions, end="")
if not re.search(r"(?m)^moonc v?" + re.escape(expected) + r"(?=\s|$)", versions):
    raise SystemExit(f"Expected moonc {expected}")
report = Path(__file__).resolve().parents[1] / "_build/toolchain.txt"
report.parent.mkdir(exist_ok=True)
report.write_text(versions, encoding="utf-8")
