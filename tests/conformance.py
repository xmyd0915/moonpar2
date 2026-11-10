"""Reproducible directory, damaged-volume and hostile-path interoperability cases."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CLI = ["node", str(ROOT / "_build/js/debug/build/cmd/main/main.js")]
MAGIC = b"PAR2\0PKT"
MAIN = b"PAR 2.0\0Main\0\0\0\0"
DESC = b"PAR 2.0\0FileDesc"
SUMS = b"PAR 2.0\0IFSC\0\0\0\0"
PARITY = b"PAR 2.0\0RecvSlic"
CREATOR = b"PAR 2.0\0Creator\0"
RESULTS = []


def call(args, folder, expected=0):
    p = subprocess.run([str(a) for a in args], cwd=folder, capture_output=True, text=True)
    if p.returncode != expected:
        raise AssertionError(f"{args}: exit {p.returncode}, expected {expected}\n{p.stdout}\n{p.stderr}")
    return p.stdout + p.stderr


def packets(raw):
    out = []
    at = 0
    while at < len(raw):
        assert raw[at:at+8] == MAGIC
        size, = struct.unpack_from("<Q", raw, at+8)
        p = raw[at:at+size]
        assert len(p) == size and hashlib.md5(p[32:]).digest() == p[16:32]
        out.append(p)
        at += size
    return out


def packet(setid, tag, body):
    assert len(tag) == 16 and len(body) % 4 == 0
    content = setid + tag + body
    return MAGIC + struct.pack("<Q", 64+len(body)) + hashlib.md5(content).digest() + content


def result(name):
    RESULTS.append({"case": name, "result": "passed"})
    print("PASS:", name, flush=True)


def originals(folder, data):
    for name, b in data.items():
        p = folder / name
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(b)


def check(folder, data, skip_empty=False):
    for name, b in data.items():
        if skip_empty and not b:
            continue
        assert (folder/name).is_file(), name
        assert hashlib.sha256((folder/name).read_bytes()).digest() == hashlib.sha256(b).digest(), name


def damage_sources(folder):
    (folder/"tree/notes/todo.txt").unlink()
    with (folder/"tree/photos/image.bin").open("r+b") as f:
        f.seek(600)
        f.write(b"\xff")


def directory_cases(root, ref, other_writer):
    data = {"tree/photos/image.bin": bytes(range(251))*7,
            "tree/notes/todo.txt": b"save the originals",
            "tree/notes/image.bin": b"same basename, different directory",
            "tree/empty": b""}
    origin = root/"original"
    origin.mkdir()
    originals(origin, data)
    if other_writer:
        call([ref,"c","-q","-t1","-s256","-c8","-n2","-f7","-B"+str(origin),
              "set.par2", *data], origin)
    else:
        call(CLI+["create","--recovery-blocks","8","--slice-size","256","set.par2","tree"], origin)
    blocks = []
    for path in sorted(origin.glob("*.par2")):
        blocks.extend(packets(path.read_bytes()))
    # Independent readers must receive only this damaged volume, never clean siblings.
    cases = {}
    cases["intact"] = b"".join(blocks)
    damaged = list(blocks)
    i = next(i for i,p in enumerate(blocks) if p[48:64] == PARITY)
    damaged[i] = damaged[i][:-1] + bytes([damaged[i][-1]^0xff])
    cases["bad-recovery-checksum"] = b"".join(damaged)
    cases["inserted-byte"] = b"X" + b"!".join(blocks) + b"trailing"
    cases["bad-length"] = MAGIC + b"\xff"*56 + b"".join(blocks)
    cases["truncated-tail"] = b"".join(blocks) + blocks[i][:71]
    damaged = list(blocks)
    m = next(i for i,p in enumerate(blocks) if p[48:64] == MAIN)
    damaged[m] = damaged[m][:-1] + bytes([damaged[m][-1]^0xff])
    cases["bad-main-copy"] = b"".join(damaged)
    cases["unknown-packet"] = packet(blocks[0][32:48], b"Other-client\0\0\0\0", b"abcd") + b"".join(reversed(blocks))
    for name, volume in cases.items():
        for reader in ("moonpar2", "par2cmdline"):
            folder = root/(name+"-"+reader)
            folder.mkdir()
            originals(folder, data)
            damage_sources(folder)
            (folder/"only.par2").write_bytes(volume)
            if reader == "moonpar2":
                text = call(CLI+["repair","out","only.par2"], folder)
                check(folder/"out", data, skip_empty=other_writer)
                if other_writer:
                    assert "tree/empty" not in call(CLI+["inspect","only.par2"],folder)
                assert not (folder/"tree/notes/todo.txt").exists()
                if name not in ("intact","unknown-packet"): assert "warning:" in text
            else:
                call([ref,"r","-q","-t1","only.par2"],folder)
                # par2cmdline 1.4.0 omits empty inputs when creating a set.
                check(folder,data)
        result(("par2cmdline" if other_writer else "moonpar2")+" writer / "+name+" / both readers")
    insufficient = b"".join(p for p in blocks if p[48:64]!=PARITY)
    for name, volume, message in [
        ("no-parity",insufficient,"insufficient independent"),
        ("no-main",b"".join(p for p in blocks if p[48:64]!=MAIN),"missing main"),
    ]:
        folder = root/name
        folder.mkdir()
        originals(folder,data)
        damage_sources(folder)
        (folder/"only.par2").write_bytes(volume)
        assert message in call(CLI+["repair","out","only.par2"],folder,2)
        assert not (folder/"out").exists()
        result(("external" if other_writer else "own")+" "+name+" leaves no output")


def path_cases(root):
    root.mkdir()
    originals(root,{"safe/x":b"abcd","safe/empty":b""})
    for n in range(130):
        originals(root,{f"many/{n//20}/{n}.txt":str(n).encode()})
    call(CLI+["create","--check-only","safe/x","set.par2","many","safe/empty"],root)
    assert "check-only safe/x" in call(CLI+["inspect","set.par2"],root)
    (root/"safe/x").write_bytes(b"bad!")
    assert "[check-only]" in call(CLI+["verify","set.par2"],root,1)
    call(CLI+["repair","out","set.par2"],root)
    assert not (root/"out/safe/x").exists() and (root/"out/safe/empty").read_bytes()==b""
    result("recursive 131 recoverable files, empty file, check-only corruption")
    # Archive paths are rooted at the explicit data directory, not process cwd.
    call(CLI+["verify","--base-dir",str(root/"out"),"set.par2"],root,1) # check-only missing
    for bad in ("../escape", "/absolute", "safe/../x", "safe//x"):
        call(CLI+["create","bad.par2",bad],root,2)
        assert not (root/"bad.par2").exists()
    call(CLI+["repair","out","set.par2"],root,2)
    result("explicit data root, traversal input rejection, existing output preservation")
    # Valid checksums do not make traversal metadata trustworthy.
    raw = (root/"set.par2").read_bytes()
    for name in ("../evil","/abs/x","C:/bad","a/../../bad","a/NUL","a\\x"):
        encoded=name.encode()
        fid=hashlib.md5(hashlib.md5(b"").digest()+struct.pack("<Q",0)+encoded).digest()
        desc=fid+hashlib.md5(b"").digest()*2+struct.pack("<Q",0)+encoded
        desc+=b"\0"*((-len(desc))%4)
        main=struct.pack("<QI",4,1)+fid
        sid=hashlib.md5(main).digest()
        volume=packet(sid,CREATOR,b"Test")+packet(sid,MAIN,main)+packet(sid,DESC,desc)+packet(sid,SUMS,fid)
        (root/"unsafe.par2").write_bytes(volume)
        assert "path" in call(CLI+["repair","unsafe-out","unsafe.par2"],root,2)
        assert not (root/"unsafe-out").exists()
    result("six hostile but checksummed archive paths rejected before output")
    # Use a junction on Windows, a symlink on POSIX.
    link = root/"linked"
    if os.name == "nt":
        call(["powershell","-NoProfile","-Command",
              "New-Item -ItemType Junction -Path '"+str(link)+"' -Target '"+str(root/"safe")+"' | Out-Null"],root)
    else:
        link.symlink_to(root/"safe",target_is_directory=True)
    try:
        assert "link" in call(CLI+["create","link.par2","linked/x"],root,2)
        assert "link" in call(CLI+["repair",str(link/"out"),"set.par2"],root,2)
    finally:
        if os.name=="nt": link.rmdir()
        else: link.unlink()
    result("symlink/junction ancestors rejected for both input and output")


def equivalence(root, ref):
    root.mkdir()
    data = {"tree/a.txt":b"hello"*70,"tree/nested/a.txt":b"small",
            "tree/b.bin":bytes(range(256))*3}
    originals(root,data)
    call(CLI+["create","--slice-size","256","ours.par2","tree"],root)
    call([ref,"c","-q","-t1","-s256","-c4","-n1","-B"+str(root),
          "theirs.par2",*data],root)
    ours={p[32:] for p in packets((root/"ours.par2").read_bytes()) if p[48:64]!=CREATOR}
    theirs={p[32:] for f in root.glob("theirs*.par2") for p in packets(f.read_bytes())
            if p[48:64] in (MAIN,DESC,SUMS,PARITY)}
    assert ours==theirs, "core packet bodies differ from reference implementation"
    result("Main, FileDesc, IFSC and RecvSlic bytes equal par2cmdline")
    call(CLI+["create","--check-only","tree/b.bin","check.par2","tree/a.txt"],root)
    probe = subprocess.run([ref,"v","-q","-t1","--full-hash","check.par2"],
                           cwd=root,capture_output=True,text=True)
    if probe.returncode != 0:
        # Preserve the observed upstream limitation, rather than calling it a pass.
        assert probe.returncode in (3221225477,-11), probe.stdout+probe.stderr
        RESULTS.append({"case":"par2cmdline non-recovery list",
                        "result":"reference limitation","exit":probe.returncode})
        print("LIMITATION: par2cmdline non-recovery-list verification exits",probe.returncode,flush=True)
    else:
        result("par2cmdline verifies non-recovery list")
    (root/"tree/b.bin").write_bytes(b"damaged check-only")
    (root/"tree/a.txt").unlink()
    call(CLI+["repair","out","check.par2"],root)
    assert (root/"out/tree/a.txt").read_bytes()==data["tree/a.txt"]
    assert not (root/"out/tree/b.bin").exists()
    result("check-only damage does not block MoonPar2 recovery")
    # One genuine file reaches the format's maximum count of source slices.
    (root/"limit.bin").write_bytes(hashlib.shake_256(b"32768 slices").digest(131072))
    call(CLI+["create","--slice-size","4","--recovery-blocks","2","limit.par2","limit.bin"],root)
    call([ref,"v","-q","-t1","--full-hash","limit.par2"],root)
    with (root/"limit.bin").open("r+b") as f:
        f.seek(-1,2)
        b=f.read(1)
        f.seek(-1,2)
        f.write(bytes([b[0]^0xff]))
    call(CLI+["repair","limit-out","limit.par2"],root)
    assert (root/"limit-out/limit.bin").read_bytes()==hashlib.shake_256(b"32768 slices").digest(131072)
    (root/"limit.bin").write_bytes(b"x"*131073)
    call(CLI+["create","--slice-size","4","over.par2","limit.bin"],root,2)
    assert not (root/"over.par2").exists()
    result("32768 source-slice boundary and 32769 rejection")


def many_files(root):
    root.mkdir()
    data={f"tree/{n//64}/{n}.txt":str(n).encode() for n in range(4096)}
    originals(root,data)
    call(CLI+["create","set.par2","tree"],root)
    (root/"tree/63/4095.txt").unlink()
    call(CLI+["repair","out","set.par2"],root)
    check(root/"out",data)
    originals(root,{"tree/63/4095.txt":b"4095","tree/extra":b"x"})
    call(CLI+["create","over.par2","tree"],root,2)
    assert not (root/"over.par2").exists()
    result("4096 files across 64 directories restore exactly; 4097 rejected")


if __name__ == "__main__":
    ap=argparse.ArgumentParser()
    ap.add_argument("--par2",required=True)
    ap.add_argument("--report",type=Path)
    args=ap.parse_args()
    with tempfile.TemporaryDirectory(prefix="moonpar2-conformance-") as tmp:
        root=Path(tmp)
        for external in (False, True):
            case=root/str(external)
            case.mkdir()
            directory_cases(case,args.par2,external)
        path_cases(root/"paths")
        equivalence(root/"equivalence",args.par2)
        many_files(root/"many")
    if args.report:
        args.report.parent.mkdir(parents=True,exist_ok=True)
        args.report.write_text(json.dumps({"cases":RESULTS},indent=2)+"\n",encoding="utf-8")
