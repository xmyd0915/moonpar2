///|
/// Reject symlinks/junctions in every existing path component, not only the leaf.
extern "js" fn check_path(path : String) -> String =
  #| path => {
  #|   const fs=process.getBuiltinModule('fs'), p=process.getBuiltinModule('path');
  #|   try {
  #|     const absolute=p.resolve(path), root=p.parse(absolute).root;
  #|     let current=root;
  #|     for(const part of absolute.slice(root.length).split(p.sep).filter(Boolean)){
  #|       current=p.join(current,part);
  #|       try { if(fs.lstatSync(current).isSymbolicLink()) return 'symbolic link or junction refused: '+current; }
  #|       catch(e){ if(e.code==='ENOENT') break; throw e; }
  #|     }
  #|     return '';
  #|   } catch(e){ return e.message; }
  #| }

///|
extern "js" fn walk_files(
  root : String,
  name : String,
  accept : (String) -> Unit,
) -> String =
  #| (root,name,accept) => {
  #|   const fs=process.getBuiltinModule('fs'), p=process.getBuiltinModule('path');
  #|   let count=0;
  #|   try {
  #|     function visit(rel,depth){
  #|       if(depth>64) throw Error('directory depth exceeds 64');
  #|       const path=p.join(root,rel), st=fs.lstatSync(path);
  #|       if(st.isSymbolicLink()) throw Error('symbolic link or junction refused: '+rel);
  #|       if(st.isDirectory()){
  #|         for(const child of fs.readdirSync(path).sort()) visit(rel+'/'+child,depth+1);
  #|       } else if(st.isFile()){
  #|         if(++count>4096) throw Error('more than 4096 files');
  #|         accept(rel);
  #|       } else throw Error('expected a regular file: '+rel);
  #|     }
  #|     visit(name,0); return '';
  #|   } catch(e){return e.message;}
  #| }

///|
fn collect(root : String, name : String) -> Array[String] raise {
  if !@par.safe_path(name) {
    fail("expected a safe relative input path: " + name)
  }
  check_io(check_path(root + "/" + name))
  let names = []
  check_io(walk_files(root, name, fn(s) { names.push(s) }))
  for path in names {
    if !@par.safe_path(path) {
      fail("unsupported input path: " + path)
    }
  }
  names
}
