// Arrow IPC (the streaming and file formats, columnar format 1.x) with GeoArrow's extension
// types, read after their specifications: docs/dev/FORMATS.md "Arrow" has what is read.

///|
/// Deepest nesting of an Arrow schema's fields.
const MAX_ARROW_DEPTH : Int32 = 32

///|
/// Most fields an Arrow schema may have, children included.
const MAX_ARROW_FIELDS : Int32 = 65536

///|
/// Most bytes the compressed buffers of one input may inflate to.
const MAX_ARROW_INFLATED : Int64 = 1L << 30

///|
/// The most bytes of names and metadata one message's strings are decoded from.
const MAX_ARROW_TEXT : Int32 = 1 << 26

///|
/// The field metadata key naming an extension type, and the one with its parameters.
const EXTENSION_NAME : String = "ARROW:extension:name"

///|
const EXTENSION_METADATA : String = "ARROW:extension:metadata"

///|
/// What a read gave besides the table: the geometry column's name (empty without one), its
/// extension metadata and the schema's `geo` metadata (GeoParquet's), both JSON or empty.
pub(all) struct ArrowInfo {
  geometry : String
  extension : String
  geo : String
}

///|
/// Reads an Arrow IPC stream or file: a row per record, its geometry from the first GeoArrow
/// column or the binary column `geo` names (docs/dev/FORMATS.md "Arrow"); columns of numbers,
/// booleans, strings, dates and decimals are kept. ZSTD buffers come inflated in `inflated`.
pub fn read_arrow(
  bytes : BytesView,
  inflated~ : ArrayView[BytesView] = [],
) -> (@geom.Table, ArrowInfo) raise ReadError {
  arrow_table(
    bytes,
    @geom.MAX_TABLE_POINTS,
    @geom.MAX_TABLE_CELLS,
    host=inflated,
  )
}

///|
/// The ZSTD frames `read_arrow` needs inflated (LZ4 it inflates itself): for each, in the order
/// it takes them as `inflated`, its position in `bytes`, its length, -1 (the length it inflates
/// to is not known) and 6 (ZSTD, as Parquet numbers codecs).
pub fn arrow_packed_buffers(bytes : BytesView) -> Array[Int32] raise ReadError {
  let wanted = []
  arrow_table(bytes, @geom.MAX_TABLE_POINTS, @geom.MAX_TABLE_CELLS, wanted~)
  |> ignore
  wanted
}

///|
/// A FlatBuffers buffer read with every position checked; a bad one sets `bad` and reads as 0.
priv struct Flat {
  b : BytesView
  mut bad : Bool
  mut text : Int32
}

///|
fn le_u64(b : BytesView, at : Int32) -> UInt64 {
  let mut bits = 0UL
  for i in 0..<8 {
    bits = bits | (b[at + i].to_uint64() << (i * 8))
  }
  bits
}

///|
fn Flat::has(self : Flat, at : Int32, n : Int32) -> Bool {
  if at < 0 || n < 0 || at > self.b.length() - n {
    self.bad = true
    return false
  }
  true
}

///|
fn Flat::u8(self : Flat, at : Int32) -> Int32 {
  if self.has(at, 1) {
    self.b[at].to_int()
  } else {
    0
  }
}

///|
fn Flat::u16(self : Flat, at : Int32) -> Int32 {
  if self.has(at, 2) {
    self.b[at].to_int() | (self.b[at + 1].to_int() << 8)
  } else {
    0
  }
}

///|
fn Flat::i32(self : Flat, at : Int32) -> Int32 {
  if self.has(at, 4) {
    le_i32(self.b, at)
  } else {
    0
  }
}

///|
fn Flat::i64(self : Flat, at : Int32) -> Int64 {
  if self.has(at, 8) {
    le_u64(self.b, at).reinterpret_as_int64()
  } else {
    0L
  }
}

///|
/// Where field `field` of the table at `table` is, -1 if it is not stored.
fn Flat::field(self : Flat, table : Int32, field : Int32) -> Int32 {
  guard table >= 0 else { return -1 }
  let vtable = table - self.i32(table)
  let size = self.u16(vtable)
  let slot = 4 + field * 2
  if self.bad || slot + 2 > size {
    return -1
  }
  let offset = self.u16(vtable + slot)
  if offset == 0 {
    -1
  } else {
    table + offset
  }
}

///|
/// What the offset at `at` points to, -1 (bad) outside the buffer.
fn Flat::indirect(self : Flat, at : Int32) -> Int32 {
  let offset = self.i32(at)
  if offset < 0 || !self.has(at + offset, 0) {
    self.bad = true
    return -1
  }
  at + offset
}

///|
/// The table that field `field` of `table` points to, -1 without one.
fn Flat::child(self : Flat, table : Int32, field : Int32) -> Int32 {
  let at = self.field(table, field)
  if at < 0 {
    -1
  } else {
    self.indirect(at)
  }
}

///|
/// Where the elements of the vector field `field` start and how many of `size` bytes it has.
fn Flat::vector(
  self : Flat,
  table : Int32,
  field : Int32,
  size : Int32,
) -> (Int32, Int32) {
  let at = self.child(table, field)
  if at < 0 {
    return (0, 0)
  }
  let n = self.i32(at)
  if n < 0 || n > (self.b.length() - at - 4) / size {
    self.bad = true
    return (0, 0)
  }
  (at + 4, n)
}

///|
fn Flat::string(self : Flat, table : Int32, field : Int32) -> String {
  let (at, n) = self.vector(table, field, 1)
  // Offsets may share one string: what is decoded is counted, not what is stored.
  self.text += n
  guard self.text <= MAX_ARROW_TEXT else {
    self.bad = true
    return ""
  }
  @core.utf8_lossy(self.b[at:at + n])
}

///|
/// The small integer field `field` (of `width` bytes: 1, 2 or 4), `default` if not stored.
fn Flat::int(
  self : Flat,
  table : Int32,
  field : Int32,
  width : Int32,
  default : Int32,
) -> Int32 {
  let at = self.field(table, field)
  if at < 0 {
    return default
  }
  match width {
    1 => self.u8(at)
    2 => self.u16(at) << 16 >> 16
    _ => self.i32(at)
  }
}

///|
/// The value of `key` among the key-value pairs of field `field`, empty without it.
fn Flat::metadata(
  self : Flat,
  table : Int32,
  field : Int32,
  key : String,
) -> String {
  let (at, n) = self.vector(table, field, 4)
  for i in 0..<n {
    let pair = self.indirect(at + i * 4)
    if pair >= 0 && self.string(pair, 0) == key {
      return self.string(pair, 1)
    }
  }
  ""
}

///|
/// An Arrow type as its buffers are laid out: `Fixed` and `Union` are types that are only
/// skipped (their buffer count), `Unknown` one whose layout is not read (its type code).
priv enum Kind {
  Nothing
  Int(Int32, Bool)
  Float(Int32)
  Boolean
  Text(Bool)
  Binary(Bool)
  Decimal(Int32, Int32)
  Date(Bool)
  Timestamp(Int32, Bool)
  List(Bool)
  FixedList(Int32)
  Struct
  Fixed(Int32)
  Unknown(Int32)
}

///|
/// A field of the schema: `dictionary` is its dictionary's id and index type when its values
/// are dictionary-encoded, `extension` its extension type's name (empty without one).
priv struct Field {
  name : String
  kind : Kind
  children : Array[Field]
  dictionary : (Int64, Kind)?
  extension : String
  extension_metadata : String
}

///|
/// The field at `table` of `flat` (Schema.fbs `Field`); `count` counts fields against
/// `MAX_ARROW_FIELDS`.
fn Flat::arrow_field(
  self : Flat,
  table : Int32,
  depth : Int32,
  count : Ref[Int32],
) -> Field {
  count.val += 1
  let t = self.child(table, 3)
  let kind = match self.int(table, 2, 1, 0) {
    1 => Nothing
    2 => Int(self.int(t, 0, 4, 0), self.int(t, 1, 1, 0) != 0)
    3 => Float(self.int(t, 0, 2, 0))
    4 => Binary(false)
    5 => Text(false)
    6 => Boolean
    7 => Decimal(self.int(t, 2, 4, 128), self.int(t, 1, 4, 0))
    8 => Date(self.int(t, 0, 2, 1) == 1)
    9 => Fixed(2)
    10 => Timestamp(self.int(t, 0, 2, 0), self.field(t, 1) >= 0)
    11 | 18 => Fixed(2)
    12 | 17 => List(false)
    13 => Struct
    14 => Fixed(if self.int(t, 0, 2, 0) == 1 { 2 } else { 1 })
    15 => Fixed(2)
    16 => FixedList(self.int(t, 0, 4, 0))
    19 => Binary(true)
    20 => Text(true)
    21 => List(true)
    code => Unknown(code)
  }
  let d = self.child(table, 4)
  let dictionary = if d < 0 {
    None
  } else {
    let index = self.child(d, 1)
    let index_kind = if index < 0 {
      Int(32, true)
    } else {
      Int(self.int(index, 0, 4, 0), self.int(index, 1, 1, 0) != 0)
    }
    let id = self.field(d, 0)
    Some((if id < 0 { 0L } else { self.i64(id) }, index_kind))
  }
  let children = []
  let (at, n) = self.vector(table, 5, 4)
  if depth < MAX_ARROW_DEPTH {
    for i in 0..<n {
      guard !self.bad && count.val < MAX_ARROW_FIELDS else { break }
      children.push(
        self.arrow_field(self.indirect(at + i * 4), depth + 1, count),
      )
    }
  } else if n > 0 {
    self.bad = true
  }
  {
    name: self.string(table, 0),
    kind,
    children,
    dictionary,
    extension: self.metadata(table, 6, EXTENSION_NAME),
    extension_metadata: self.metadata(table, 6, EXTENSION_METADATA),
  }
}

///|
/// Which rows of a column hold a value: its validity bitmap, or every row without one.
priv struct Validity {
  bits : BytesView
}

///|
fn Validity::has(self : Validity, i : Int32) -> Bool {
  // Past the bitmap (a list's or struct's own, shorter than its children): null.
  self.bits.length() == 0 ||
  (
    i >> 3 < self.bits.length() &&
    ((self.bits[i >> 3].to_int() >> (i & 7)) & 1) == 1
  )
}

///|
/// A column of a record batch, its buffers checked to hold its rows: fixed-width values,
/// strings or bytes by offsets, dictionary indices with the dictionary's values, lists, lists
/// of a fixed size, structs, nothing but nulls, or a column that is not read.
priv enum Column {
  Values(Kind, Validity, BytesView, Int32)
  Bytes(Bool, Bool, Validity, BytesView, BytesView, Int32)
  Indices(Column, Array[@geom.Prop])
  Lists(Validity, Bool, BytesView, Int32, Column)
  FixedLists(Validity, Int32, Column)
  Structs(Validity, Array[Column])
  Nulls(Int32)
  Skipped
}

///|
/// A record batch being read: `flat` holds its metadata, `body` its buffers; `node` and
/// `buffer` count the field nodes and buffers taken, in the schema's depth-first order.
priv struct Batch {
  flat : Flat
  body : BytesView
  nodes : (Int32, Int32)
  buffers : (Int32, Int32)
  compressed : Bool
  lz4 : Bool
  inflated : Ref[Int64]
  // Per buffer, what the host inflated of it (ZSTD), if anything.
  held : Array[BytesView?]
  mut node : Int32
  mut buffer : Int32
  mut error : String?
}

///|
fn Batch::fail(self : Batch, message : String) -> Unit {
  if self.error is None {
    self.error = Some(message)
  }
}

///|
/// The next field node's length; 0 (failed) without one or past `i32`.
fn Batch::length(self : Batch) -> Int32 {
  guard self.node < self.nodes.1 else {
    self.fail("a column without its field node")
    return 0
  }
  let n = self.flat.i64(self.nodes.0 + self.node * 16)
  self.node += 1
  // A bitmap of more rows would not count its bytes in an Int32.
  guard n >= 0L && n <= 0x3fffffffL else {
    self.fail("a column's length out of range")
    return 0
  }
  n.to_int()
}

///|
/// The next buffer, which must hold at least `least` bytes (else failed, and empty).
fn Batch::take(self : Batch, least : Int64) -> BytesView {
  let empty = self.body[0:0]
  guard self.buffer < self.buffers.1 else {
    self.fail("a column without its buffers")
    return empty
  }
  let at = self.buffers.0 + self.buffer * 16
  self.buffer += 1
  let (offset, length) = (self.flat.i64(at), self.flat.i64(at + 8))
  guard offset >= 0L &&
    length >= 0L &&
    offset <= self.body.length().to_int64() - length else {
    self.fail("a buffer outside the message body")
    return empty
  }
  let stored = self.body[offset.to_int():(offset + length).to_int()]
  let bytes = if self.held.get(self.buffer - 1) is Some(Some(inflated)) {
    inflated
  } else if self.compressed && length > 0L {
    self.inflate(stored)
  } else {
    stored
  }
  guard bytes.length().to_int64() >= least else {
    self.fail("a buffer shorter than its column")
    return empty
  }
  bytes
}

///|
/// A compressed buffer's bytes: eight bytes (-1 if what follows is stored as it is; else a
/// length, which writers disagree on and is not used), then an LZ4 frame. Empty (failed) if
/// malformed or past what one input may inflate to.
fn Batch::inflate(self : Batch, stored : BytesView) -> BytesView {
  let empty = self.body[0:0]
  guard stored.length() >= 8 else {
    self.fail("a compressed buffer without its length")
    return empty
  }
  if le_u64(stored, 0).reinterpret_as_int64() == -1L {
    return stored[8:]
  }
  guard self.lz4 else {
    self.fail("a ZSTD buffer that was not inflated")
    return empty
  }
  let left = MAX_ARROW_INFLATED - self.inflated.val
  match lz4_frame(stored[8:], left.to_int()) {
    Some(bytes) => {
      self.inflated.val += bytes.length().to_int64()
      bytes[:]
    }
    None => {
      self.fail(
        "a malformed LZ4 frame, or buffers that inflate past \{MAX_ARROW_INFLATED} bytes",
      )
      empty
    }
  }
}

///|
/// The next buffer as the validity of `n` rows.
fn Batch::validity(self : Batch, n : Int32) -> Validity {
  let bits = self.take(0L)
  if bits.length() == 0 {
    return { bits, }
  }
  if bits.length() < (n + 7) / 8 {
    self.fail("a validity bitmap shorter than its column")
    return { bits: self.body[0:0], }
  }
  { bits, }
}

///|
/// Bytes of a value of `kind` in a fixed-width buffer; 0 for one held in bits (booleans).
fn Kind::width(self : Kind) -> Int32 {
  match self {
    Int(bits, _) | Decimal(bits, _) => bits / 8
    Float(precision) => 2 << precision
    Date(milliseconds) => if milliseconds { 8 } else { 4 }
    Timestamp(_, _) => 8
    _ => 0
  }
}

///|
/// The column of `field` at the batch's position, with `dictionaries` by id; the nodes and
/// buffers of a column that is not read are passed over.
fn Batch::column(
  self : Batch,
  field : Field,
  dictionaries : Map[Int64, Array[@geom.Prop]],
) -> Column {
  guard self.error is None else { return Skipped }
  if field.dictionary is Some((id, index)) {
    let indices = self.plain(
      { ..field, kind: index, dictionary: None, },
      dictionaries,
    )
    return match dictionaries.get(id) {
      Some(values) => Indices(indices, values)
      None => Skipped
    }
  }
  self.plain(field, dictionaries)
}

///|
/// `column` of a field taken by its own type (a dictionary's indices, or its values).
fn Batch::plain(
  self : Batch,
  field : Field,
  dictionaries : Map[Int64, Array[@geom.Prop]],
) -> Column {
  let n = self.length()
  match field.kind {
    Nothing => Nulls(n)
    Boolean => {
      let valid = self.validity(n)
      Values(Boolean, valid, self.take(((n + 7) / 8).to_int64()), n)
    }
    Int(_, _) | Float(_) | Decimal(_, _) | Date(_) | Timestamp(_, _) as kind => {
      let width = kind.width()
      let valid = self.validity(n)
      let data = self.take(n.to_int64() * width.to_int64())
      let known = match kind {
        Int(bits, _) => bits == 8 || bits == 16 || bits == 32 || bits == 64
        Decimal(bits, _) => bits == 128 || bits == 256
        Float(precision) => precision >= 0 && precision <= 2
        _ => true
      }
      if known {
        Values(kind, valid, data, n)
      } else {
        Skipped
      }
    }
    Text(large) | Binary(large) as kind => {
      let valid = self.validity(n)
      let width = if large { 8L } else { 4L }
      let offsets = self.take((n.to_int64() + 1L) * width)
      Bytes(kind is Text(_), large, valid, offsets, self.take(0L), n)
    }
    List(large) => {
      let valid = self.validity(n)
      let width = if large { 8L } else { 4L }
      let offsets = self.take((n.to_int64() + 1L) * width)
      guard field.children is [child] else {
        self.fail("a list without its one child")
        return Skipped
      }
      Lists(valid, large, offsets, n, self.column(child, dictionaries))
    }
    FixedList(size) => {
      let valid = self.validity(n)
      guard field.children is [child] && size >= 0 else {
        self.fail("a fixed-size list without its one child")
        return Skipped
      }
      FixedLists(valid, size, self.column(child, dictionaries))
    }
    Struct => {
      let valid = self.validity(n)
      Structs(valid, field.children.map(c => self.column(c, dictionaries)))
    }
    Fixed(buffers) => {
      for _ in 0..<buffers {
        self.take(0L) |> ignore
      }
      for child in field.children {
        self.column(child, dictionaries) |> ignore
      }
      Skipped
    }
    Unknown(code) => {
      self.fail("a column of an unsupported type (\{code}): \{field.name}")
      Skipped
    }
  }
}

///|
/// The 4- or 8-byte offset `i` of `offsets`, -1 if it is past `i32`.
fn offset_at(offsets : BytesView, large : Bool, i : Int32) -> Int32 {
  if large {
    let v = le_u64(offsets, i * 8)
    if v > 0x7fffffffUL {
      -1
    } else {
      v.to_int()
    }
  } else {
    le_i32(offsets, i * 4)
  }
}

///|
/// The range of offsets `i` and `i + 1`, None unless it is in order and within `limit`.
fn range_at(
  offsets : BytesView,
  large : Bool,
  i : Int32,
  limit : Int32,
) -> (Int32, Int32)? {
  let (start, end) = (
    offset_at(offsets, large, i),
    offset_at(offsets, large, i + 1),
  )
  guard start >= 0 && end >= start && end <= limit else { return None }
  Some((start, end))
}

///|
/// How many rows a column has (0 for one not read).
fn Column::length(self : Column) -> Int32 {
  match self {
    Values(_, _, _, n)
    | Bytes(_, _, _, _, _, n)
    | Lists(_, _, _, n, _)
    | Nulls(n) => n
    Indices(c, _) => c.length()
    FixedLists(_, size, c) => if size == 0 { 0 } else { c.length() / size }
    Structs(_, children) =>
      children.fold(init=0x7fffffff, (n, c) => n.min(c.length()))
    Skipped => 0
  }
}

///|
/// Row `i` of a fixed-width column as a number (NaN for a type that is not one).
fn number_at(kind : Kind, data : BytesView, i : Int32) -> Double {
  match kind {
    Int(8, signed) => {
      let v = data[i].to_int()
      (if signed { v << 24 >> 24 } else { v }).to_double()
    }
    Int(16, signed) => {
      let v = data[i * 2].to_int() | (data[i * 2 + 1].to_int() << 8)
      (if signed { v << 16 >> 16 } else { v }).to_double()
    }
    Int(32, signed) => {
      let v = le_i32(data, i * 4)
      if signed {
        v.to_double()
      } else {
        v.reinterpret_as_uint().to_double()
      }
    }
    Int(_, signed) => {
      let v = le_u64(data, i * 8)
      if signed {
        v.reinterpret_as_int64().to_double()
      } else {
        v.to_double()
      }
    }
    Float(0) =>
      half_float(data[i * 2].to_int() | (data[i * 2 + 1].to_int() << 8))
    Float(1) => Float::reinterpret_from_int(le_i32(data, i * 4)).to_double()
    Float(_) => le_u64(data, i * 8).reinterpret_as_double()
    Decimal(bits, scale) => {
      // Little-endian two's complement: negated first if negative, so that small values
      // keep their digits when the limbs are summed.
      let count = bits / 64
      let limbs = Array::makei(count, k => le_u64(data, i * (bits / 8) + k * 8))
      let negative = limbs[count - 1] >> 63 == 1UL
      if negative {
        let mut carry = 1UL
        for k in 0..<count {
          limbs[k] = limbs[k].lnot() + carry
          carry = if carry == 1UL && limbs[k] == 0UL { 1UL } else { 0UL }
        }
      }
      let mut sum = 0.0
      for k = count - 1; k >= 0; k = k - 1 {
        sum = sum * 18446744073709551616.0 + limbs[k].to_double()
      }
      let v = scaled(sum, scale)
      if negative {
        -v
      } else {
        v
      }
    }
    _ => @double.not_a_number
  }
}

///|
/// An IEEE 754 half-precision float from its bits.
fn half_float(bits : Int32) -> Double {
  let sign = if (bits & 0x8000) != 0 { -1.0 } else { 1.0 }
  let exponent = (bits >> 10) & 0x1f
  let fraction = (bits & 0x3ff).to_double()
  let two = (e : Int32) => {
    let mut v = 1.0
    for _ in 0..<e.abs() {
      v = if e > 0 { v * 2.0 } else { v / 2.0 }
    }
    v
  }
  if exponent == 0 {
    sign * fraction * two(-24)
  } else if exponent == 31 {
    if fraction == 0.0 {
      sign * @double.infinity
    } else {
      @double.not_a_number
    }
  } else {
    sign * (1024.0 + fraction) * two(exponent - 25)
  }
}

///|
/// `n` in at least `width` decimal digits.
fn padded(n : Int64, width : Int32) -> String {
  let digits = n.to_string()
  "0".repeat((width - digits.length()).max(0)) + digits
}

///|
/// The ISO 8601 date of `days` since 1970-01-01 (the proleptic Gregorian calendar; Howard
/// Hinnant's `civil_from_days`).
fn iso_date(days : Int64) -> String {
  let z = days + 719468L
  let era = (if z >= 0L { z } else { z - 146096L }) / 146097L
  let doe = z - era * 146097L
  let yoe = (doe - doe / 1460L + doe / 36524L - doe / 146096L) / 365L
  let doy = doe - (365L * yoe + yoe / 4L - yoe / 100L)
  let mp = (5L * doy + 2L) / 153L
  let day = doy - (153L * mp + 2L) / 5L + 1L
  let month = if mp < 10L { mp + 3L } else { mp - 9L }
  let year = yoe + era * 400L + (if month <= 2L { 1L } else { 0L })
  let sign = if year < 0L { "-" } else { "" }
  "\{sign}\{padded(year.abs(), 4)}-\{padded(month, 2)}-\{padded(day, 2)}"
}

///|
/// `a` divided by `b` (positive) rounded down, and what is left.
fn floor_div(a : Int64, b : Int64) -> (Int64, Int64) {
  let q = a / b
  if a % b < 0L {
    (q - 1L, a - (q - 1L) * b)
  } else {
    (q, a - q * b)
  }
}

///|
/// The ISO 8601 date and time of `ms` milliseconds since 1970-01-01T00:00:00, with `Z` for a
/// timestamp that has a time zone (Arrow keeps those in UTC).
fn iso_time(ms : Int64, utc : Bool) -> String {
  let (days, rest) = floor_div(ms, 86400000L)
  let (seconds, millis) = (rest / 1000L, rest % 1000L)
  let clock = "\{padded(seconds / 3600L, 2)}:\{padded(seconds / 60L % 60L, 2)}:\{padded(seconds % 60L, 2)}"
  let fraction = if millis == 0L { "" } else { ".\{padded(millis, 3)}" }
  "\{iso_date(days)}T\{clock}\{fraction}\{if utc { "Z" } else { "" }}"
}

///|
/// Row `i` of a property column: null for a null or a column that holds no property values.
fn Column::prop(self : Column, i : Int32) -> @geom.Prop {
  match self {
    Values(kind, valid, data, _) => {
      guard valid.has(i) else { return Null }
      match kind {
        Boolean => Bool(((data[i >> 3].to_int() >> (i & 7)) & 1) == 1)
        Date(milliseconds) =>
          if milliseconds {
            let ms = le_u64(data, i * 8).reinterpret_as_int64()
            Str(iso_date(floor_div(ms, 86400000L).0))
          } else {
            Str(iso_date(le_i32(data, i * 4).to_int64()))
          }
        Timestamp(unit, utc) => {
          let v = le_u64(data, i * 8).reinterpret_as_int64()
          let ms = match unit {
            0 => v * 1000L
            1 => v
            2 => floor_div(v, 1000L).0
            _ => floor_div(v, 1000000L).0
          }
          Str(iso_time(ms, utc))
        }
        _ => {
          let x = number_at(kind, data, i)
          if x.is_nan() {
            Null
          } else {
            Num(x)
          }
        }
      }
    }
    Bytes(true, large, valid, offsets, data, _) => {
      guard valid.has(i) &&
        range_at(offsets, large, i, data.length()) is Some((start, end)) else {
        return Null
      }
      Str(@core.utf8_lossy(data[start:end]))
    }
    Indices(indices, values) =>
      match indices.prop(i) {
        Num(k) if k >= 0.0 && k < values.length().to_double() =>
          values[k.to_int()]
        _ => Null
      }
    _ => Null
  }
}

///|
/// Whether the column holds property values (`prop`).
fn Column::is_property(self : Column) -> Bool {
  match self {
    Values(_, _, _, _) | Bytes(true, _, _, _, _, _) | Nulls(_) => true
    Indices(c, _) => c.is_property()
    _ => false
  }
}

///|
/// How a geometry column holds its rows: WKB, or GeoArrow's nesting of lists over points
/// (`lists` deep) making `kind`.
priv enum Encoding {
  Wkb
  Native(Int32, @geom.GeomKind)
}

///|
/// The encoding GeoArrow's extension type `name` stands for.
fn encoding_of(name : String) -> Encoding? {
  let found = match name {
    "geoarrow.wkb" | "ogc.wkb" => Wkb
    "geoarrow.point" => Native(0, Point)
    "geoarrow.linestring" => Native(1, LineString)
    "geoarrow.multipoint" => Native(1, MultiPoint)
    "geoarrow.polygon" => Native(2, Polygon)
    "geoarrow.multilinestring" => Native(2, MultiLineString)
    "geoarrow.multipolygon" => Native(3, MultiPolygon)
    _ => return None
  }
  Some(found)
}

///|
/// What reading rows needs besides the columns: the shapes of a row, a WKB reader, the points
/// read so far and the first error.
priv struct ArrowRows {
  wkb : Wkb
  shapes : Shapes
  max_points : Int32
  mut used : Int32
  mut error : String?
}

///|
fn ArrowRows::fail(self : ArrowRows, message : String) -> Unit {
  if self.error is None {
    self.error = Some(message)
  }
}

///|
/// Adds point `i` of a column of points (a fixed-size list of interleaved doubles, or a
/// struct of x, y, …) to the shapes; false for a point of NaN, which GeoArrow reads as empty.
fn ArrowRows::point(self : ArrowRows, points : Column, i : Int32) -> Bool {
  let (x, y) = match points {
    FixedLists(_, size, Values(Float(2), _, data, n)) if size >= 2 &&
      i < n / size => {
      let at = i * size * 8
      (
        le_u64(data, at).reinterpret_as_double(),
        le_u64(data, at + 8).reinterpret_as_double(),
      )
    }
    Structs(_, [Values(Float(2), _, xs, n), Values(Float(2), _, ys, m), ..]) if i <
      n.min(m) =>
      (
        le_u64(xs, i * 8).reinterpret_as_double(),
        le_u64(ys, i * 8).reinterpret_as_double(),
      )
    _ => {
      self.fail("a GeoArrow column whose points are not doubles")
      return false
    }
  }
  if x.is_nan() && y.is_nan() {
    return false
  }
  if x.is_nan() || y.is_nan() || x.is_inf() || y.is_inf() {
    self.fail("a coordinate that is not finite")
    return false
  }
  self.used += 1
  guard self.used <= self.max_points else {
    self.fail("more than \{self.max_points} points")
    return false
  }
  self.shapes.point(x, y)
  true
}

///|
/// Calls `each` with the child and the range row `i` of a list column covers; nothing for a
/// null row, failing for offsets out of order or past the child.
fn ArrowRows::items(
  self : ArrowRows,
  list : Column,
  i : Int32,
  each : (Column, Int32) -> Unit,
) -> Unit {
  guard list is Lists(valid, large, offsets, n, child) && i < n else {
    self.fail("a GeoArrow column that is not the lists its type names")
    return
  }
  guard valid.has(i) else { return }
  guard range_at(offsets, large, i, child.length()) is Some((start, end)) else {
    self.fail("list offsets out of order or past their values")
    return
  }
  for j in start..<end {
    guard self.error is None else { return }
    each(child, j)
  }
}

///|
/// Row `i` of a GeoArrow column of `lists` levels making `kind`, into the shapes.
fn ArrowRows::native(
  self : ArrowRows,
  column : Column,
  lists : Int32,
  kind : @geom.GeomKind,
  i : Int32,
) -> Unit {
  let s = self.shapes
  let ring = (points : Column, j : Int32) => {
    self.items(points, j, (c, k) => self.point(c, k) |> ignore)
    s.end_ring()
  }
  match (lists, kind) {
    (0, _) => {
      let valid = match column {
        FixedLists(valid, _, _) | Structs(valid, _) => valid.has(i)
        _ => true
      }
      if valid && self.point(column, i) {
        s.end_ring()
        s.end_part()
      }
    }
    (1, _) => {
      ring(column, i)
      s.end_part()
    }
    (2, Polygon) => {
      self.items(column, i, ring)
      s.end_part()
    }
    (2, _) =>
      self.items(column, i, (c, j) => {
        ring(c, j)
        s.end_part()
      })
    _ =>
      self.items(column, i, (c, j) => {
        self.items(c, j, ring)
        s.end_part()
      })
  }
  s.end_member(kind)
}

///|
/// The quoted string after `"key":` in `json`, empty without one: enough to find what GeoParquet's
/// `geo` metadata names as its primary column.
fn json_string_after(json : String, key : String) -> String {
  guard json.find("\"\{key}\"") is Some(at) else { return "" }
  let rest = json[at + key.length() + 2:].to_owned()
  guard rest.find("\"") is Some(open) else { return "" }
  let value = rest[open + 1:].to_owned()
  guard value.find("\"") is Some(close) else { return "" }
  value[:close].to_owned()
}

///|
/// A read in progress: the schema's fields, the dictionaries read so far, which column holds the
/// geometry and how, and the rows going to `out`.
priv struct ArrowReader {
  bytes : BytesView
  out : @geom.TableBuilder
  fields : Array[Field]
  dictionaries : Map[Int64, Array[@geom.Prop]]
  rows : ArrowRows
  max_cells : Int32
  mut seen : Int64
  inflated : Ref[Int64]
  // The buffers the host inflated (ZSTD), in the order they are met, or where to list them.
  host : ArrayView[BytesView]
  mut next_host : Int32
  wanted : Array[Int32]?
  mut geometry : (Int32, Encoding)?
  mut geo : String
  mut seen_schema : Bool
}

///|
fn arrow_error(at : Int32, message : String) -> ReadError {
  Invalid(format="Arrow", pos=at, message)
}

///|
/// Takes the Schema.fbs `Schema` at `table` of `flat` (the message or footer at `at`).
fn ArrowReader::schema(
  self : ArrowReader,
  flat : Flat,
  table : Int32,
  at : Int32,
) -> Unit raise ReadError {
  guard !self.seen_schema else { raise arrow_error(at, "a second schema") }
  self.seen_schema = true
  guard flat.int(table, 0, 2, 0) == 0 else {
    raise arrow_error(at, "big-endian data is not supported")
  }
  let fields = self.fields
  let count = Ref(0)
  let (list, n) = flat.vector(table, 1, 4)
  for i in 0..<n {
    guard !flat.bad && count.val < MAX_ARROW_FIELDS else { break }
    fields.push(flat.arrow_field(flat.indirect(list + i * 4), 0, count))
  }
  guard !flat.bad && count.val < MAX_ARROW_FIELDS else {
    raise arrow_error(at, "a malformed schema")
  }
  self.geo = flat.metadata(table, 2, "geo")
  let primary = json_string_after(self.geo, "primary_column")
  let binary = (named : (Field) -> Bool) => {
    fields.search_by(f => f.kind is Binary(_) && named(f)).map(i => (i, Wkb))
  }
  let conventional = ["geometry", "geom", "wkb_geometry"]
  self.geometry = match
    fields.search_by(f => encoding_of(f.extension) is Some(_)) {
    Some(i) => Some((i, encoding_of(fields[i].extension).unwrap()))
    None =>
      match binary(f => f.name == primary) {
        Some(found) => Some(found)
        None => binary(f => conventional.contains(f.name.to_lower()))
      }
  }
}

///|
/// Takes a dictionary batch (`kind` 2) or a record batch (3) whose header is `header` of `flat`
/// and whose buffers are `body`.
fn ArrowReader::data(
  self : ArrowReader,
  flat : Flat,
  header : Int32,
  kind : Int32,
  body : BytesView,
  at : Int32,
  body_at : Int32,
) -> Unit raise ReadError {
  guard self.seen_schema else {
    raise arrow_error(at, "data before the schema")
  }
  let fields = self.fields
  let rows = self.rows
  let record = if kind == 2 { flat.child(header, 1) } else { header }
  let compression = flat.child(record, 3)
  let codec = if compression < 0 { -1 } else { flat.int(compression, 0, 1, 0) }
  guard codec <= 1 else {
    raise arrow_error(at, "buffers compressed with a codec that is not read")
  }
  // ZSTD buffers are inflated by the host: listed on one pass, taken in that order on the next.
  let held : Array[BytesView?] = []
  if codec == 1 {
    let (list, count) = flat.vector(record, 2, 16)
    for i in 0..<count {
      let (offset, length) = (
        flat.i64(list + i * 16),
        flat.i64(list + i * 16 + 8),
      )
      guard offset >= 0L &&
        length >= 0L &&
        offset <= body.length().to_int64() - length else {
        raise arrow_error(at, "a buffer outside the message body")
      }
      let stored = body[offset.to_int():(offset + length).to_int()]
      if length <= 8L || le_u64(stored, 0).reinterpret_as_int64() == -1L {
        held.push(None)
      } else if self.wanted is Some(wanted) {
        wanted.push(body_at + offset.to_int() + 8)
        wanted.push(length.to_int() - 8)
        wanted.push(-1)
        wanted.push(6)
      } else {
        guard self.next_host < self.host.length() else {
          raise arrow_error(at, "a ZSTD buffer that was not inflated")
        }
        let inflated = self.host[self.next_host]
        self.next_host += 1
        self.inflated.val += inflated.length().to_int64()
        guard self.inflated.val <= MAX_ARROW_INFLATED else {
          raise arrow_error(
            at,
            "buffers that inflate past \{MAX_ARROW_INFLATED} bytes",
          )
        }
        held.push(Some(inflated))
      }
    }
  }
  guard self.wanted is None else { return }
  let batch : Batch = {
    flat,
    body,
    compressed: codec >= 0,
    lz4: codec == 0,
    held,
    inflated: self.inflated,
    nodes: flat.vector(record, 1, 16),
    buffers: flat.vector(record, 2, 16),
    node: 0,
    buffer: 0,
    error: None,
  }
  if kind == 2 {
    let id_at = flat.field(header, 0)
    let id = if id_at < 0 { 0L } else { flat.i64(id_at) }
    let delta = flat.int(header, 2, 1, 0) != 0
    guard dictionary_field(fields, id) is Some(field) else {
      raise arrow_error(at, "a dictionary no field uses")
    }
    let column = batch.plain({ ..field, dictionary: None, }, self.dictionaries)
    guard batch.error is None && !flat.bad else {
      raise arrow_error(at, batch.error.unwrap_or("a malformed dictionary"))
    }
    let values = if delta {
      self.dictionaries.get(id).unwrap_or([])
    } else {
      []
    }
    if column.is_property() {
      guard column.length() <= self.max_cells - values.length() else {
        raise arrow_error(
          at,
          "a dictionary of more than \{self.max_cells} values",
        )
      }
      for i in 0..<column.length() {
        values.push(column.prop(i))
      }
    }
    self.dictionaries[id] = values
    return
  }
  let columns = fields.map(f => batch.column(f, self.dictionaries))
  let length_at = flat.field(record, 0)
  let n = if length_at < 0 { 0L } else { flat.i64(length_at) }
  guard batch.error is None && !flat.bad && n >= 0L && n <= 0x7fffffffL else {
    raise arrow_error(at, batch.error.unwrap_or("a malformed record batch"))
  }
  // Rows without a property column are no cells: the rows themselves are counted.
  self.seen += n
  guard self.seen <= self.max_cells.to_int64() else {
    raise arrow_error(at, "more than \{self.max_cells} rows")
  }
  for c, column in columns {
    guard column is Skipped || column.length() >= n.to_int() else {
      raise arrow_error(at, "column \{fields[c].name} shorter than its batch")
    }
  }
  let props = []
  for i in 0..<n.to_int() {
    rows.shapes.clear()
    let mut from_wkb = false
    if self.geometry is Some((g, encoding)) {
      match (encoding, columns[g]) {
        (Wkb, Bytes(false, large, valid, offsets, data, _)) =>
          if valid.has(i) {
            guard range_at(offsets, large, i, data.length()) is Some((s, e)) else {
              raise arrow_error(at, "binary offsets out of order")
            }
            guard rows.wkb.cell(data[s:e]) else {
              raise arrow_error(at, "malformed WKB in a row")
            }
            rows.used += rows.wkb.shapes.points()
            from_wkb = true
          }
        (Native(lists, kind), column) => rows.native(column, lists, kind, i)
        _ => rows.fail("a geometry column of another type than its name says")
      }
    }
    guard rows.error is None && rows.used <= rows.max_points else {
      raise arrow_error(
        at,
        rows.error.unwrap_or("more than \{rows.max_points} points"),
      )
    }
    props.clear()
    for c, column in columns {
      if column.is_property() && !(self.geometry is Some((g, _)) && g == c) {
        props.push((fields[c].name, column.prop(i)))
      }
    }
    let shapes = if from_wkb { rows.wkb.shapes } else { rows.shapes }
    shapes.emit(self.out, props, None, max_cells=self.max_cells)
    if property_limit(self.out, self.max_cells) is Some(why) {
      raise arrow_error(at, why)
    }
  }
}

///|
/// Takes the encapsulated message at `pos`; where the next one starts, -1 after the last.
fn ArrowReader::message(
  self : ArrowReader,
  pos : Int32,
) -> Int32 raise ReadError {
  let bytes = self.bytes
  let mut pos = pos
  guard pos >= 0 && pos <= bytes.length() - 4 else { return -1 }
  let mut size = le_i32(bytes, pos)
  if size == -1 {
    pos += 4
    guard pos <= bytes.length() - 4 else { return -1 }
    size = le_i32(bytes, pos)
  }
  pos += 4
  if size == 0 {
    return -1
  }
  guard size > 0 && size <= bytes.length() - pos else {
    raise arrow_error(pos, "a message past the end of the data")
  }
  let flat : Flat = { b: bytes[pos:pos + size], bad: false, text: 0, }
  let message = flat.indirect(0)
  let header = flat.child(message, 2)
  let length_at = flat.field(message, 3)
  let body_length = if length_at < 0 { 0L } else { flat.i64(length_at) }
  let start = pos + size
  guard !flat.bad &&
    body_length >= 0L &&
    body_length <= (bytes.length() - start).to_int64() else {
    raise arrow_error(pos, "a malformed message")
  }
  let body = bytes[start:start + body_length.to_int()]
  match flat.int(message, 1, 1, 0) {
    1 => self.schema(flat, header, pos)
    2 | 3 as kind => self.data(flat, header, kind, body, pos, start)
    _ => ()
  }
  start + body_length.to_int()
}

///|
/// Bytes an Arrow file starts and ends with.
let arrow_magic : Bytes = b"ARROW1"

///|
/// `read_arrow` taking at most `max_points` points and `max_cells` property cells.
fn arrow_table(
  bytes : BytesView,
  max_points : Int32,
  max_cells : Int32,
  host~ : ArrayView[BytesView] = [],
  wanted? : Array[Int32],
) -> (@geom.Table, ArrowInfo) raise ReadError {
  let reader : ArrowReader = {
    bytes,
    out: @geom.TableBuilder::new(),
    fields: [],
    dictionaries: Map([]),
    rows: {
      wkb: Wkb::new(bytes, max_points),
      shapes: Shapes::new(),
      max_points,
      used: 0,
      error: None,
    },
    max_cells,
    seen: 0L,
    inflated: Ref(0L),
    host,
    next_host: 0,
    wanted,
    geometry: None,
    geo: "",
    seen_schema: false,
  }
  let n = bytes.length()
  if n >= 18 && bytes[0:6] == arrow_magic && bytes[n - 6:] == arrow_magic {
    // The file format: the schema and where the batches are come from the footer (a writer
    // need not repeat the schema among the messages).
    let size = le_i32(bytes, n - 10)
    guard size > 0 && size <= n - 18 else {
      raise arrow_error(n - 10, "a footer past the start of the file")
    }
    let at = n - 10 - size
    let flat : Flat = { b: bytes[at:n - 10], bad: false, text: 0, }
    let footer = flat.indirect(0)
    reader.schema(flat, flat.child(footer, 1), at)
    for blocks in [2, 3] {
      let (list, count) = flat.vector(footer, blocks, 24)
      // In the file's order, so that no message is read twice.
      let mut last = -1L
      for i in 0..<count {
        let offset = flat.i64(list + i * 24)
        guard offset > last && offset <= n.to_int64() else {
          raise arrow_error(at, "a block outside the file, or out of order")
        }
        last = offset
        reader.message(offset.to_int()) |> ignore
      }
    }
    guard !flat.bad else { raise arrow_error(at, "a malformed footer") }
  } else {
    let mut pos = 0
    while pos >= 0 {
      pos = reader.message(pos)
    }
  }
  guard reader.seen_schema else { raise arrow_error(0, "no schema") }
  let info = match reader.geometry {
    Some((g, _)) =>
      {
        geometry: reader.fields[g].name,
        extension: reader.fields[g].extension_metadata,
        geo: reader.geo,
      }
    None => { geometry: "", extension: "", geo: reader.geo, }
  }
  (reader.out.finish(), info)
}

///|
/// The field whose values dictionary `id` holds, searched depth first.
fn dictionary_field(fields : Array[Field], id : Int64) -> Field? {
  for f in fields {
    if f.dictionary is Some((d, _)) && d == id {
      return Some(f)
    }
    if dictionary_field(f.children, id) is Some(found) {
      return Some(found)
    }
  }
  None
}
