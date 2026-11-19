///|
/// Makes room for `len` input bytes and returns where JS should write them,
/// or -1 if `len` is too large.
#export_name("prepare_input")
pub fn prepare_input(len : Int32) -> Int32 {
  @wasmio.prepare_input(len, @wasmio.MAX_INPUT_BYTES)
}

///|
/// Where the last call's output starts.
#export_name("output_addr")
pub fn output_addr() -> Int32 {
  @wasmio.output_addr()
}

///|
/// The file `open` opened, until the next.
let file : Ref[@formats.ParquetFile?] = Ref(None)

///|
/// Opens the Parquet footer placed as input (the FileMetaData before a file's last 8 bytes) for
/// the calls after it: 0, or minus the length of the UTF-8 error message at `output_addr`.
#export_name("open")
pub fn open() -> Int32 {
  file.val = None
  let opened = @formats.parquet_open(@wasmio.input_bytes()[:]) catch {
    e => return @wasmio.fail_with(e.message())
  }
  @wasmio.clear_input()
  file.val = Some(opened)
  0
}

///|
/// The opened file's geometry column's name, an empty string and its `geo` metadata at
/// `output_addr`, each a u32 length and UTF-8; returns their length.
#export_name("info_out")
pub fn info_out() -> Int32 {
  let w = @core.ByteWriter::new()
  if file.val is Some(f) {
    let info = f.info()
    w.utf8(info.geometry)
    w.utf8(info.extension)
    w.utf8(info.geo)
  }
  @wasmio.write_bytes(w.to_bytes()[:])
}

///|
/// `@formats.ParquetFile::plan` of the opened file with the arguments placed as input
/// (docs/dev/FORMATS.md "Parquet"): the byte ranges to read as f64 pairs (a position and a
/// length) at `output_addr`, their count times two, or minus an error message's length.
#export_name("plan")
pub fn plan() -> Int32 {
  guard file.val is Some(f) else { return @wasmio.fail_with("no file is open") }
  let r = @core.ByteReader::new(@wasmio.input_bytes()[:])
  let boxed = r.u8() == 1
  let box = (r.f64(), r.f64(), r.f64(), r.f64())
  let bbox = if boxed { Some(box) } else { None }
  let names = (r : @core.ByteReader) => {
    let n = r.u32()
    guard n >= 0 && n <= r.remaining() else {
      r.fail()
      return []
    }
    Array::makei(n, _ => r.utf8())
  }
  let columns = if r.u8() == 1 { Some(names(r)) } else { None }
  let covering = names(r)
  guard r.ok() else { return @wasmio.fail_with("malformed arguments") }
  @wasmio.clear_input()
  let ranges = f.plan(bbox?, columns?=columns.map(c => c[:]), covering~) catch {
    e => return @wasmio.fail_with(e.message())
  }
  @wasmio.write_f64s(
    FixedArray::makei(ranges.length() * 2, i => {
      let range = ranges[i / 2]
      (if i % 2 == 0 { range.0 } else { range.1 }).to_double()
    }),
  )
}

///|
/// The parts of the file in the input's first `len` bytes: a u32 count, then per part its
/// position in the file (an f64) and its length (a u32), then the parts' bytes one after
/// another. None if malformed.
fn parts(input : Bytes, len : Int32) -> Array[(Int64, Int32, BytesView)]? {
  guard len >= 4 && len <= input.length() else { return None }
  let r = @core.ByteReader::new(input[:len])
  let n = r.u32()
  guard n >= 0 && n <= r.remaining() / 12 else { return None }
  let mut base = 4 + n * 12
  let out = []
  for _ in 0..<n {
    let offset = r.f64()
    let length = r.u32()
    guard offset >= 0.0 &&
      offset < 9.0e15 &&
      length >= 0 &&
      length <= len - base else {
      return None
    }
    out.push((offset.to_int64(), base, input[base:base + length]))
    base += length
  }
  Some(out)
}

///|
/// What of the file's parts placed as input (`parts`) `read` needs inflated
/// (`@formats.ParquetFile::packed_pages`), as i32s at `output_addr`: their count, or minus an
/// error message's length. The input stays.
#export_name("pages")
pub fn pages() -> Int32 {
  let input = @wasmio.input_bytes()
  guard file.val is Some(f) && parts(input, input.length()) is Some(parts) else {
    return @wasmio.fail_with("malformed input")
  }
  let pages = f.packed_pages(parts) catch {
    e => return @wasmio.fail_with(e.message())
  }
  @wasmio.write_i32s(pages[:])
}

///|
/// Reads the rows `plan` chose from the file's parts in the input's first `len_parts` bytes, the
/// inflated pages after them (a u32 length and the bytes each, in `pages`' order): Table bytes
/// at `output_addr`, their length, or minus an error message's.
#export_name("read")
pub fn read(len_parts : Int32) -> Int32 {
  let input = @wasmio.input_bytes()
  guard file.val is Some(f) && parts(input, len_parts) is Some(parts) else {
    return @wasmio.fail_with("malformed input")
  }
  let inflated = []
  let mut at = len_parts
  while at < input.length() {
    guard at <= input.length() - 4 else {
      return @wasmio.fail_with("malformed input")
    }
    let n = @core.ByteReader::new(input[at:at + 4]).u32()
    guard n >= 0 && n <= input.length() - at - 4 else {
      return @wasmio.fail_with("malformed input")
    }
    inflated.push(input[at + 4:at + 4 + n])
    at += 4 + n
  }
  let table = f.read(parts, inflated~) catch {
    e => return @wasmio.fail_with(e.message())
  }
  @wasmio.clear_input()
  @wasmio.write_table(table)
}
