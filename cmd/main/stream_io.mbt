///|
extern "js" fn disk_size(path : String, accept : (Double) -> Unit) -> String =
  #| (path,accept) => {
  #|   try {
  #|     const s=process.getBuiltinModule('fs').lstatSync(path);
  #|     if(!s.isFile()) return 'expected a regular file: '+path;
  #|     if(!Number.isSafeInteger(s.size)) return 'file size exceeds exact address range';
  #|     accept(s.size); return '';
  #|   } catch(e) {return e.code==='ENOENT'?'':e.message;}
  #| }

///|
fn size_of(path : String) -> UInt64? raise {
  check_io(check_path(path))
  let mut result = None
  check_io(disk_size(path, fn(s) { result = Some(s.to_uint64()) }))
  result
}

///|
extern "js" fn disk_chunk(
  path : String,
  offset : Double,
  length : Int32,
  accept : (Bytes) -> Unit,
) -> String =
  #| (path,offset,length,accept) => {
  #|   const fs=process.getBuiltinModule('fs'); let fd;
  #|   try {
  #|     fd=fs.openSync(path,fs.constants.O_RDONLY|(fs.constants.O_NOFOLLOW||0));
  #|     if(!fs.fstatSync(fd).isFile()) return 'expected a regular source';
  #|     const bytes=Buffer.alloc(length);let at=0;
  #|     while(at<length) {
  #|       const n=fs.readSync(fd,bytes,at,length-at,offset+at);
  #|       if(!n) return 'source shortened during read: '+path;
  #|       at+=n;
  #|     }
  #|     accept(bytes);return '';
  #|   } catch(e){return e.message;}
  #|   finally {if(fd!==undefined)fs.closeSync(fd);}
  #| }

///|
fn chunk(path : String, at : UInt64, length : Int32) -> Bytes raise {
  check_io(check_path(path))
  let mut out = b""
  check_io(disk_chunk(path, at.to_double(), length, fn(b) { out = b }))
  out
}

///|
extern "js" fn start_stage(
  target : String,
  accept : (String) -> Unit,
) -> String =
  #| (target,accept) => {
  #|   const fs=process.getBuiltinModule('fs'),p=process.getBuiltinModule('path');
  #|   try {
  #|     if(fs.existsSync(target))return 'output already exists: '+target;
  #|     accept(fs.mkdtempSync(p.join(p.dirname(p.resolve(target)),'.moonpar2-stage-')));
  #|     return '';
  #|   }catch(e){return e.message;}
  #| }

///|
extern "js" fn put_chunk(
  path : String,
  offset : Double,
  data : Bytes,
) -> String =
  #| (path,offset,data) => {
  #|   const fs=process.getBuiltinModule('fs'),p=process.getBuiltinModule('path');let fd;
  #|   try {
  #|     fs.mkdirSync(p.dirname(path),{recursive:true});
  #|     fd=fs.openSync(path,offset===0?'wx':'r+');
  #|     let at=0;
  #|     while(at<data.length){
  #|       const n=fs.writeSync(fd,data,at,data.length-at,offset+at);
  #|       if(!n)return 'no progress writing staged file';
  #|       at+=n;
  #|     }
  #|     return '';
  #|   }catch(e){return e.message;}finally{if(fd!==undefined)fs.closeSync(fd);}
  #| }

///|
extern "js" fn finish_stage(
  stage : String,
  target : String,
  names : FixedArray[String],
) -> String =
  #| (stage,target,names) => {
  #|   const fs=process.getBuiltinModule('fs'),p=process.getBuiltinModule('path');
  #|   try {
  #|     fs.mkdirSync(target);
  #|     for(const name of names){
  #|       const to=p.join(target,name);
  #|       fs.mkdirSync(p.dirname(to),{recursive:true});
  #|       fs.copyFileSync(p.join(stage,name),to,fs.constants.COPYFILE_EXCL);
  #|     }
  #|     return '';
  #|   }catch(e){return e.message;}
  #| }

///|
extern "js" fn discard_stage(stage : String) -> Unit =
  #| stage => {process.getBuiltinModule('fs').rmSync(stage,{recursive:true,force:true});}

///|
fn repair_disk(
  set : @par.RecoverySet,
  base : String,
  target : String,
) -> Unit raise {
  check_io(check_path(target))
  let mut stage = ""
  check_io(start_stage(target, fn(s) { stage = s }))
  errdefer discard_stage(stage)
  {
    set.repair_stream(
      name => size_of(base + "/" + name),
      (name, at, n) => chunk(base + "/" + name, at, n),
      (name, at, b) => {
        check_io(check_path(stage + "/" + name))
        check_io(put_chunk(stage + "/" + name, at.to_double(), b))
      },
    )
    check_io(check_path(target))
    let names = set
      .files()
      .filter(fn(f) { f.recoverable })
      .map(fn(f) { f.name })
    check_io(
      finish_stage(
        stage,
        target,
        FixedArray::makei(names.length(), fn(i) { names[i] }),
      ),
    )
  }
  discard_stage(stage)
}
