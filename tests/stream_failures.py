"""A failed streaming write must not publish unverified files or leave staging data."""
from pathlib import Path
import subprocess
import tempfile

CLI=Path(__file__).resolve().parents[1]/"_build/js/debug/build/cmd/main/main.js"

with tempfile.TemporaryDirectory(prefix="moonpar2-stream-errors-") as tmp:
    root=Path(tmp)
    (root/"source").write_bytes(b"original")
    subprocess.run(["node",str(CLI),"create","set.par2","source"],cwd=root,check=True)
    (root/"source").unlink()
    preload=root/"disk-full.cjs"
    preload.write_text("""
const fs=require('node:fs');
const open=fs.openSync,write=fs.writeSync;
const staged=new Set();
fs.openSync=function(p,...args){
  const fd=open.call(this,p,...args);
  if(String(p).includes('.moonpar2-stage-'))staged.add(fd);
  return fd;
};
fs.writeSync=function(fd,...args){
  if(staged.has(fd))throw Object.assign(Error('simulated disk full'),{code:'ENOSPC'});
  return write.call(this,fd,...args);
};
""")
    p=subprocess.run(["node","--require",str(preload),str(CLI),"repair","out","set.par2"],
                     cwd=root,capture_output=True,text=True)
    assert p.returncode==2 and "simulated disk full" in p.stderr,p.stderr
    assert not (root/"out").exists()
    assert not list(root.glob(".moonpar2-stage-*"))
    subprocess.run(["node",str(CLI),"repair","out","set.par2"],cwd=root,check=True)
    assert (root/"out/source").read_bytes()==b"original"
    print("PASS: streaming ENOSPC, no published output, cleanup, successful retry")
