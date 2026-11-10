"""Large-file, bounded-heap acceptance. Every byte is hashed; no local source override."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
from time import perf_counter

ROOT=Path(__file__).resolve().parents[1]
CLI=ROOT/"_build/js/debug/build/cmd/main/main.js"
MIB=1024**2


def digest(path):
    h=hashlib.sha256()
    with path.open("rb") as f:
        for b in iter(lambda:f.read(MIB),b""):h.update(b)
    return h.hexdigest()


def exercise(folder,size,reference):
    probe=folder/"rss.cjs"
    probe.write_text("process.on('exit',()=>console.error('RSS:'+process.resourceUsage().maxRSS));")
    measurements=[]
    def run(label,args,expected=0):
        start=perf_counter()
        p=subprocess.run(["node","--max-old-space-size=256","--require",str(probe),
                          str(CLI),*args],cwd=folder,capture_output=True,text=True)
        assert p.returncode==expected,(label,p.stdout,p.stderr)
        rss=next(int(x[4:])/1024 for x in p.stderr.splitlines() if x.startswith("RSS:"))
        assert rss<512,(label,rss)
        measurements.append({"command":label,"seconds":round(perf_counter()-start,3),"rss_mib":round(rss,1)})
        print(measurements[-1],flush=True)
        return p.stdout+p.stderr
    source=folder/"data"
    source.mkdir()
    big=source/"archive.bin"
    block=hashlib.shake_256(b"MoonPar2 streaming acceptance").digest(MIB)
    with big.open("wb") as out:
        remaining=size
        while remaining:
            n=min(len(block),remaining)
            out.write(block[:n])
            remaining-=n
    (source/"note.txt").write_bytes(b"restore this note")
    hashes={p.name:digest(p) for p in source.iterdir()}
    run("create",["create","--recovery-blocks","4","backup.par2","data"])
    run("verify",["verify","backup.par2"])
    if reference:
        subprocess.run([reference,"v","-q","-q","-t1","--full-hash","backup.par2"],cwd=folder,check=True)
    (source/"note.txt").unlink()
    with big.open("r+b") as f:
        f.seek(-1,2)
        old=f.read(1)
        f.seek(-1,2)
        f.write(bytes([old[0]^0xff]))
    run("detect",["verify","backup.par2"],1)
    run("repair",["repair","out","backup.par2"])
    for name,h in hashes.items():assert digest(folder/"out/data"/name)==h
    assert not list(folder.glob(".moonpar2-stage-*"))
    shutil.rmtree(folder/"out")
    if reference:
        subprocess.run([reference,"r","-q","-q","-t1","backup.par2"],cwd=folder,check=True)
        for name,h in hashes.items():assert digest(source/name)==h
    result={"bytes":size,"result":"passed","sha256":hashes,"measurements":measurements}
    print("PASS: large file SHA-256, reference repair, bounded heap and staging cleanup",flush=True)
    return result


if __name__=="__main__":
    ap=argparse.ArgumentParser()
    ap.add_argument("--mib",type=int,default=1024)
    ap.add_argument("--par2")
    ap.add_argument("--report",type=Path)
    ap.add_argument("--temp-root",type=Path)
    args=ap.parse_args()
    if not 1<=args.mib<=8192:ap.error("mib must be between 1 and 8192")
    with tempfile.TemporaryDirectory(prefix="moonpar2-stream-",dir=args.temp_root) as tmp:
        result=exercise(Path(tmp),args.mib*MIB+1,args.par2)
    if args.report:
        args.report.parent.mkdir(parents=True,exist_ok=True)
        args.report.write_text(json.dumps(result,indent=2)+"\n",encoding="utf-8")
