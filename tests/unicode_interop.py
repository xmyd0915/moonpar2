"""Exercise UTF-8 paths, Unicode Filename packets, and a second PAR2 implementation."""
import argparse
import hashlib
import json
import os
import shutil
from pathlib import Path
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
CLI=["node",str(ROOT/"_build/js/debug/build/cmd/main/main.js")]


def call(args,folder,expected=0):
    p=subprocess.run(args,cwd=folder,capture_output=True,encoding="utf-8",errors="replace")
    if p.returncode!=expected: raise AssertionError(f"{args}: {p.returncode}\n{p.stdout}\n{p.stderr}")
    return p.stdout+p.stderr


def put(folder,data):
    for name,b in data.items():
        p=folder/name
        p.parent.mkdir(parents=True,exist_ok=True)
        p.write_bytes(b)


def check(folder,data):
    for name,b in data.items():
        assert hashlib.sha256((folder/name).read_bytes()).digest()==hashlib.sha256(b).digest(),name


def exercise(folder,reference,multipar=False):
    data={"文档/说明.txt":"中文和日本語".encode(),"照片/旅行🌙/记录.bin":bytes(range(250))*3}
    put(folder,data)
    call(CLI+["create","--slice-size","256","ours.par2",*data],folder)
    if multipar:
        call([reference,"v","/uo","ours.par2"],folder)
    else:
        call([reference,"v","-q","--full-hash","ours.par2"],folder)
    (folder/"文档/说明.txt").unlink()
    (folder/"照片/旅行🌙/记录.bin").write_bytes(bytes(range(250))*2+b"x"*250)
    call(CLI+["repair","out","ours.par2"],folder)
    check(folder/"out",data)
    shutil.rmtree(folder/"out")
    if multipar: call([reference,"r","/uo","ours.par2"],folder,16)
    else: call([reference,"r","-q","-t1","ours.par2"],folder)
    check(folder,data)
    if multipar:
        call([reference,"c","/uo","/up","/ss256","/rn4","theirs.par2",*data],folder)
    else:
        call([reference,"c","-q","-t1","-s256","-c4","-n1","theirs.par2",*data],folder)
    (folder/"文档/说明.txt").unlink()
    (folder/"照片/旅行🌙/记录.bin").write_bytes(bytes(range(250))*2+b"x"*250)
    volumes=sorted(p.name for p in folder.glob("theirs*.par2"))
    call(CLI+["repair","from-reference",*volumes],folder)
    check(folder/"from-reference",data)
    print("PASS: Unicode paths and both recovery directions:",reference,flush=True)
    if multipar:
        put(folder,{"important.bin":b"recover me","catalog.txt":b"check me"})
        call(CLI+["create","--check-only","catalog.txt","checks.par2","important.bin"],folder)
        call([reference,"v","/uo","checks.par2"],folder)
        (folder/"important.bin").unlink()
        call([reference,"r","/uo","checks.par2"],folder,16)
        assert (folder/"important.bin").read_bytes()==b"recover me"
        print("PASS: MultiPar validates non-recovery metadata and repairs recovery members",flush=True)


if __name__=="__main__":
    ap=argparse.ArgumentParser()
    ap.add_argument("--par2")
    ap.add_argument("--multipar")
    args=ap.parse_args()
    for reference,is_multi in [(args.par2,False),(args.multipar,True)]:
        if reference:
            with tempfile.TemporaryDirectory(prefix="moonpar2-unicode-") as tmp:
                exercise(Path(tmp),reference,is_multi)
