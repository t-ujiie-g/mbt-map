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
/// What of the Arrow data placed as input `read` needs inflated (`@formats.arrow_packed_buffers`),
/// as i32s at `output_addr`: their count, or minus an error message's length. The input stays.
#export_name("pages")
pub fn pages() -> Int32 {
  let pages = @formats.arrow_packed_buffers(@wasmio.input_bytes()[:]) catch {
    e => return @wasmio.fail_with(e.message())
  }
  @wasmio.write_i32s(pages[:])
}

///|
/// Reads the Arrow IPC stream or file in the input's first `len_file` bytes, the buffers the
/// host inflated after it (a u32 length and the bytes each, in `pages`' order), into
/// `@geom.Table::to_bytes` form at `output_addr`: its length, or minus an error message's.
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
  let (table, info) = @formats.read_arrow(input[:len_file], inflated~) catch {
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

///|
/// Writes the input table as Arrow IPC (`@formats.write_arrow`; bit 0 of `flags` for GeoArrow's
/// native types, bit 1 for the file format) at `output_addr`: its length, or minus an error
/// message's.
#export_name("write")
pub fn write(flags : Int32) -> Int32 {
  guard @wasmio.input_table(0, @wasmio.input_length()) is Some(t) else {
    return @wasmio.fail_with("malformed table")
  }
  @wasmio.clear_input()
  let written = @formats.write_arrow(
    t,
    native=(flags & 1) != 0,
    file=(flags & 2) != 0,
    number_text=@wasmio.host_number_to_text,
  )
  match written {
    Ok(bytes) => @wasmio.write_bytes(bytes[:])
    Err(message) => @wasmio.fail_with(message)
  }
}
