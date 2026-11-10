///|
/// Keep index names distinct from standard recovery-volume names.
extern "js" fn valid_index_name(name : String) -> Bool =
  #| name => /^.+\.par2$/i.test(name) && !/\.vol[0-9]+\+[0-9]+\.par2$/i.test(name)

///|
extern "js" fn find_volume_files(
  inputs : FixedArray[String],
  enabled : Bool,
  accept : (String) -> Unit,
) -> String =
  #| (inputs,enabled,accept) => {
  #|   const fs=process.getBuiltinModule('fs'), p=process.getBuiltinModule('path');
  #|   const fold=s=>process.platform==='win32'?s.toLowerCase():s;
  #|   const seen=new Set(), output=[], candidates=[];
  #|   const key=s=>fold(p.resolve(s));
  #|   function add(path){
  #|     const id=key(path);
  #|     if(seen.has(id))return;
  #|     if(output.length===256)throw Error('more than 256 recovery volumes');
  #|     seen.add(id);output.push(path);
  #|   }
  #|   try {
  #|     for(const input of inputs)add(input);
  #|     if(enabled){
  #|       const searched=new Set();
  #|       for(const input of inputs){
  #|         const name=p.basename(input),dir=p.dirname(input);
  #|         const volume=/^(.*)\.vol[0-9]+\+[0-9]+\.par2$/i.exec(name);
  #|         const index=/^(.*)\.par2$/i.exec(name);
  #|         if(!index)continue;
  #|         const stem=volume?volume[1]:index[1],family=key(p.join(dir,stem));
  #|         if(searched.has(family))continue;
  #|         searched.add(family);
  #|         for(const child of fs.readdirSync(dir).sort()){
  #|           const match=/^(.*)\.vol[0-9]+\+[0-9]+\.par2$/i.exec(child);
  #|           const head=/^(.*)\.par2$/i.exec(child);
  #|           if(!(match&&fold(match[1])===fold(stem))&&
  #|              !(head&&fold(head[1])===fold(stem)))continue;
  #|           const path=p.join(dir,child),st=fs.lstatSync(path);
  #|           if(st.isSymbolicLink()||!st.isFile())throw Error('expected a regular recovery volume: '+path);
  #|           candidates.push(path);
  #|         }
  #|       }
  #|       candidates.sort((a,b)=>key(a)<key(b)?-1:key(a)>key(b)?1:0);
  #|       for(const path of candidates)add(path);
  #|     }
  #|     for(const path of output)accept(path);
  #|     return '';
  #|   }catch(e){return e.message;}
  #| }

///|
fn discover_volumes(
  inputs : Array[String],
  enabled : Bool,
) -> Array[String] raise {
  for path in inputs {
    check_io(check_path(path))
  }
  let found = []
  check_io(
    find_volume_files(
      FixedArray::makei(inputs.length(), fn(i) { inputs[i] }),
      enabled,
      fn(path) { found.push(path) },
    ),
  )
  found
}

///|
extern "js" fn publish_volume_files(
  paths : FixedArray[String],
  data : FixedArray[Bytes],
) -> String =
  #| (paths,data) => {
  #|   const fs=process.getBuiltinModule('fs'),p=process.getBuiltinModule('path');
  #|   const directories=new Map(),staged=[],published=[];
  #|   const key=s=>{const absolute=p.resolve(s);return process.platform==='win32'?absolute.toLowerCase():absolute;};
  #|   const same=(a,b)=>a.dev===b.dev&&a.ino===b.ino;
  #|   let failure='';
  #|   try {
  #|     const unique=new Set();
  #|     for(const path of paths){
  #|       if(unique.has(key(path)))throw Error('duplicate output volume: '+path);
  #|       unique.add(key(path));
  #|       try {fs.lstatSync(path);throw Error('output already exists: '+path);}
  #|       catch(e){if(e.code!=='ENOENT')throw e;}
  #|     }
  #|     for(let i=0;i<paths.length;i++){
  #|       const dir=p.dirname(p.resolve(paths[i])),id=key(dir);
  #|       if(!directories.has(id))directories.set(id,fs.mkdtempSync(p.join(dir,'.moonpar2-volumes-')));
  #|       const tmp=p.join(directories.get(id),String(i));
  #|       fs.writeFileSync(tmp,data[i],{flag:'wx'});
  #|       staged.push(tmp);
  #|     }
  #|     for(let i=0;i<paths.length;i++){
  #|       const stat=fs.lstatSync(staged[i],{bigint:true});
  #|       try {
  #|         fs.linkSync(staged[i],paths[i]);
  #|         published.push({path:paths[i],stat});
  #|       }
  #|       catch(e){
  #|         if(!['EPERM','ENOTSUP','EOPNOTSUPP','ENOSYS'].includes(e.code))throw e;
  #|         const fd=fs.openSync(paths[i],'wx');
  #|         try {
  #|           published.push({path:paths[i],stat:fs.fstatSync(fd,{bigint:true})});
  #|           fs.writeFileSync(fd,data[i]);
  #|         }finally{fs.closeSync(fd);}
  #|       }
  #|     }
  #|   }catch(e){
  #|     failure=e.message;
  #|     for(const item of published.reverse()){
  #|       try {
  #|         const current=fs.lstatSync(item.path,{bigint:true});
  #|         if(same(current,item.stat))fs.unlinkSync(item.path);
  #|       }catch(cleanup){if(cleanup.code!=='ENOENT')failure+='; rollback: '+cleanup.message;}
  #|     }
  #|   }finally{
  #|     for(const stage of directories.values()){
  #|       try {fs.rmSync(stage,{recursive:true,force:true});}
  #|       catch(e){failure+='; staging cleanup: '+e.message;}
  #|     }
  #|   }
  #|   return failure;
  #| }

///|
fn write_volume_set(paths : Array[String], data : Array[Bytes]) -> Unit raise {
  if paths.is_empty() || paths.length() != data.length() {
    fail("volume paths and contents must have equal nonzero lengths")
  }
  for path in paths {
    check_io(check_path(path))
  }
  check_io(
    publish_volume_files(
      FixedArray::makei(paths.length(), fn(i) { paths[i] }),
      FixedArray::makei(data.length(), fn(i) { data[i] }),
    ),
  )
}
