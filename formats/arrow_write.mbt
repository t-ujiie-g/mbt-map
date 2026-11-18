///|
/// Bytes written little-endian one after another, some patched afterwards.
priv struct Out {
  mut bytes : FixedArray[Byte]
  mut len : Int32
}

///|
fn Out::new() -> Out {
  { bytes: FixedArray::make(1024, b'\x00'), len: 0, }
}

///|
fn Out::room(self : Out, n : Int32) -> Unit {
  if self.len + n > self.bytes.length() {
    let grown = FixedArray::make(
      (self.bytes.length() * 2).max(self.len + n),
      b'\x00',
    )
    self.bytes.blit_to(grown, len=self.len)
    self.bytes = grown
  }
}

///|
fn Out::u8(self : Out, v : Int32) -> Unit {
  self.room(1)
  self.bytes[self.len] = v.to_byte()
  self.len += 1
}

///|
fn Out::u16(self : Out, v : Int32) -> Unit {
  self.u8(v)
  self.u8(v >> 8)
}

///|
fn Out::i32(self : Out, v : Int32) -> Unit {
  self.room(4)
  for k in 0..<4 {
    self.bytes[self.len + k] = (v >> (k * 8)).to_byte()
  }
  self.len += 4
}

///|
fn Out::i64(self : Out, v : Int64) -> Unit {
  self.i32(v.to_int())
  self.i32((v >> 32).to_int())
}

///|
fn Out::f64(self : Out, v : Double) -> Unit {
  self.i64(v.reinterpret_as_int64())
}

///|
/// Sets the i32 at `at`.
fn Out::patch(self : Out, at : Int32, v : Int32) -> Unit {
  for k in 0..<4 {
    self.bytes[at + k] = (v >> (k * 8)).to_byte()
  }
}

///|
/// Zeros until the length is `rest` past a multiple of `align`.
fn Out::pad(self : Out, align : Int32, rest~ : Int32 = 0) -> Unit {
  while self.len % align != rest {
    self.u8(0)
  }
}

///|
fn Out::append(self : Out, other : Out) -> Unit {
  self.room(other.len)
  other.bytes.blit_to(self.bytes, len=other.len, dst_offset=self.len)
  self.len += other.len
}

///|
fn Out::text(self : Out, s : String) -> Unit {
  let b = @utf8.encode(s)
  self.room(b.length())
  for i, byte in b {
    self.bytes[self.len + i] = byte
  }
  self.len += b.length()
}

///|
/// A value of a FlatBuffers table, by its place among the table's fields: not stored, a scalar
/// of 1, 2, 4 or 8 bytes, or an offset to what `Node` writes after the table.
priv enum Slot {
  Absent
  Byte(Int32)
  Short(Int32)
  Word(Int32)
  Long(Int64)
  Link(Node)
}

///|
/// What a FlatBuffers offset points to: a table, a string, a vector of tables, or a vector of
/// structs (its count and its bytes, aligned to 8).
priv enum Node {
  Table(Array[Slot])
  Text(String)
  Tables(Array[Node])
  Structs(Int32, Out)
}

///|
/// Writes `node` and returns where it starts: a table's vtable comes before it and what its
/// offsets point to after it, so that every offset points forward.
fn Out::node(self : Out, node : Node) -> Int32 {
  match node {
    Text(s) => {
      self.pad(4)
      let at = self.len
      self.i32(0)
      self.text(s)
      self.patch(at, self.len - at - 4)
      self.u8(0)
      at
    }
    Structs(count, bytes) => {
      self.pad(8, rest=4)
      let at = self.len
      self.i32(count)
      self.append(bytes)
      at
    }
    Tables(tables) => {
      self.pad(4)
      let at = self.len
      self.i32(tables.length())
      for _ in tables {
        self.i32(0)
      }
      for i, table in tables {
        let slot = at + 4 + i * 4
        self.patch(slot, self.node(table) - slot)
      }
      at
    }
    Table(slots) => {
      // Where each value sits after the table's 4-byte offset to its vtable.
      let places = []
      let mut size = 4
      for slot in slots {
        let width = match slot {
          Absent => 0
          Byte(_) => 1
          Short(_) => 2
          Word(_) | Link(_) => 4
          Long(_) => 8
        }
        if width > 0 {
          size = (size + width - 1) / width * width
        }
        places.push(if width == 0 { 0 } else { size })
        size += width
      }
      let vtable_size = 4 + slots.length() * 2
      self.pad(8, rest=(8 - vtable_size % 8) % 8)
      let vtable = self.len
      self.u16(vtable_size)
      self.u16(size)
      for place in places {
        self.u16(place)
      }
      let at = self.len
      self.i32(at - vtable)
      let refs = []
      for i, slot in slots {
        while self.len < at + places[i] {
          self.u8(0)
        }
        match slot {
          Absent => ()
          Byte(v) => self.u8(v)
          Short(v) => self.u16(v)
          Word(v) => self.i32(v)
          Long(v) => self.i64(v)
          Link(child) => {
            refs.push((self.len, child))
            self.i32(0)
          }
        }
      }
      for r in refs {
        self.patch(r.0, self.node(r.1) - r.0)
      }
      at
    }
  }
}

///|
/// A FlatBuffers buffer whose root is `root`, padded to a multiple of 8 bytes.
fn flatbuffer(root : Node) -> Out {
  let out = Out::new()
  out.i32(0)
  out.patch(0, out.node(root))
  out.pad(8)
  out
}

///|
/// Key-value pairs as Schema.fbs's `[KeyValue]`.
fn key_values(pairs : Array[(String, String)]) -> Slot {
  if pairs.is_empty() {
    return Absent
  }
  Link(Tables(pairs.map(p => Table([Link(Text(p.0)), Link(Text(p.1))]))))
}

///|
/// A Schema.fbs `Field` named `name` of the type with code `code` and table `kind`.
fn field_node(
  name : String,
  code : Int32,
  kind : Array[Slot],
  nullable~ : Bool = true,
  children~ : Array[Node] = [],
  metadata~ : Array[(String, String)] = [],
) -> Node {
  Table([
    Link(Text(name)),
    if nullable {
      Byte(1)
    } else {
      Absent
    },
    Byte(code),
    Link(Table(kind)),
    Absent,
    Link(Tables(children)),
    key_values(metadata),
  ])
}

///|
/// A column being written: its field nodes (length, null count) and its buffers in the
/// record batch's order, with the bytes of the body.
priv struct Body {
  nodes : Out
  buffers : Out
  bytes : Out
  mut node_count : Int32
  mut buffer_count : Int32
}

///|
fn Body::node(self : Body, length : Int32, nulls : Int32) -> Unit {
  self.nodes.i64(length.to_int64())
  self.nodes.i64(nulls.to_int64())
  self.node_count += 1
}

///|
/// Adds the buffer `fill` writes (padded to 8 bytes in the body).
fn Body::buffer(self : Body, fill : (Out) -> Unit) -> Unit {
  let start = self.bytes.len
  fill(self.bytes)
  self.buffers.i64(start.to_int64())
  self.buffers.i64((self.bytes.len - start).to_int64())
  self.bytes.pad(8)
  self.buffer_count += 1
}

///|
/// Adds a validity bitmap of `n` rows, empty when `valid` holds for every one; how many
/// rows are null.
fn Body::validity(self : Body, n : Int32, valid : (Int32) -> Bool) -> Int32 {
  let mut nulls = 0
  for i in 0..<n {
    if !valid(i) {
      nulls += 1
    }
  }
  self.buffer(out => if nulls > 0 { bits(out, n, valid) })
  nulls
}

///|
/// `n` bits, the first lowest in each byte.
fn bits(out : Out, n : Int32, bit : (Int32) -> Bool) -> Unit {
  let mut byte = 0
  for i in 0..<n {
    if bit(i) {
      byte = byte | (1 << (i & 7))
    }
    if (i & 7) == 7 || i == n - 1 {
      out.u8(byte)
      byte = 0
    }
  }
}

///|
/// Adds a buffer of the `n + 1` offsets whose steps are `sizes`.
fn Body::offsets(self : Body, n : Int32, size : (Int32) -> Int32) -> Unit {
  self.buffer(out => {
    let mut at = 0
    out.i32(0)
    for i in 0..<n {
      at += size(i)
      out.i32(at)
    }
  })
}

///|
/// The Arrow type a column of property values is written as.
priv enum Written {
  AllNull
  Int32s
  Doubles
  Booleans
  Strings
}

///|
fn written_as(values : Array[@geom.Prop?]) -> Written {
  let mut numbers = 0
  let mut whole = true
  let mut booleans = 0
  let mut strings = 0
  for v in values {
    match v {
      Some(Num(x)) => {
        numbers += 1
        whole = whole && x == x.to_int().to_double()
      }
      Some(Bool(_)) => booleans += 1
      Some(Str(_)) => strings += 1
      _ => ()
    }
  }
  let kinds = [numbers, booleans, strings].filter(n => n > 0).length()
  if kinds == 0 {
    AllNull
  } else if kinds > 1 || strings > 0 {
    Strings
  } else if booleans > 0 {
    Booleans
  } else if whole {
    Int32s
  } else {
    Doubles
  }
}

///|
/// A property column's field, its values added to `body`.
fn property_column(
  body : Body,
  name : String,
  values : Array[@geom.Prop?],
  number_text : (Double) -> String,
) -> Node {
  let n = values.length()
  let valid = (i : Int32) => values[i] is Some(v) && !(v is Null)
  let number = (i : Int32) => if values[i] is Some(Num(x)) { x } else { 0.0 }
  match written_as(values) {
    AllNull => {
      body.node(n, n)
      field_node(name, 1, [])
    }
    Int32s => {
      body.node(n, body.validity(n, valid))
      body.buffer(out => {
        for i in 0..<n {
          out.i32(number(i).to_int())
        }
      })
      field_node(name, 2, [Word(32), Byte(1)])
    }
    Doubles => {
      body.node(n, body.validity(n, valid))
      body.buffer(out => {
        for i in 0..<n {
          out.f64(number(i))
        }
      })
      field_node(name, 3, [Short(2)])
    }
    Booleans => {
      body.node(n, body.validity(n, valid))
      body.buffer(out => bits(out, n, i => values[i] is Some(Bool(true))))
      field_node(name, 6, [])
    }
    Strings => {
      let texts = values.map(v => {
        match v {
          Some(Str(s)) => @utf8.encode(s)
          Some(Num(x)) => @utf8.encode(number_text(x))
          Some(Bool(b)) => if b { b"true" } else { b"false" }
          _ => b""
        }
      })
      body.node(n, body.validity(n, valid))
      body.offsets(n, i => texts[i].length())
      body.buffer(out => {
        for text in texts {
          out.room(text.length())
          for k, byte in text {
            out.bytes[out.len + k] = byte
          }
          out.len += text.length()
        }
      })
      field_node(name, 5, [])
    }
  }
}

///|
/// ISO WKB (little-endian) of row `f` of `t`, which has a geometry.
fn wkb_of(out : Out, t : @geom.Table, f : Int32) -> Unit {
  let header = (code : Int32) => {
    out.u8(1)
    out.i32(code)
  }
  let positions = (r : Int32, count : Bool) => {
    let (a, b) = t.points(r)
    if count {
      out.i32(b - a)
    }
    for i in a..<b {
      out.f64(t.coords[i * 2])
      out.f64(t.coords[i * 2 + 1])
    }
  }
  let (p0, p1) = t.parts(f)
  let rings = (p : Int32) => {
    let (r0, r1) = t.rings(p)
    out.i32(r1 - r0)
    for r in r0..<r1 {
      positions(r, true)
    }
  }
  // Every ring of the row, whichever part it is in.
  let (first, last) = (t.rings(p0).0, t.rings(p1 - 1).1)
  match t.kinds[f] {
    Point => {
      header(1)
      positions(first, false)
    }
    LineString => {
      header(2)
      positions(first, true)
    }
    Polygon => {
      header(3)
      rings(p0)
    }
    MultiPoint => {
      header(4)
      let (a, b) = t.feature_points(f)
      out.i32(b - a)
      for i in a..<b {
        header(1)
        out.f64(t.coords[i * 2])
        out.f64(t.coords[i * 2 + 1])
      }
    }
    MultiLineString => {
      header(5)
      out.i32(last - first)
      for r in first..<last {
        header(2)
        positions(r, true)
      }
    }
    MultiPolygon => {
      header(6)
      out.i32(p1 - p0)
      for p in p0..<p1 {
        header(3)
        rings(p)
      }
    }
    NoGeometry => ()
  }
}

///|
/// GeoArrow's extension type for a table whose rows with a geometry have `kinds` (one kind,
/// or a kind and its multi), and how many lists it nests over points; None for another mix.
fn native_type(kinds : Array[@geom.GeomKind]) -> (String, Int32)? {
  let has = (k : @geom.GeomKind) => kinds.contains(k)
  let only = (a : @geom.GeomKind, b : @geom.GeomKind) => {
    kinds.all(k => k == a || k == b)
  }
  let found = if only(Point, Point) {
    ("point", 0)
  } else if only(Point, MultiPoint) {
    ("multipoint", 1)
  } else if only(LineString, LineString) {
    ("linestring", 1)
  } else if only(LineString, MultiLineString) {
    ("multilinestring", 2)
  } else if only(Polygon, Polygon) {
    ("polygon", 2)
  } else if only(Polygon, MultiPolygon) && has(MultiPolygon) {
    ("multipolygon", 3)
  } else {
    return None
  }
  Some(found)
}

///|
/// The geometry column as GeoArrow's `name` (`lists` deep), its buffers added to `body`.
fn native_column(
  body : Body,
  t : @geom.Table,
  field : String,
  name : String,
  lists : Int32,
  metadata : Array[(String, String)],
) -> Node {
  let n = t.length()
  let has = (f : Int32) => !(t.kinds[f] is NoGeometry)
  // The rows' parts, rings and points, in order: rows without geometry have none.
  let parts = []
  let rings = []
  let mut points = 0
  for f in 0..<n {
    guard has(f) else { continue }
    let (p0, p1) = t.parts(f)
    for p in p0..<p1 {
      parts.push(p)
      let (r0, r1) = t.rings(p)
      for r in r0..<r1 {
        rings.push(r)
        points += t.points(r).1 - t.points(r).0
      }
    }
  }
  let ring_count = (f : Int32) => {
    if has(f) {
      t.rings(t.parts(f).1 - 1).1 - t.rings(t.parts(f).0).0
    } else {
      0
    }
  }
  let point_count = (r : Int32) => t.points(r).1 - t.points(r).0
  let feature_points = (f : Int32) => {
    if has(f) {
      t.feature_points(f).1 - t.feature_points(f).0
    } else {
      0
    }
  }
  let list = (child : Node, label : String) => {
    field_node(label, 12, [], nullable=false, children=[child])
  }
  let xy = field_node("xy", 3, [Short(2)], nullable=false)
  let vertices = (
    label : String,
    nullable : Bool,
    metadata : Array[(String, String)],
  ) => field_node(label, 16, [Word(2)], nullable~, children=[xy], metadata~)
  let coordinates = (count : Int32, row : (Int32) -> (Int32, Int32)) => {
    body.node(count * 2, 0)
    body.buffer(_ => ())
    body.buffer(out => {
      for f in 0..<n {
        let (a, b) = row(f)
        for i in a..<b {
          out.f64(t.coords[i * 2])
          out.f64(t.coords[i * 2 + 1])
        }
        if lists == 0 && a == b {
          out.f64(@double.not_a_number)
          out.f64(@double.not_a_number)
        }
      }
    })
  }
  let all_points = (f : Int32) => {
    if has(f) {
      t.feature_points(f)
    } else {
      (0, 0)
    }
  }
  body.node(n, body.validity(n, has))
  let inner = match lists {
    0 => {
      coordinates(n, all_points)
      return vertices(field, true, metadata)
    }
    1 => {
      body.offsets(n, feature_points)
      vertices("vertices", false, [])
    }
    2 => {
      body.offsets(n, ring_count)
      body.node(rings.length(), 0)
      body.buffer(_ => ())
      body.offsets(rings.length(), i => point_count(rings[i]))
      list(vertices("vertices", false, []), "rings")
    }
    _ => {
      body.offsets(n, f => if has(f) { t.parts(f).1 - t.parts(f).0 } else { 0 })
      body.node(parts.length(), 0)
      body.buffer(_ => ())
      body.offsets(parts.length(), i => {
        t.rings(parts[i]).1 - t.rings(parts[i]).0
      })
      body.node(rings.length(), 0)
      body.buffer(_ => ())
      body.offsets(rings.length(), i => point_count(rings[i]))
      list(list(vertices("vertices", false, []), "rings"), "polygons")
    }
  }
  body.node(points, 0)
  body.buffer(_ => ())
  coordinates(points, all_points)
  ignore(name)
  field_node(field, 12, [], children=[inner], metadata~)
}

///|
/// An encapsulated IPC message: the continuation marker, the metadata's length, the metadata
/// (`header` of type `kind`) and `body`.
fn message(out : Out, kind : Int32, header : Node, body : Out) -> Int32 {
  let meta = flatbuffer(
    Table([Short(4), Byte(kind), Link(header), Long(body.len.to_int64())]),
  )
  out.i32(-1)
  out.i32(meta.len)
  out.append(meta)
  out.append(body)
  8 + meta.len
}

///|
/// `t` as an Arrow IPC stream, or with `file` in the file format (docs/dev/FORMATS.md "Arrow"):
/// its columns by what their cells hold (numbers as text through `number_text` in a mixed one),
/// the geometry as WKB or, with `native`, GeoArrow's type (an error for rows of mixed kinds).
pub fn write_arrow(
  t : @geom.Table,
  native~ : Bool = false,
  file~ : Bool = false,
  number_text~ : (Double) -> String = Double::to_string,
) -> Result[Bytes, String] {
  let n = t.length()
  let body : Body = {
    nodes: Out::new(),
    buffers: Out::new(),
    bytes: Out::new(),
    node_count: 0,
    buffer_count: 0,
  }
  let fields = t.columns.map(c => {
    property_column(body, c.name, c.values, number_text)
  })
  let kinds : Array[@geom.GeomKind] = []
  for k in t.kinds {
    if !(k is NoGeometry) && !kinds.contains(k) {
      kinds.push(k)
    }
  }
  let metadata = []
  if kinds.length() > 0 {
    let mut name = "geometry"
    while t.column(name) is Some(_) {
      name = name + "_"
    }
    let crs = "{\"crs\":\"OGC:CRS84\",\"crs_type\":\"authority_code\"}"
    let encoding = if native {
      guard native_type(kinds) is Some((kind, lists)) else {
        return Err(
          "rows of mixed geometry types have no GeoArrow type: write WKB",
        )
      }
      let extension = [
        (EXTENSION_NAME, "geoarrow.\{kind}"),
        (EXTENSION_METADATA, crs),
      ]
      fields.push(native_column(body, t, name, kind, lists, extension))
      kind
    } else {
      let has = (f : Int32) => !(t.kinds[f] is NoGeometry)
      let cells = Out::new()
      let ends = [0]
      for f in 0..<n {
        if has(f) {
          wkb_of(cells, t, f)
        }
        ends.push(cells.len)
      }
      body.node(n, body.validity(n, has))
      body.offsets(n, f => ends[f + 1] - ends[f])
      body.buffer(out => out.append(cells))
      fields.push(
        field_node(name, 4, [], metadata=[
          (EXTENSION_NAME, "geoarrow.wkb"),
          (EXTENSION_METADATA, crs),
        ]),
      )
      "WKB"
    }
    // The column's name is JSON as it is unless a property was named with quotes.
    let quoted = name
      .replace_all(old="\\", new="\\\\")
      .replace_all(old="\"", new="\\\"")
    metadata.push(
      (
        "geo",
        "{\"version\":\"1.1.0\",\"primary_column\":\"\{quoted}\",\"columns\":{\"\{quoted}\":{\"encoding\":\"\{encoding}\",\"geometry_types\":[]}}}",
      ),
    )
  }
  let schema = () => {
    Node::Table([Absent, Link(Tables(fields)), key_values(metadata)])
  }
  let out = Out::new()
  if file {
    out.text("ARROW1")
    out.pad(8)
  }
  message(out, 1, schema(), Out::new()) |> ignore
  let batch_at = out.len
  let batch_meta = message(
    out,
    3,
    Table([
      Long(n.to_int64()),
      Link(Structs(body.node_count, body.nodes)),
      Link(Structs(body.buffer_count, body.buffers)),
    ]),
    body.bytes,
  )
  out.i32(-1)
  out.i32(0)
  if file {
    let block = Out::new()
    block.i64(batch_at.to_int64())
    block.i32(batch_meta)
    block.i32(0)
    block.i64(body.bytes.len.to_int64())
    let footer = flatbuffer(
      Table([
        Short(4),
        Link(schema()),
        Link(Structs(0, Out::new())),
        Link(Structs(1, block)),
      ]),
    )
    out.append(footer)
    out.i32(footer.len)
    out.text("ARROW1")
  }
  Ok(Bytes::makei(out.len, i => out.bytes[i]))
}
