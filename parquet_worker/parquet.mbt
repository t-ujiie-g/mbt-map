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
/// What the last read told of its geometry column (`@formats.ArrowInfo`).
let last_info : Ref[@formats.ArrowInfo] = Ref({
  geometry: "",
  extension: "",
  geo: "",
})

///|
/// What of the Parquet file placed as input `read` needs inflated (`@formats.parquet_packed_pages`),
/// as i32s at `output_addr`: their count, or minus an error message's length. The input stays.
#export_name("pages")
pub fn pages() -> Int32 {
  let pages = @formats.parquet_packed_pages(@wasmio.input_bytes()[:]) catch {
    e => return @wasmio.fail_with(e.message())
  }
  @wasmio.write_i32s(pages[:])
}

///|
/// Reads the Parquet file in the input's first `len_file` bytes, the inflated pages after it (a
/// u32 length and the bytes each, in `pages`' order) into `@geom.Table::to_bytes` form at
/// `output_addr`: its length, or minus the length of the UTF-8 error message written instead.
#export_name("read")
pub fn read(len_file : Int32) -> Int32 {
  let input = @wasmio.input_bytes()
  guard len_file >= 0 && len_file <= input.length() else {
    return @wasmio.fail_with("malformed input")
  }
  let inflated = []
  let mut at = len_file
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
  let (table, info) = @formats.read_parquet(input[:len_file], inflated~) catch {
    e => return @wasmio.fail_with(e.message())
  }
  last_info.val = info
  @wasmio.clear_input()
  @wasmio.write_table(table)
}

///|
/// The last read's geometry column's name, its extension metadata and the schema's `geo`
/// metadata at `output_addr`, each a u32 length and UTF-8; returns their length.
#export_name("info_out")
pub fn info_out() -> Int32 {
  let w = @core.ByteWriter::new()
  w.utf8(last_info.val.geometry)
  w.utf8(last_info.val.extension)
  w.utf8(last_info.val.geo)
  @wasmio.write_bytes(w.to_bytes()[:])
}
