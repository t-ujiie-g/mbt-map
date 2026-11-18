///|
/// The host's `Math`, `Number`, `String` and `Intl`, as the display worker's.
let hooks : @tableops.Hooks = {
  trig: @wasmio.host_trig(),
  number_text: @wasmio.host_number_to_text,
  text_number: @wasmio.host_text_to_number,
  intl: {
    number_format: @wasmio.host_number_format,
    collate: @wasmio.host_collate,
    resolved_locale: @wasmio.host_resolved_locale,
  },
}

///|
/// How deep packed JSON may nest.
const MAX_JSON_DEPTH : Int32 = 64

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
/// Packed JSON (docs/dev/FORMATS.md "Table operations"): None if malformed or nested past
/// `MAX_JSON_DEPTH`.
fn read_json(r : @core.ByteReader, depth : Int32) -> Json? {
  guard depth < MAX_JSON_DEPTH else { return None }
  let tag = r.u8()
  guard r.ok() else { return None }
  match tag {
    0 => Some(Json::null())
    1 => Some(Json::boolean(false))
    2 => Some(Json::boolean(true))
    3 => Some(Json::number(r.f64()))
    4 => Some(Json::string(r.utf8()))
    5 => {
      let n = r.u32()
      guard n >= 0 && n <= r.remaining() else { return None }
      let items = []
      for _ in 0..<n {
        guard read_json(r, depth + 1) is Some(j) else { return None }
        items.push(j)
      }
      Some(Json::array(items))
    }
    6 => {
      let n = r.u32()
      guard n >= 0 && n <= r.remaining() else { return None }
      let map : Map[String, Json] = Map([])
      for _ in 0..<n {
        let key = r.utf8()
        guard read_json(r, depth + 1) is Some(j) else { return None }
        map[key] = j
      }
      Some(Json::object(map))
    }
    _ => None
  }
}

///|
/// The expression packed next in `r`, compiled; its error as the message.
fn read_expression(r : @core.ByteReader) -> Result[@style.Expr, String] {
  guard read_json(r, 0) is Some(json) && r.ok() else {
    return Err("malformed expression")
  }
  let e = @style.compile(json) catch { err => return Err(err.message()) }
  Ok(e)
}

///|
/// Runs `f` on the input's table (its first `len_table` bytes) and a reader of the rest, and
/// writes the table it gives at `output_addr`: its length, or minus an error message's.
fn run(
  len_table : Int32,
  f : (@geom.Table, @core.ByteReader) -> Result[@geom.Table, String],
) -> Int32 {
  let rest = @wasmio.input_length() - len_table
  guard @wasmio.input_table(0, len_table) is Some(t) else {
    return @wasmio.fail_with("malformed table")
  }
  let args = @wasmio.input_slice(len_table, rest)
  @wasmio.clear_input()
  match f(t, @core.ByteReader::new(args[:])) {
    Ok(out) => @wasmio.write_table(out)
    Err(message) => @wasmio.fail_with(message)
  }
}

///|
/// `@tableops.select`: the arguments are a u32 count and that many names.
#export_name("select")
pub fn select(len_table : Int32) -> Int32 {
  run(len_table, (t, r) => {
    let n = r.u32()
    guard n >= 0 && n <= r.remaining() else { return Err("malformed names") }
    let names = Array::makei(n, _ => r.utf8())
    guard r.ok() else { return Err("malformed names") }
    @tableops.select(t, names)
  })
}

///|
/// `@tableops.filter`: the argument is a packed expression.
#export_name("filter")
pub fn filter(len_table : Int32) -> Int32 {
  run(len_table, (t, r) => {
    read_expression(r).map(e => @tableops.filter(t, e, hooks~))
  })
}

///|
/// `@geom.Table::take`: the arguments are the rows as u32s.
#export_name("take")
pub fn take(len_table : Int32) -> Int32 {
  run(len_table, (t, r) => {
    let rows = Array::makei(r.remaining() / 4, _ => r.u32())
    match t.take(rows) {
      Some(out) => Ok(out)
      None => Err("a row out of the table")
    }
  })
}

///|
/// `@tableops.slice` of the input table.
#export_name("slice")
pub fn slice(len_table : Int32, start : Int32, end : Int32) -> Int32 {
  run(len_table, (t, _) => Ok(@tableops.slice(t, start, end)))
}

///|
/// `@tableops.derive_columns`: the arguments are a u32 count and per column its name, then
/// 0 and a packed expression, or 1, a u32 count and that many property values.
#export_name("derive")
pub fn derive_columns(len_table : Int32) -> Int32 {
  run(len_table, (t, r) => {
    let n = r.u32()
    guard n >= 0 && n <= r.remaining() else { return Err("malformed columns") }
    let columns = []
    for _ in 0..<n {
      let name = r.utf8()
      let how : @tableops.Derived = if r.u8() == 0 {
        match read_expression(r) {
          Ok(e) => Computed(e)
          Err(message) => return Err("\{name}: \{message}")
        }
      } else {
        let cells = r.u32()
        guard cells >= 0 && cells <= r.remaining() else {
          return Err("malformed columns")
        }
        Given(Array::makei(cells, _ => @geom.read_prop(r)))
      }
      guard r.ok() else { return Err("malformed columns") }
      columns.push((name, how))
    }
    @tableops.derive_columns(t, columns, hooks~)
  })
}

///|
/// `@tableops.orderby`: the arguments are a u32 count and per key 1 if it descends (else 0)
/// and a packed expression.
#export_name("orderby")
pub fn orderby(len_table : Int32) -> Int32 {
  run(len_table, (t, r) => {
    let n = r.u32()
    guard n >= 0 && n <= r.remaining() else { return Err("malformed keys") }
    let keys = []
    for _ in 0..<n {
      let descending = r.u8() == 1
      match read_expression(r) {
        Ok(e) => keys.push((e, descending))
        Err(message) => return Err(message)
      }
    }
    Ok(@tableops.orderby(t, keys, hooks~))
  })
}

///|
/// The property values of the column named by the rest of the input (UTF-8), one per row, at
/// `output_addr`: their length, or minus an error message's.
#export_name("column")
pub fn column(len_table : Int32) -> Int32 {
  let rest = @wasmio.input_length() - len_table
  guard @wasmio.input_table(0, len_table) is Some(t) else {
    return @wasmio.fail_with("malformed table")
  }
  let name = @core.utf8_lossy(@wasmio.input_slice(len_table, rest)[:])
  @wasmio.clear_input()
  guard t.column(name) is Some(c) else {
    return @wasmio.fail_with("no column \{name}")
  }
  let w = @core.ByteWriter::new()
  for v in c.values {
    @geom.write_prop(w, v)
  }
  @wasmio.write_bytes(w.to_bytes()[:])
}

///|
/// `@tableops.column_kinds` of the input table as i32s at `output_addr`: their count, or minus
/// an error message's length.
#export_name("kinds")
pub fn kinds() -> Int32 {
  guard @wasmio.input_table(0, @wasmio.input_length()) is Some(t) else {
    return @wasmio.fail_with("malformed table")
  }
  @wasmio.clear_input()
  @wasmio.write_i32s(@tableops.column_kinds(t)[:])
}

///|
/// A value an operation takes of each row: a string names a column of `t` (which must have it,
/// unless it has no row), anything else is an expression.
fn value_of(json : Json, t : @geom.Table) -> Result[@style.Expr, String] {
  let json = match json {
    String(name) => {
      guard t.length() == 0 || t.column(name) is Some(_) else {
        return Err("no column \{name}")
      }
      Json::array([Json::string("get"), json])
    }
    _ => json
  }
  let e = @style.compile(json) catch { err => return Err(err.message()) }
  Ok(e)
}

///|
/// A u32 count and per item its name, what `extra` reads after it, and a value of `t` (packed
/// JSON as `value_of` takes it).
fn[T] read_values(
  r : @core.ByteReader,
  t : @geom.Table,
  extra : () -> T,
) -> Result[Array[(String, T, @style.Expr)], String] {
  let n = r.u32()
  guard n >= 0 && n <= r.remaining() else { return Err("malformed values") }
  let out = []
  for _ in 0..<n {
    let name = r.utf8()
    let more = extra()
    guard read_json(r, 0) is Some(json) && r.ok() else {
      return Err("malformed values")
    }
    match value_of(json, t) {
      Ok(e) => out.push((name, more, e))
      Err(message) => return Err("\{name}: \{message}")
    }
  }
  Ok(out)
}

///|
/// Outputs as `rollup` and `pairs` take them: `read_values` with, per output, its aggregate
/// (the place in `@tableops.Aggregate`) and an f64 fraction (`quantile`'s).
fn read_outputs(
  r : @core.ByteReader,
  t : @geom.Table,
) -> Result[Array[(String, @tableops.Aggregate, @style.Expr)], String] {
  read_values(r, t, () => @tableops.Aggregate::coded(r.u8(), r.f64()))
}

///|
/// `@tableops.rollup`: the arguments are the keys (`read_values`), then the outputs
/// (`read_outputs`).
#export_name("rollup")
pub fn rollup(len_table : Int32) -> Int32 {
  run(len_table, (t, r) => {
    let keys = match read_values(r, t, () => ()) {
      Ok(keys) => keys.map(k => (k.0, k.2))
      Err(message) => return Err(message)
    }
    read_outputs(r, t).map(outputs => @tableops.rollup(t, keys, outputs, hooks~))
  })
}

///|
/// The input's two tables (`len_left` bytes, then `len_right`) and a reader of the rest.
fn two_tables(
  len_left : Int32,
  len_right : Int32,
) -> (@geom.Table, @geom.Table, @core.ByteReader)? {
  let rest = @wasmio.input_length() - len_left - len_right
  guard @wasmio.input_table(0, len_left) is Some(left) &&
    @wasmio.input_table(len_left, len_right) is Some(right) else {
    return None
  }
  let args = @wasmio.input_slice(len_left + len_right, rest)
  @wasmio.clear_input()
  Some((left, right, @core.ByteReader::new(args[:])))
}

///|
/// Writes the table at `output_addr`: its length, or minus the error message's.
fn finish(result : Result[@geom.Table, String]) -> Int32 {
  match result {
    Ok(out) => @wasmio.write_table(out)
    Err(message) => @wasmio.fail_with(message)
  }
}

///|
/// `@tableops.join` of the input's two tables with the arguments after them (docs/dev/FORMATS.md
/// "Table operations").
#export_name("join")
pub fn join(len_left : Int32, len_right : Int32) -> Int32 {
  guard two_tables(len_left, len_right) is Some((left, right, r)) else {
    return @wasmio.fail_with("malformed table")
  }
  let keep_left = r.u8() == 1
  let suffix = (r.utf8(), r.utf8())
  let n = r.u32()
  guard n >= 0 && n <= r.remaining() else {
    return @wasmio.fail_with("malformed join")
  }
  let on = Array::makei(n, _ => (r.utf8(), r.utf8()))
  guard r.ok() else { return @wasmio.fail_with("malformed join") }
  finish(@tableops.join(left, right, on, keep_left~, suffix~))
}

///|
/// `@tableops.join_pairs` (or, with outputs, `@tableops.rollup_pairs`) of the input's two tables
/// with the arguments after them (docs/dev/FORMATS.md "Table operations").
#export_name("pairs")
pub fn pairs(len_left : Int32, len_right : Int32) -> Int32 {
  guard two_tables(len_left, len_right) is Some((left, right, r)) else {
    return @wasmio.fail_with("malformed table")
  }
  let mode = r.u8()
  let suffix = (r.utf8(), r.utf8())
  let n = r.u32()
  guard n >= 0 && n <= r.remaining() / 4 else {
    return @wasmio.fail_with("malformed pairs")
  }
  let rows = Array::makei(n, _ => r.u32())
  guard r.ok() else { return @wasmio.fail_with("malformed pairs") }
  if mode != 2 {
    return finish(
      @tableops.join_pairs(left, right, rows, keep_left=mode == 1, suffix~),
    )
  }
  finish(
    read_outputs(r, right).bind(outputs => {
      @tableops.rollup_pairs(left, right, rows, outputs, hooks~)
    }),
  )
}
