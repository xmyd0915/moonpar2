///|
extern "js" fn read_bounded(
  path : String,
  limit : Int32,
  accept : (Bytes) -> Unit,
) -> String =
  #| (path, limit, accept) => {
  #|   const fs = process.getBuiltinModule('fs');
  #|   let fd;
  #|   try {
  #|     const entry = fs.lstatSync(path);
  #|     if (!entry.isFile()) return 'expected a regular file: ' + path;
  #|     fd = fs.openSync(path, fs.constants.O_RDONLY | (fs.constants.O_NOFOLLOW || 0));
  #|     const stat = fs.fstatSync(fd);
  #|     if (!stat.isFile() || stat.size > limit) return 'input too large or not a file: ' + path;
  #|     const bytes = Buffer.alloc(stat.size);
  #|     let offset = 0;
  #|     while (offset < bytes.length) {
  #|       const n = fs.readSync(fd, bytes, offset, bytes.length-offset, null);
  #|       if (!n) return 'file changed while reading: ' + path;
  #|       offset += n;
  #|     }
  #|     if (fs.fstatSync(fd).size !== bytes.length) return 'file changed while reading: ' + path;
  #|     accept(bytes);
  #|     return '';
  #|   } catch (e) { return e.code === 'ENOENT' && fd === undefined ? '' : e.message; }
  #|   finally { if (fd !== undefined) fs.closeSync(fd); }
  #| }

///|
extern "js" fn write_new(path : String, bytes : Bytes) -> String =
  #| (path, bytes) => {
  #|   const fs = process.getBuiltinModule('fs'), p = process.getBuiltinModule('path');
  #|   let stage;
  #|   try {
  #|     stage = fs.mkdtempSync(p.join(p.dirname(path), '.moonpar2-'));
  #|     const tmp = p.join(stage, 'data');
  #|     fs.writeFileSync(tmp, bytes, {flag:'wx'});
  #|     try {
  #|       fs.linkSync(tmp, path);
  #|     } catch (error) {
  #|       if (!['EPERM','ENOTSUP','EOPNOTSUPP','ENOSYS'].includes(error.code)) throw error;
  #|       fs.copyFileSync(tmp, path, fs.constants.COPYFILE_EXCL);
  #|     }
  #|     return '';
  #|   } catch(e) { return e.message; }
  #|   finally { if (stage) fs.rmSync(stage, {recursive:true,force:true}); }
  #| }

///|
extern "js" fn new_dir(path : String) -> String =
  #| path => {try {process.getBuiltinModule('fs').mkdirSync(path); return ''} catch(e){return e.message}}

///|
extern "js" fn parent(path : String) -> String =
  #| path => process.getBuiltinModule('path').dirname(path)

///|
extern "js" fn exit_code(n : Int32) -> Unit =
  #| n => {process.exitCode = n}

///|
fn read(path : String, limit : Int32) -> Bytes? raise {
  let mut result = None
  let err = read_bounded(path, limit, fn(b) { result = Some(b) })
  if !err.is_empty() {
    fail(err)
  }
  result
}

///|
fn check_io(message : String) -> Unit raise {
  if !message.is_empty() {
    fail(message)
  }
}
