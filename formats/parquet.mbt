// Parquet files with GeoParquet's metadata, read after the format's specification
// (parquet-format's parquet.thrift, Encodings.md and LogicalTypes.md) and Snappy's format
// description: docs/dev/FORMATS.md "Parquet" has what is read.

///|
/// Bytes a Parquet file starts and ends with.
let parquet_magic : Bytes = b"PAR1"

///|
/// Deepest nesting of Thrift structs in a Parquet footer or page header.
const MAX_THRIFT_DEPTH : Int32 = 32

///|
/// Most schema elements, row groups and columns of a row group a Parquet file may have.
const MAX_PARQUET_ITEMS : Int32 = 65536

///|
/// Thrift compact protocol type codes.
const T_TRUE : Int32 = 1

///|
const T_FALSE : Int32 = 2

///|
const T_BYTE : Int32 = 3

///|
const T_I16 : Int32 = 4

///|
const T_I32 : Int32 = 5

///|
const T_I64 : Int32 = 6

///|
const T_DOUBLE : Int32 = 7

///|
const T_BINARY : Int32 = 8

///|
const T_LIST : Int32 = 9

///|
const T_SET : Int32 = 10

///|
const T_MAP : Int32 = 11

///|
const T_STRUCT : Int32 = 12

///|
/// parquet.thrift's `Type` (a leaf's physical type).
const BOOLEAN : Int32 = 0

///|
const INT32 : Int32 = 1

///|
const INT64 : Int32 = 2

///|
const INT96 : Int32 = 3

///|
const FLOAT : Int32 = 4

///|
const DOUBLE : Int32 = 5

///|
const BYTE_ARRAY : Int32 = 6

///|
const FIXED_LEN_BYTE_ARRAY : Int32 = 7

///|
/// parquet.thrift's `Encoding`.
const PLAIN : Int32 = 0

///|
const PLAIN_DICTIONARY : Int32 = 2

///|
const RLE : Int32 = 3

///|
const DELTA_BINARY_PACKED : Int32 = 5

///|
const DELTA_LENGTH_BYTE_ARRAY : Int32 = 6

///|
const DELTA_BYTE_ARRAY : Int32 = 7

///|
const RLE_DICTIONARY : Int32 = 8

///|
const BYTE_STREAM_SPLIT : Int32 = 9

///|
/// parquet.thrift's `CompressionCodec`: those read.
const UNCOMPRESSED : Int32 = 0

///|
const SNAPPY : Int32 = 1

///|
const GZIP : Int32 = 2

///|
const ZSTD : Int32 = 6

///|
/// parquet.thrift's `PageType`: those read.
const DATA_PAGE : Int32 = 0

///|
const DICTIONARY_PAGE : Int32 = 2

///|
const DATA_PAGE_V2 : Int32 = 3

///|
/// Thrift's compact protocol over `b`: a bad read sets `bad` and gives 0.
priv struct Thrift {
  b : BytesView
  mut pos : Int32
  mut bad : Bool
  mut depth : Int32
}

///|
fn Thrift::byte(self : Thrift) -> Int32 {
  guard self.pos < self.b.length() else {
    self.bad = true
    return 0
  }
  self.pos += 1
  self.b[self.pos - 1].to_int()
}

///|
/// An unsigned LEB128 integer of at most 64 bits.
fn Thrift::varint(self : Thrift) -> UInt64 {
  let mut v = 0UL
  for shift = 0; shift < 70; shift = shift + 7 {
    let b = self.byte()
    v = v | ((b & 0x7f).to_uint64() << shift)
    if (b & 0x80) == 0 {
      return v
    }
  }
  self.bad = true
  0UL
}

///|
/// A zigzag integer (i16, i32, i64).
fn Thrift::int(self : Thrift) -> Int64 {
  let v = self.varint()
  (v >> 1).reinterpret_as_int64() ^ -(v & 1UL).reinterpret_as_int64()
}

///|
/// An i32 that must be one: 0 (bad) outside its range.
fn Thrift::i32(self : Thrift) -> Int32 {
  let v = self.int()
  guard v >= -2147483648L && v <= 2147483647L else {
    self.bad = true
    return 0
  }
  v.to_int()
}

///|
fn Thrift::binary(self : Thrift) -> BytesView {
  let n = self.varint()
  guard n <= (self.b.length() - self.pos).to_uint64() else {
    self.bad = true
    return self.b[0:0]
  }
  self.pos += n.to_int()
  self.b[self.pos - n.to_int():self.pos]
}

///|
/// A list's element type and size.
fn Thrift::list(self : Thrift) -> (Int32, Int32) {
  let head = self.byte()
  let size = if head >> 4 == 15 {
    let n = self.varint()
    guard n <= (self.b.length() - self.pos).to_uint64() else {
      self.bad = true
      return (0, 0)
    }
    n.to_int()
  } else {
    head >> 4
  }
  (head & 15, size)
}

///|
/// Passes over a value of type `kind` (a compact protocol type code).
fn Thrift::skip(self : Thrift, kind : Int32) -> Unit {
  match kind {
    T_TRUE | T_FALSE => ()
    T_BYTE => self.byte() |> ignore
    T_I16 | T_I32 | T_I64 => self.varint() |> ignore
    T_DOUBLE => {
      guard self.pos <= self.b.length() - 8 else {
        self.bad = true
        return
      }
      self.pos += 8
    }
    T_BINARY => self.binary() |> ignore
    T_LIST | T_SET => {
      let (element, n) = self.list()
      for _ in 0..<n {
        guard !self.bad else { return }
        // A boolean in a list takes a byte.
        self.skip(
          if element == T_TRUE || element == T_FALSE {
            T_BYTE
          } else {
            element
          },
        )
      }
    }
    T_MAP => {
      let n = self.varint()
      guard n <= (self.b.length() - self.pos).to_uint64() else {
        self.bad = true
        return
      }
      if n > 0UL {
        let kinds = self.byte()
        for _ in 0..<n.to_int() {
          guard !self.bad else { return }
          self.skip(kinds >> 4)
          self.skip(kinds & 15)
        }
      }
    }
    T_STRUCT => self.fields((_, kind) => self.skip(kind))
    _ => self.bad = true
  }
}

///|
/// Calls `each` with the id and type of every field of the struct at the position; `each`
/// must read the value or `skip` it.
fn Thrift::fields(self : Thrift, each : (Int32, Int32) -> Unit) -> Unit {
  self.depth += 1
  guard self.depth <= MAX_THRIFT_DEPTH else {
    self.bad = true
    return
  }
  let mut id = 0
  while !self.bad {
    let head = self.byte()
    if head == 0 {
      break
    }
    id = if head >> 4 == 0 { self.i32() } else { id + (head >> 4) }
    each(id, head & 15)
  }
  self.depth -= 1
}

///|
/// Calls `each` for every struct of the list at the position (`kind` 9), skipping other values.
fn Thrift::structs(self : Thrift, kind : Int32, each : () -> Unit) -> Unit {
  guard kind == T_LIST else {
    self.skip(kind)
    return
  }
  let (element, n) = self.list()
  guard (element == T_STRUCT || n == 0) && n <= MAX_PARQUET_ITEMS else {
    self.bad = true
    return
  }
  for _ in 0..<n {
    guard !self.bad else { return }
    each()
  }
}

///|
/// What a column's values stand for beyond their physical type.
priv enum Logical {
  Plain
  Text
  Decimal(Int32)
  Date
  Timestamp(Int32, Bool)
  Integer(Int32, Bool)
  Float16
  Geometry
  Other
}

///|
/// A leaf of the schema: its physical type (parquet.thrift's `Type`), whether it may be null,
/// `flat`, whether it is a column of the rows themselves (not inside a group or repeated), and
/// `path`, its name after its groups' (`bbox.xmin`).
priv struct Leaf {
  name : String
  path : String
  physical : Int32
  length : Int32
  optional : Bool
  logical : Logical
  flat : Bool
}

///|
/// The LogicalType union at the position (parquet.thrift).
fn Thrift::logical(self : Thrift) -> Logical {
  let mut found = Other
  self.fields((which, kind) => {
    found = match which {
      5 => {
        let mut scale = 0
        self.fields((id, kind) => {
          if id == 1 {
            scale = self.i32()
          } else {
            self.skip(kind)
          }
        })
        Decimal(scale)
      }
      8 => {
        let mut utc = false
        let mut unit = 0
        self.fields((id, kind) => {
          match id {
            1 => utc = kind == T_TRUE
            2 =>
              self.fields((u, kind) => {
                unit = u
                self.skip(kind)
              })
            _ => self.skip(kind)
          }
        })
        Timestamp(unit, utc)
      }
      10 => {
        let mut bits = 0
        let mut signed = false
        self.fields((id, kind) => {
          match id {
            1 => bits = self.byte()
            2 => signed = kind == T_TRUE
            _ => self.skip(kind)
          }
        })
        Integer(bits, signed)
      }
      _ => {
        self.skip(kind)
        match which {
          1 | 4 | 12 => Text
          6 => Date
          11 => Plain
          15 => Float16
          17 | 18 => Geometry
          _ => Other
        }
      }
    }
  })
  found
}

///|
/// The SchemaElement at the position: its name, its leaf (None for a group) and its children's
/// count.
fn Thrift::schema_element(self : Thrift, top : Bool) -> (String, Leaf?, Int32) {
  let mut name = ""
  let mut physical = -1
  let mut length = 0
  let mut repetition = 0
  let mut children = 0
  let mut converted = -1
  let mut scale = 0
  let mut logical : Logical? = None
  self.fields((id, kind) => {
    match id {
      1 => physical = self.i32()
      2 => length = self.i32()
      3 => repetition = self.i32()
      4 => name = @core.utf8_lossy(self.binary())
      5 => children = self.i32()
      6 => converted = self.i32()
      7 => scale = self.i32()
      10 => logical = Some(self.logical())
      _ => self.skip(kind)
    }
  })
  if physical < 0 {
    return (name, None, children)
  }
  // ConvertedType, for files without a LogicalType.
  let logical = match logical {
    Some(l) => l
    None =>
      match converted {
        0 | 4 | 19 => Text
        5 => Decimal(scale)
        6 => Date
        9 => Timestamp(1, true)
        10 => Timestamp(2, true)
        11 => Integer(8, false)
        12 => Integer(16, false)
        13 => Integer(32, false)
        14 => Integer(64, false)
        -1 | 15 | 16 | 17 | 18 => Plain
        _ => Other
      }
  }
  (
    name,
    Some({
      name,
      path: name,
      physical,
      length,
      optional: repetition == 1,
      logical,
      flat: top && repetition != 2,
    }),
    children,
  )
}

///|
/// A column chunk: its codec (parquet.thrift's `CompressionCodec`), where its pages start and
/// how many bytes they take, and its statistics' smallest and largest value as stored (empty
/// without them).
priv struct Chunk {
  codec : Int32
  start : Int64
  size : Int64
  min : BytesView
  max : BytesView
}

///|
fn Thrift::chunk(self : Thrift) -> Chunk {
  let mut codec = 0
  let mut size = 0L
  let mut data = 0L
  let mut dictionary = 0L
  let mut min = self.b[0:0]
  let mut max = self.b[0:0]
  self.fields((id, kind) => {
    if id == 3 && kind == T_STRUCT {
      self.fields((id, kind) => {
        match id {
          4 => codec = self.i32()
          7 => size = self.int()
          9 => data = self.int()
          11 => dictionary = self.int()
          // Statistics: `min_value` and `max_value`, or the older `min` and `max`.
          12 if kind == T_STRUCT =>
            self.fields((id, kind) => {
              match id {
                1 | 5 if kind == T_BINARY => {
                  let v = self.binary()
                  if id == 5 || max.length() == 0 {
                    max = v
                  }
                }
                2 | 6 if kind == T_BINARY => {
                  let v = self.binary()
                  if id == 6 || min.length() == 0 {
                    min = v
                  }
                }
                _ => self.skip(kind)
              }
            })
          _ => self.skip(kind)
        }
      })
    } else {
      self.skip(kind)
    }
  })
  let start = if dictionary > 0L && dictionary < data {
    dictionary
  } else {
    data
  }
  { codec, start, size, min, max, }
}

///|
/// A Parquet file's footer: the schema's leaves in the columns' order, each row group's row
/// count and chunks, and the `geo` metadata (empty without it).
priv struct Footer {
  leaves : Array[Leaf]
  groups : Array[(Int64, Array[Chunk])]
  geo : String
}

///|
/// The FileMetaData in `bytes`; None if malformed.
fn parquet_footer(bytes : BytesView) -> Footer? {
  let t : Thrift = { b: bytes, pos: 0, bad: false, depth: 0, }
  let leaves = []
  let groups = []
  let mut geo = ""
  // How many more elements belong to the group being read, outermost first.
  let open : Array[Int32] = []
  let names : Array[String] = []
  t.fields((id, kind) => {
    match id {
      2 =>
        t.structs(kind, () => {
          while open.length() > 0 && open[open.length() - 1] == 0 {
            open.pop() |> ignore
          }
          // The root is the one element outside any group; its children are the rows' columns.
          while names.length() > open.length() {
            names.pop() |> ignore
          }
          let (name, leaf, children) = t.schema_element(open.length() == 1)
          if open.length() > 0 {
            open[open.length() - 1] -= 1
          }
          match leaf {
            // The root's own name is no part of a path.
            Some(leaf) => {
              let mut path = name
              for k = names.length() - 1; k >= 1; k = k - 1 {
                path = names[k] + "." + path
              }
              leaves.push({ ..leaf, path, })
            }
            None => {
              open.push(children.max(0))
              names.push(name)
            }
          }
        })
      4 =>
        t.structs(kind, () => {
          let chunks = []
          let mut rows = 0L
          t.fields((id, kind) => {
            match id {
              1 => t.structs(kind, () => chunks.push(t.chunk()))
              3 => rows = t.int()
              _ => t.skip(kind)
            }
          })
          groups.push((rows, chunks))
        })
      5 =>
        t.structs(kind, () => {
          let mut key = ""
          let mut value = ""
          t.fields((id, kind) => {
            match id {
              1 => key = @core.utf8_lossy(t.binary())
              2 => value = @core.utf8_lossy(t.binary())
              _ => t.skip(kind)
            }
          })
          if key == "geo" {
            geo = value
          }
        })
      _ => t.skip(kind)
    }
  })
  guard !t.bad else { return None }
  Some({ leaves, groups, geo, })
}

///|
/// A page's header (parquet.thrift's `PageHeader`): `kind` 0 a data page, 2 a dictionary page,
/// 3 a data page of version 2 (others are passed over); `levels` and `packed` are version 2's:
/// the bytes its levels take, and whether the values after them are compressed.
priv struct Page {
  kind : Int32
  uncompressed : Int32
  compressed : Int32
  values : Int32
  encoding : Int32
  levels : Int32
  packed : Bool
}

///|
/// The page header at `t`'s position.
fn Thrift::page(self : Thrift) -> Page {
  let mut kind = -1
  let mut uncompressed = 0
  let mut compressed = 0
  let mut values = 0
  let mut encoding = 0
  let mut levels = 0
  let mut packed = true
  self.fields((id, k) => {
    match id {
      1 => kind = self.i32()
      2 => uncompressed = self.i32()
      3 => compressed = self.i32()
      5 | 7 if k == T_STRUCT =>
        self.fields((id, k) => {
          match id {
            1 => values = self.i32()
            2 => encoding = self.i32()
            _ => self.skip(k)
          }
        })
      8 if k == T_STRUCT =>
        self.fields((id, k) => {
          match id {
            1 => values = self.i32()
            4 => encoding = self.i32()
            5 => levels += self.i32()
            6 => levels += self.i32()
            7 => packed = k == T_TRUE
            _ => self.skip(k)
          }
        })
      _ => self.skip(k)
    }
  })
  { kind, uncompressed, compressed, values, encoding, levels, packed, }
}

///|
/// The bytes the Snappy block `src` holds, at most `limit`; None if it is malformed or holds
/// more.
fn snappy(src : BytesView, limit : Int32) -> Bytes? {
  let n = src.length()
  let t : Thrift = { b: src, pos: 0, bad: false, depth: 0, }
  let size = t.varint()
  guard !t.bad && size <= limit.to_uint64() else { return None }
  let out = Out::new()
  out.room(size.to_int())
  let mut pos = t.pos
  while pos < n {
    let tag = src[pos].to_int()
    pos += 1
    let mut length = (tag >> 2) + 1
    if (tag & 3) == 0 {
      // A literal: lengths past 60 are in the next one to four bytes.
      if length > 60 {
        let extra = length - 60
        guard pos <= n - extra else { return None }
        length = 0
        for k in 0..<extra {
          length = length | (src[pos + k].to_int() << (k * 8))
        }
        pos += extra
        guard length >= 0 && length < 0x7fffffff else { return None }
        length += 1
      }
      guard length <= n - pos && length <= size.to_int() - out.len else {
        return None
      }
      out.bytes.blit_from_bytesview(out.len, src[pos:pos + length])
      pos += length
      out.len += length
      continue
    }
    let width = match tag & 3 {
      1 => 1
      2 => 2
      _ => 4
    }
    guard pos <= n - width else { return None }
    let mut offset = 0
    for k in 0..<width {
      offset = offset | (src[pos + k].to_int() << (k * 8))
    }
    pos += width
    if width == 1 {
      length = 4 + ((tag >> 2) & 7)
      offset = offset | (tag >> 5 << 8)
    }
    guard offset > 0 && offset <= out.len && length <= size.to_int() - out.len else {
      return None
    }
    for k in 0..<length {
      out.bytes[out.len + k] = out.bytes[out.len - offset + k]
    }
    out.len += length
  }
  guard out.len == size.to_int() else { return None }
  Some(Bytes::makei(out.len, i => out.bytes[i]))
}

///|
/// Bits read from `b`, the lowest of each byte first.
priv struct Bits {
  b : BytesView
  mut pos : Int32
  mut held : UInt64
  mut count : Int32
  mut bad : Bool
}

///|
fn Bits::new(b : BytesView, pos : Int32) -> Bits {
  { b, pos, held: 0UL, count: 0, bad: false, }
}

///|
/// The next `width` bits (at most 64) as a number.
fn Bits::take(self : Bits, width : Int32) -> UInt64 {
  let mut v = 0UL
  let mut got = 0
  while got < width {
    if self.count == 0 {
      guard self.pos < self.b.length() else {
        self.bad = true
        return 0UL
      }
      self.held = self.b[self.pos].to_uint64()
      self.pos += 1
      self.count = 8
    }
    let n = (width - got).min(self.count)
    v = v | ((self.held & ((1UL << n) - 1UL)) << got)
    self.held = self.held >> n
    self.count -= n
    got += n
  }
  v
}

///|
/// `count` values of the RLE and bit-packing hybrid in `b` from `pos`, each of `width` bits
/// (at most 32); None if `b` ends before them.
fn rle_hybrid(
  b : BytesView,
  pos : Int32,
  width : Int32,
  count : Int32,
) -> Array[Int32]? {
  guard width >= 0 && width <= 32 else { return None }
  let out : Array[Int32] = Array(capacity=count)
  let t : Thrift = { b, pos, bad: false, depth: 0, }
  while out.length() < count {
    let head = t.varint()
    guard !t.bad && head <= 0x7fffffffUL else { return None }
    let run = (head >> 1).to_int()
    if (head & 1UL) == 1UL {
      let bits = Bits::new(b, t.pos)
      for
        _ in 0..<(run.to_int64() * 8L)
        .min((count - out.length()).to_int64())
        .to_int() {
        out.push(bits.take(width).to_int())
      }
      guard !bits.bad else { return None }
      let bytes = (run.to_int64() * 8L * width.to_int64() + 7L) / 8L
      guard bytes <= (b.length() - t.pos).to_int64() || out.length() == count else {
        return None
      }
      t.pos = (t.pos.to_int64() + bytes).min(b.length().to_int64()).to_int()
    } else {
      let bytes = (width + 7) / 8
      guard t.pos <= b.length() - bytes else { return None }
      let mut v = 0
      for k in 0..<bytes {
        v = v | (b[t.pos + k].to_int() << (k * 8))
      }
      t.pos += bytes
      for _ in 0..<run.min(count - out.length()) {
        out.push(v)
      }
      // A run of no values would never end.
      guard run > 0 else { return None }
    }
  }
  Some(out)
}

///|
/// The integers DELTA_BINARY_PACKED holds in `b` from `pos`, and where they end; None if
/// malformed or more than `limit`.
fn delta_packed(
  b : BytesView,
  pos : Int32,
  limit : Int32,
) -> (Array[Int64], Int32)? {
  let t : Thrift = { b, pos, bad: false, depth: 0, }
  let block = t.varint()
  let miniblocks = t.varint()
  let total = t.varint()
  let first = t.int()
  guard !t.bad &&
    total <= limit.to_uint64() &&
    miniblocks > 0UL &&
    miniblocks <= 4096UL &&
    block > 0UL &&
    block <= 0x1000000UL &&
    block % miniblocks == 0UL else {
    return None
  }
  let per = (block / miniblocks).to_int()
  let total = total.to_int()
  let out : Array[Int64] = Array(capacity=total)
  if total > 0 {
    out.push(first)
  }
  let mut last = first
  while out.length() < total {
    let min_delta = t.int()
    guard !t.bad && t.pos <= b.length() - miniblocks.to_int() else {
      return None
    }
    let widths = b[t.pos:t.pos + miniblocks.to_int()]
    t.pos += miniblocks.to_int()
    for m in 0..<miniblocks.to_int() {
      guard out.length() < total else { break }
      let width = widths[m].to_int()
      guard width <= 64 else { return None }
      let bits = Bits::new(b, t.pos)
      for _ in 0..<per {
        let delta = bits.take(width).reinterpret_as_int64()
        if out.length() < total {
          last = last + min_delta + delta
          out.push(last)
        }
      }
      guard !bits.bad else { return None }
      t.pos = bits.pos
    }
  }
  Some((out, t.pos))
}

///|
/// The values of a page or dictionary, by their physical type: integers (INT32, INT64),
/// reals (FLOAT, DOUBLE), booleans, or byte strings (BYTE_ARRAY, FIXED_LEN_BYTE_ARRAY, INT96).
priv enum Values {
  Ints(Array[Int64])
  Reals(Array[Double])
  Flags(Array[Bool])
  Blobs(Array[BytesView])
}

///|
fn Values::length(self : Values) -> Int32 {
  match self {
    Ints(v) => v.length()
    Reals(v) => v.length()
    Flags(v) => v.length()
    Blobs(v) => v.length()
  }
}

///|
/// Bytes a value of a fixed-width physical type takes when stored plainly (0 for others).
fn Leaf::width(self : Leaf) -> Int32 {
  match self.physical {
    INT32 | FLOAT => 4
    INT64 | DOUBLE => 8
    INT96 => 12
    FIXED_LEN_BYTE_ARRAY => self.length
    _ => 0
  }
}

///|
/// `count` values of `leaf` stored plainly in `b`; None if `b` is too short.
fn plain_values(leaf : Leaf, b : BytesView, count : Int32) -> Values? {
  let width = leaf.width()
  guard width == 0 ||
    (width > 0 && count.to_int64() * width.to_int64() <= b.length().to_int64()) else {
    return None
  }
  let found = match leaf.physical {
    BOOLEAN => {
      guard (count + 7) / 8 <= b.length() else { return None }
      Flags(
        Array::makei(count, i => ((b[i >> 3].to_int() >> (i & 7)) & 1) == 1),
      )
    }
    INT32 => Ints(Array::makei(count, i => le_i32(b, i * 4).to_int64()))
    INT64 =>
      Ints(Array::makei(count, i => le_u64(b, i * 8).reinterpret_as_int64()))
    FLOAT =>
      Reals(
        Array::makei(count, i => {
          Float::reinterpret_from_int(le_i32(b, i * 4)).to_double()
        }),
      )
    DOUBLE =>
      Reals(Array::makei(count, i => le_u64(b, i * 8).reinterpret_as_double()))
    INT96 | FIXED_LEN_BYTE_ARRAY =>
      Blobs(Array::makei(count, i => b[i * width:(i + 1) * width]))
    BYTE_ARRAY => {
      let out = Array(capacity=count)
      let mut pos = 0
      for _ in 0..<count {
        guard pos <= b.length() - 4 else { return None }
        let n = le_i32(b, pos)
        guard n >= 0 && n <= b.length() - pos - 4 else { return None }
        out.push(b[pos + 4:pos + 4 + n])
        pos += 4 + n
      }
      Blobs(out)
    }
    _ => return None
  }
  Some(found)
}

///|
/// `count` values of `leaf` in `b`, encoded as `encoding` (parquet.thrift's `Encoding`) with
/// the chunk's `dictionary`; why not, as an error.
fn page_values(
  leaf : Leaf,
  b : BytesView,
  count : Int32,
  encoding : Int32,
  dictionary : Values?,
) -> Result[Values, String] {
  let short = Err("a page shorter than its values")
  match encoding {
    PLAIN =>
      match plain_values(leaf, b, count) {
        Some(v) => Ok(v)
        None => short
      }
    PLAIN_DICTIONARY | RLE_DICTIONARY => {
      guard dictionary is Some(dictionary) else {
        return Err("a dictionary-encoded page without its dictionary")
      }
      if count == 0 {
        return Ok(Blobs([]))
      }
      guard b.length() >= 1 &&
        rle_hybrid(b, 1, b[0].to_int(), count) is Some(ids) else {
        return short
      }
      let n = dictionary.length()
      guard ids.all(i => i >= 0 && i < n) else {
        return Err("a dictionary index past its dictionary")
      }
      Ok(
        match dictionary {
          Ints(v) => Ints(ids.map(i => v[i]))
          Reals(v) => Reals(ids.map(i => v[i]))
          Flags(v) => Flags(ids.map(i => v[i]))
          Blobs(v) => Blobs(ids.map(i => v[i]))
        },
      )
    }
    RLE if leaf.physical == BOOLEAN => {
      // Booleans as runs, after a 4-byte length.
      guard b.length() >= 4 && rle_hybrid(b, 4, 1, count) is Some(bits) else {
        return short
      }
      Ok(Flags(bits.map(bit => bit == 1)))
    }
    DELTA_BINARY_PACKED if leaf.physical == INT32 || leaf.physical == INT64 =>
      match delta_packed(b, 0, count) {
        Some((v, _)) if v.length() == count =>
          // INT32 deltas wrap at 32 bits.
          Ok(
            Ints(
              if leaf.physical == INT32 {
                v.map(x => x.to_int().to_int64())
              } else {
                v
              },
            ),
          )
        _ => short
      }
    DELTA_LENGTH_BYTE_ARRAY | DELTA_BYTE_ARRAY if leaf.physical == BYTE_ARRAY => {
      // DELTA_BYTE_ARRAY: the lengths shared with the value before, then the rest of each.
      let mut pos = 0
      let mut prefixes : Array[Int64] = []
      if encoding == DELTA_BYTE_ARRAY {
        guard delta_packed(b, 0, count) is Some((p, end)) && p.length() == count else {
          return short
        }
        prefixes = p
        pos = end
      }
      guard delta_packed(b, pos, count) is Some((lengths, start)) &&
        lengths.length() == count else {
        return short
      }
      let out : Array[BytesView] = Array(capacity=count)
      let mut at = start
      for i, length in lengths {
        guard length >= 0L && length <= (b.length() - at).to_int64() else {
          return short
        }
        let suffix = b[at:at + length.to_int()]
        at += length.to_int()
        if encoding == DELTA_LENGTH_BYTE_ARRAY {
          out.push(suffix)
          continue
        }
        let prefix = prefixes[i]
        guard prefix >= 0L &&
          (i > 0 || prefix == 0L) &&
          (i == 0 || prefix <= out[i - 1].length().to_int64()) else {
          return Err("a shared prefix longer than the value before")
        }
        if prefix == 0L {
          out.push(suffix)
        } else {
          let joined = Bytes::makei(prefix.to_int() + suffix.length(), k => {
            if k < prefix.to_int() {
              out[i - 1][k]
            } else {
              suffix[k - prefix.to_int()]
            }
          })
          out.push(joined[:])
        }
      }
      Ok(Blobs(out))
    }
    BYTE_STREAM_SPLIT if leaf.width() > 0 => {
      // BYTE_STREAM_SPLIT: the values' first bytes, then their second bytes, and so on.
      let width = leaf.width()
      guard count.to_int64() * width.to_int64() <= b.length().to_int64() else {
        return short
      }
      let joined = Bytes::makei(count * width, k => {
        b[k % width * count + k / width]
      })
      match plain_values(leaf, joined[:], count) {
        Some(v) => Ok(v)
        None => short
      }
    }
    _ => Err("values in an encoding that is not read (\{encoding})")
  }
}

///|
/// A big-endian two's complement integer of any length as a number.
fn be_number(b : BytesView) -> Double {
  let negative = b.length() > 0 && b[0].to_int() >= 0x80
  let mut v = 0.0
  for byte in b {
    let digit = if negative { 255 - byte.to_int() } else { byte.to_int() }
    v = v * 256.0 + digit.to_double()
  }
  if negative {
    -(v + 1.0)
  } else {
    v
  }
}

///|
/// `x` times 10 to the power of minus `scale`: one division (or multiplication) by a power
/// of ten, which is exact up to 10^22, so that a decimal reads as its nearest double.
fn scaled(x : Double, scale : Int32) -> Double {
  let mut power = 1.0
  for _ in 0..<scale.abs().min(400) {
    power = power * 10.0
  }
  if scale < 0 {
    x * power
  } else {
    x / power
  }
}

///|
/// Value `i` of `values` as the property value `leaf`'s type makes it.
fn Leaf::prop(self : Leaf, values : Values, i : Int32) -> @geom.Prop {
  let number = (x : Double) => {
    if x.is_nan() {
      @geom.Prop::Null
    } else {
      Num(x)
    }
  }
  match (values, self.logical) {
    (Flags(v), _) => Bool(v[i])
    (Reals(v), _) => number(v[i])
    (Ints(v), Date) => Str(iso_date(v[i]))
    (Ints(v), Timestamp(unit, utc)) => {
      let ms = match unit {
        1 => v[i]
        2 => floor_div(v[i], 1000L).0
        _ => floor_div(v[i], 1000000L).0
      }
      Str(iso_time(ms, utc))
    }
    (Ints(v), Decimal(scale)) => number(scaled(v[i].to_double(), scale))
    (Ints(v), Integer(bits, false)) =>
      if bits == 64 {
        Num(v[i].reinterpret_as_uint64().to_double())
      } else if self.physical == INT32 {
        Num(v[i].to_int().reinterpret_as_uint().to_double())
      } else {
        Num(v[i].to_double())
      }
    (Ints(v), _) => Num(v[i].to_double())
    (Blobs(v), Text) => Str(@core.utf8_lossy(v[i]))
    (Blobs(v), Decimal(scale)) => number(scaled(be_number(v[i]), scale))
    (Blobs(v), Float16) if v[i].length() == 2 =>
      number(half_float(v[i][0].to_int() | (v[i][1].to_int() << 8)))
    // INT96: nanoseconds of the day, then the Julian day (2440588 is 1970-01-01).
    (Blobs(v), Plain) if self.physical == 3 => {
      let nanos = le_u64(v[i], 0).reinterpret_as_int64()
      let day = le_i32(v[i], 8).to_int64() - 2440588L
      Str(iso_time(day * 86400000L + floor_div(nanos, 1000000L).0, false))
    }
    _ => Null
  }
}

///|
/// Whether a flat column of `leaf`'s type becomes a property column.
fn Leaf::is_property(self : Leaf) -> Bool {
  match (self.physical, self.logical) {
    (0 | 1 | 2 | 4 | 5, Other) => false
    (0 | 1 | 2 | 4 | 5, _) => true
    (3, Plain) => true
    (6, Text | Decimal(_)) => true
    (7, Decimal(_) | Float16) => true
    _ => false
  }
}

///|
/// Bytes of the file placed in the input: where they are in the file, where in the input, and
/// the bytes.
priv struct Segment {
  offset : Int64
  base : Int32
  bytes : BytesView
}

///|
/// A read in progress: the parts of the file at hand, the pages the host inflated (GZIP, ZSTD)
/// in the order they are met, and what one input may inflate to in all.
priv struct ParquetReader {
  segments : ArrayView[Segment]
  inflated : ArrayView[BytesView]
  mut next_inflated : Int32
  mut budget : Int64
  // Where each page the host must inflate is and how long, when only listing them.
  wanted : Array[Int32]?
}

///|
/// The bytes of a page body of `size` bytes inflated, compressed with `codec`; why not, as an
/// error.
fn ParquetReader::inflate(
  self : ParquetReader,
  codec : Int32,
  body : BytesView,
  size : Int32,
) -> Result[BytesView, String] {
  guard size >= 0 && size.to_int64() <= self.budget else {
    return Err("pages that inflate past \{MAX_ARROW_INFLATED} bytes")
  }
  self.budget -= size.to_int64()
  match codec {
    UNCOMPRESSED => Ok(body)
    SNAPPY =>
      match snappy(body, size) {
        Some(bytes) => Ok(bytes[:])
        None => Err("a malformed Snappy block")
      }
    GZIP | ZSTD => {
      guard self.next_inflated < self.inflated.length() else {
        return Err("a GZIP or ZSTD page that was not inflated")
      }
      self.next_inflated += 1
      let bytes = self.inflated[self.next_inflated - 1]
      guard bytes.length() == size else {
        return Err("a page of another size than its header says")
      }
      Ok(bytes)
    }
    _ => Err("pages compressed with a codec that is not read (\{codec})")
  }
}

///|
/// The cells of `chunk` (a column of `leaf`) in a row group of `rows` rows: a value per row,
/// None where it is null. When only listing the pages to inflate, an empty array.
fn ParquetReader::column(
  self : ParquetReader,
  leaf : Leaf,
  chunk : Chunk,
  rows : Int32,
) -> Result[(Values, Array[Int32]), String] {
  // The segment that holds the whole chunk; positions are in its bytes from here on.
  let mut held : Segment? = None
  for s in self.segments {
    if chunk.start >= s.offset &&
      chunk.size <= s.offset + s.bytes.length().to_int64() - chunk.start {
      held = Some(s)
    }
  }
  guard chunk.start >= 4L && chunk.size >= 0L && held is Some(segment) else {
    return Err("a column chunk outside the bytes read of the file")
  }
  let bytes = segment.bytes
  let mut pos = (chunk.start - segment.offset).to_int()
  let end = pos + chunk.size.to_int()
  let mut dictionary : Values? = None
  // Every value of the chunk, and for each row its value's place (-1 for null).
  let mut all : Values? = None
  let places : Array[Int32] = Array(capacity=rows)
  let mut count = 0
  while pos < end && places.length() < rows {
    let t : Thrift = { b: bytes[pos:end], pos: 0, bad: false, depth: 0, }
    let page = t.page()
    guard !t.bad &&
      page.compressed >= 0 &&
      page.compressed <= end - pos - t.pos &&
      page.uncompressed >= 0 &&
      page.values >= 0 else {
      return Err("a malformed page header")
    }
    let body = bytes[pos + t.pos:pos + t.pos + page.compressed]
    let body_at = segment.base + pos + t.pos
    pos += t.pos + page.compressed
    guard page.kind == DATA_PAGE ||
      page.kind == DICTIONARY_PAGE ||
      page.kind == DATA_PAGE_V2 else {
      continue
    }
    // Version 2 keeps its levels before the values, never compressed.
    let levels = if page.kind == DATA_PAGE_V2 { page.levels } else { 0 }
    guard levels >= 0 && levels <= body.length() && levels <= page.uncompressed else {
      return Err("a malformed page header")
    }
    let packed = chunk.codec != UNCOMPRESSED &&
      (page.kind != DATA_PAGE_V2 || page.packed)
    if self.wanted is Some(wanted) {
      if packed && (chunk.codec == GZIP || chunk.codec == ZSTD) {
        // Charged here too: the host allocates what a page says it inflates to.
        let size = (page.uncompressed - levels).to_int64()
        guard size <= self.budget else {
          return Err("pages that inflate past \{MAX_ARROW_INFLATED} bytes")
        }
        self.budget -= size
        wanted.push(body_at + levels)
        wanted.push(body.length() - levels)
        wanted.push(page.uncompressed - levels)
        wanted.push(chunk.codec)
      }
      if page.kind != DICTIONARY_PAGE {
        count += page.values
        if count >= rows {
          break
        }
      }
      continue
    }
    let data = if packed {
      match
        self.inflate(chunk.codec, body[levels:], page.uncompressed - levels) {
        Ok(data) => data
        Err(why) => return Err(why)
      }
    } else {
      body[levels:]
    }
    if page.kind == DICTIONARY_PAGE {
      guard plain_values(leaf, data, page.values) is Some(values) else {
        return Err("a dictionary page shorter than its values")
      }
      dictionary = Some(values)
      continue
    }
    guard page.values <= rows - places.length() else {
      return Err("a column with more values than its row group has rows")
    }
    // Which rows hold a value: definition levels of one bit for a column that may be null.
    let mut values_at = 0
    let defined = if !leaf.optional {
      None
    } else if page.kind == DATA_PAGE_V2 {
      rle_hybrid(body, 0, 1, page.values)
    } else {
      guard data.length() >= 4 else { return Err("a page without its levels") }
      let length = le_i32(data, 0)
      guard length >= 0 && length <= data.length() - 4 else {
        return Err("a page without its levels")
      }
      values_at = 4 + length
      rle_hybrid(data[:4 + length], 4, 1, page.values)
    }
    guard !leaf.optional || defined is Some(_) else {
      return Err("malformed definition levels")
    }
    let present = match defined {
      Some(levels) => levels.fold(init=0, (sum, level) => sum + level)
      None => page.values
    }
    let values = match
      page_values(leaf, data[values_at:], present, page.encoding, dictionary) {
      Ok(values) => values
      Err(why) => return Err(why)
    }
    guard values.length() == present else {
      return Err("a page with another count of values than its levels say")
    }
    let before = match all {
      Some(v) => v.length()
      None => 0
    }
    let mut k = before
    for i in 0..<page.values {
      if defined is Some(levels) && levels[i] == 0 {
        places.push(-1)
      } else {
        places.push(k)
        k += 1
      }
    }
    all = Some(
      match (all, values) {
        (None, v) => v
        (Some(Ints(a)), Ints(b)) => Ints(a + b)
        (Some(Reals(a)), Reals(b)) => Reals(a + b)
        (Some(Flags(a)), Flags(b)) => Flags(a + b)
        (Some(Blobs(a)), Blobs(b)) => Blobs(a + b)
        (Some(a), _) => a
      },
    )
  }
  if self.wanted is Some(_) {
    return Ok((Blobs([]), []))
  }
  guard places.length() == rows else {
    return Err(
      "column \{leaf.name} has another count of values than its row group has rows",
    )
  }
  Ok((all.unwrap_or(Blobs([])), places))
}

///|
/// A Parquet file's footer, opened: its schema and row groups, which column holds the geometry,
/// and what `plan` chose to read (every row group and column until it is called).
struct ParquetFile {
  footer : Footer
  geometry : Int32?
  mut groups : Array[Int32]
  mut kept : Array[Bool]
  mut bbox : (Double, Double, Double, Double)?
}

///|
fn parquet_error(at : Int32, message : String) -> ReadError {
  Invalid(format="Parquet", pos=at, message)
}

///|
/// Opens the footer `metadata` (the FileMetaData before a file's last 8 bytes).
pub fn parquet_open(metadata : BytesView) -> ParquetFile raise ReadError {
  guard parquet_footer(metadata) is Some(footer) else {
    raise parquet_error(0, "a malformed footer")
  }
  let leaves = footer.leaves
  for group in footer.groups {
    guard group.0 >= 0L &&
      group.0 <= 0x7fffffffL &&
      group.1.length() == leaves.length() else {
      raise parquet_error(
        0, "a row group with another count of columns than the schema",
      )
    }
  }
  let primary = json_string_after(footer.geo, "primary_column")
  let binary = (named : (Leaf) -> Bool) => {
    leaves.search_by(l => {
      l.flat && l.physical == 6 && l.logical is (Plain | Geometry) && named(l)
    })
  }
  let conventional = ["geometry", "geom", "wkb_geometry"]
  let geometry = match binary(l => l.logical is Geometry) {
    Some(g) => Some(g)
    None =>
      match binary(l => l.name == primary) {
        Some(g) => Some(g)
        None => binary(l => conventional.contains(l.name.to_lower()))
      }
  }
  // GeoParquet's GeoArrow encodings nest lists, which are not read.
  if geometry is None && primary != "" {
    raise parquet_error(
      0,
      "the geometry column \{primary} is not WKB, which is all that is read",
    )
  }
  let file : ParquetFile = {
    footer,
    geometry,
    groups: [],
    kept: [],
    bbox: None,
  }
  file.plan() |> ignore
  file
}

///|
/// The geometry column's name (empty without one) and the `geo` metadata.
pub fn ParquetFile::info(self : ParquetFile) -> ArrowInfo {
  let geometry = match self.geometry {
    Some(g) => self.footer.leaves[g].name
    None => ""
  }
  { geometry, extension: "", geo: self.footer.geo, }
}

///|
/// A fixed-width statistic as a number: NaN unless `stored` is a FLOAT's or a DOUBLE's bytes.
fn Leaf::statistic(self : Leaf, stored : BytesView) -> Double {
  match (self.physical, stored.length()) {
    (4, 4) => Float::reinterpret_from_int(le_i32(stored, 0)).to_double()
    (5, 8) => le_u64(stored, 0).reinterpret_as_double()
    _ => @double.not_a_number
  }
}

///|
/// Chooses what `read` takes (docs/dev/FORMATS.md "Parquet"): the property `columns` named, the
/// rows whose geometry's box meets `bbox`, and no row group whose `covering` statistics lie
/// outside it. Gives the byte ranges of the file `read` needs, a position and a length each.
pub fn ParquetFile::plan(
  self : ParquetFile,
  bbox? : (Double, Double, Double, Double),
  columns? : ArrayView[String],
  covering~ : ArrayView[String] = [],
) -> Array[(Int64, Int64)] raise ReadError {
  let leaves = self.footer.leaves
  let property = (c : Int32) => {
    leaves[c].flat && leaves[c].is_property() && self.geometry != Some(c)
  }
  if columns is Some(names) {
    for name in names {
      guard leaves.search_by(l => l.name == name) is Some(c) && property(c) else {
        raise parquet_error(0, "no column \{name}")
      }
    }
  }
  self.kept = Array::makei(leaves.length(), c => {
    self.geometry == Some(c) ||
    (
      property(c) &&
      (match columns {
        Some(names) => names.contains(leaves[c].name)
        None => true
      })
    )
  })
  self.bbox = bbox
  let boxes = covering.map(path => leaves.search_by(l => l.path == path))
  let ranges = []
  self.groups = []
  for g, group in self.footer.groups {
    let chunks = group.1
    if bbox is Some((x0, y0, x1, y1)) &&
      boxes is [Some(xmin), Some(ymin), Some(xmax), Some(ymax)] {
      // NaN (no statistics) compares false: the group is kept.
      let outside = leaves[xmin].statistic(chunks[xmin].min) > x1 ||
        leaves[ymin].statistic(chunks[ymin].min) > y1 ||
        leaves[xmax].statistic(chunks[xmax].max) < x0 ||
        leaves[ymax].statistic(chunks[ymax].max) < y0
      guard !outside else { continue }
    }
    guard group.0 > 0L else { continue }
    self.groups.push(g)
    for c, chunk in chunks {
      if self.kept[c] {
        guard chunk.start >= 4L && chunk.size >= 0L else {
          raise parquet_error(0, "a column chunk outside the file")
        }
        ranges.push((chunk.start, chunk.size))
      }
    }
  }
  ranges
}

///|
/// `read` over `segments` with the pages the host inflated, or, with `wanted`, only listing
/// the pages it must inflate.
fn ParquetFile::table(
  self : ParquetFile,
  segments : ArrayView[Segment],
  inflated : ArrayView[BytesView],
  wanted : Array[Int32]?,
  max_points : Int32,
  max_cells : Int32,
) -> @geom.Table raise ReadError {
  let leaves = self.footer.leaves
  let geometry = self.geometry
  let reader : ParquetReader = {
    segments,
    inflated,
    next_inflated: 0,
    budget: MAX_ARROW_INFLATED,
    wanted,
  }
  let out = @geom.TableBuilder::new()
  let wkb = Wkb::new(b"", max_points)
  let none = Shapes::new()
  let mut used = 0
  let props = []
  for g in self.groups {
    let (rows, chunks) = self.footer.groups[g]
    let rows = rows.to_int()
    let columns = []
    for c, leaf in leaves {
      if !self.kept[c] {
        columns.push(None)
        continue
      }
      match reader.column(leaf, chunks[c], rows) {
        Ok(column) => columns.push(Some(column))
        Err(why) => raise parquet_error(0, "column \{leaf.name}: \{why}")
      }
    }
    guard wanted is None else { continue }
    for i in 0..<rows {
      let mut shapes = none
      if geometry is Some(g) &&
        columns[g] is Some((Blobs(cells), places)) &&
        places[i] >= 0 {
        guard wkb.cell(cells[places[i]]) else {
          raise parquet_error(0, "malformed WKB in a row")
        }
        used += wkb.shapes.points()
        guard used <= max_points else {
          raise parquet_error(0, "more than \{max_points} points")
        }
        shapes = wkb.shapes
      }
      if self.bbox is Some(bbox) && !shapes.meets(bbox) {
        continue
      }
      props.clear()
      for c, column in columns {
        if column is Some((values, places)) && geometry != Some(c) {
          props.push(
            (
              leaves[c].name,
              if places[i] < 0 {
                @geom.Prop::Null
              } else {
                leaves[c].prop(values, places[i])
              },
            ),
          )
        }
      }
      shapes.emit(out, props, None, max_cells~)
      if property_limit(out, max_cells) is Some(why) {
        raise parquet_error(0, why)
      }
    }
  }
  out.finish()
}

///|
/// Whether the box of the shapes' points meets `bbox` (never without a point).
fn Shapes::meets(
  self : Shapes,
  bbox : (Double, Double, Double, Double),
) -> Bool {
  let c = self.coords
  guard c.length() >= 2 else { return false }
  let mut x0 = c[0]
  let mut x1 = c[0]
  let mut y0 = c[1]
  let mut y1 = c[1]
  for i = 2; i + 1 < c.length(); i = i + 2 {
    x0 = x0.min(c[i])
    x1 = x1.max(c[i])
    y0 = y0.min(c[i + 1])
    y1 = y1.max(c[i + 1])
  }
  x0 <= bbox.2 && x1 >= bbox.0 && y0 <= bbox.3 && y1 >= bbox.1
}

///|
/// The parts of the file given as (their position in the file, their position in the host's
/// input, their bytes) as segments.
fn segments_of(parts : ArrayView[(Int64, Int32, BytesView)]) -> Array[Segment] {
  parts.map(p => { offset: p.0, base: p.1, bytes: p.2, })
}

///|
/// Reads the rows `plan` chose from `parts` of the file (each its position in the file, its
/// position in the host's input and its bytes), which must hold every range `plan` gave. GZIP
/// and ZSTD pages come in `inflated`, in `packed_pages`' order.
pub fn ParquetFile::read(
  self : ParquetFile,
  parts : ArrayView[(Int64, Int32, BytesView)],
  inflated~ : ArrayView[BytesView] = [],
) -> @geom.Table raise ReadError {
  self.table(
    segments_of(parts),
    inflated,
    None,
    @geom.MAX_TABLE_POINTS,
    @geom.MAX_TABLE_CELLS,
  )
}

///|
/// The GZIP members and ZSTD frames `read` needs inflated: for each, in the order it takes
/// them, its position in the host's input, its length, the length it inflates to and its codec
/// (2 GZIP, 6 ZSTD).
pub fn ParquetFile::packed_pages(
  self : ParquetFile,
  parts : ArrayView[(Int64, Int32, BytesView)],
) -> Array[Int32] raise ReadError {
  let wanted = []
  self.table(
    segments_of(parts),
    [],
    Some(wanted),
    @geom.MAX_TABLE_POINTS,
    @geom.MAX_TABLE_CELLS,
  )
  |> ignore
  wanted
}

///|
/// The FileMetaData of the whole file `bytes`, and where it starts.
fn metadata_of(bytes : BytesView) -> (BytesView, Int32) raise ReadError {
  let n = bytes.length()
  guard n >= 12 && bytes[0:4] == parquet_magic && bytes[n - 4:] == parquet_magic else {
    raise parquet_error(0, "not a Parquet file")
  }
  let size = le_i32(bytes, n - 8)
  guard size > 0 && size <= n - 12 else {
    raise parquet_error(n - 8, "a footer past the start of the file")
  }
  (bytes[n - 8 - size:n - 8], n - 8 - size)
}

///|
/// Reads the whole Parquet file `bytes` (docs/dev/FORMATS.md "Parquet"): `parquet_open` of its
/// footer and `ParquetFile::read` of every row; `inflated` as `read`'s.
pub fn read_parquet(
  bytes : BytesView,
  inflated~ : ArrayView[BytesView] = [],
) -> (@geom.Table, ArrowInfo) raise ReadError {
  let file = parquet_open(metadata_of(bytes).0) catch {
    Invalid(pos~, message, ..) =>
      raise parquet_error(pos + metadata_of(bytes).1, message)
  }
  (file.read([(0L, 0, bytes)], inflated~), file.info())
}

///|
/// `ParquetFile::packed_pages` of the whole file `bytes`.
pub fn parquet_packed_pages(bytes : BytesView) -> Array[Int32] raise ReadError {
  parquet_open(metadata_of(bytes).0).packed_pages([(0L, 0, bytes)])
}
