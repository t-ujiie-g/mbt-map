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
/// Reads the Arrow IPC stream or file placed as input into `@geom.Table::to_bytes` form at
/// `output_addr`: its length, or minus the length of the UTF-8 error message written instead.
#export_name("read")
pub fn read() -> Int32 {
  let (table, info) = @formats.read_arrow(@wasmio.input_bytes()[:]) catch {
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
