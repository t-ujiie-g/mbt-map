///|
/// Rows of every kind in `kinds`' order, one without geometry, with a column of each type.
fn arrow_sample(kinds : Array[@geom.GeomKind]) -> @geom.Table {
  let b = @geom.TableBuilder::new()
  for i, kind in kinds {
    let x = i.to_double()
    let ring = (n : Int32) => {
      for k in 0..<n {
        b.point(x + k.to_double(), 10.0 - k.to_double())
      }
      b.end_ring()
    }
    match kind {
      Point => {
        ring(1)
        b.end_part()
      }
      MultiPoint | LineString => {
        ring(3)
        b.end_part()
      }
      MultiLineString =>
        for _ in 0..<2 {
          ring(2)
          b.end_part()
        }
      Polygon => {
        ring(4)
        ring(4)
        b.end_part()
      }
      MultiPolygon =>
        for _ in 0..<2 {
          ring(4)
          b.end_part()
        }
      NoGeometry => ()
    }
    b.prop("name", Str("row \{i}"))
    if i != 1 {
      b.prop("whole", Num(i.to_double() - 1.0))
      b.prop("real", Num(i.to_double() + 0.5))
      b.prop("flag", Bool(i % 2 == 0))
    }
    b.prop("mixed", if i % 2 == 0 { Num(1.5) } else { Bool(true) })
    b.prop("nothing", Null)
    b.end_feature(kind)
  }
  b.finish()
}

///|
test "write_arrow and read_arrow carry every geometry kind as WKB, in a stream and a file" {
  let t = arrow_sample([
    Point,
    MultiPoint,
    LineString,
    MultiLineString,
    Polygon,
    MultiPolygon,
    NoGeometry,
  ])
  for file in [false, true] {
    let bytes = @formats.write_arrow(t, file~).unwrap()
    assert_eq(bytes[0:6] == b"ARROW1", file)
    let (back, info) = @formats.read_arrow(bytes[:])
    // Nothing for the host to inflate in what is not compressed.
    assert_eq(@formats.arrow_packed_buffers(bytes[:]), [])
    assert_eq(info.geometry, "geometry")
    assert_true(info.extension.contains("OGC:CRS84"))
    assert_true(info.geo.contains("\"primary_column\":\"geometry\""))
    assert_eq(back.kinds, t.kinds)
    assert_eq(back.coords, t.coords)
    assert_eq(back.part_ends, t.part_ends)
    assert_eq(back.columns.map(c => c.name), [
      "name", "whole", "real", "flag", "mixed", "nothing",
    ])
    // A missing cell comes back as null, a mixed column as text.
    assert_eq(back.column("whole").unwrap().values[1], Some(Null))
    assert_eq(back.column("whole").unwrap().values[2], Some(Num(1.0)))
    assert_eq(back.column("real").unwrap().values[0], Some(Num(0.5)))
    assert_eq(back.column("flag").unwrap().values[2], Some(Bool(true)))
    assert_eq(back.column("mixed").unwrap().values[0:2].to_owned(), [
      Some(Str("1.5")),
      Some(Str("true")),
    ])
    assert_eq(back.column("nothing").unwrap().values[0], Some(Null))
    assert_eq(back.column("name").unwrap().values[6], Some(Str("row 6")))
  }
}

///|
test "write_arrow's native geometry is GeoArrow's type for the rows' kind, a kind with its multi as the multi" {
  let cases : Array[(Array[@geom.GeomKind], Array[@geom.GeomKind])] = [
    ([Point, NoGeometry, Point], [Point, NoGeometry, Point]),
    ([Point, MultiPoint], [MultiPoint, MultiPoint]),
    ([LineString, LineString], [LineString, LineString]),
    ([MultiLineString, LineString], [MultiLineString, MultiLineString]),
    ([Polygon, NoGeometry], [Polygon, NoGeometry]),
    ([Polygon, MultiPolygon], [MultiPolygon, MultiPolygon]),
  ]
  for c in cases {
    let t = arrow_sample(c.0)
    let bytes = @formats.write_arrow(t, native=true, file=true).unwrap()
    let (back, _) = @formats.read_arrow(bytes[:])
    assert_eq(back.kinds, c.1)
    assert_eq(back.coords, t.coords)
    assert_eq(back.part_ends, t.part_ends)
    assert_eq(back.ring_ends, t.ring_ends)
    assert_eq(back.point_ends, t.point_ends)
  }
  assert_true(
    @formats.write_arrow(arrow_sample([Point, Polygon]), native=true)
    is Err("rows of mixed geometry types have no GeoArrow type: write WKB"),
  )
  assert_true(
    @formats.write_arrow(arrow_sample([MultiPoint, LineString]), native=true)
    is Err(_),
  )
}

///|
test "a table without geometry has no geometry column, and an empty one reads back empty" {
  let t = arrow_sample([NoGeometry, NoGeometry])
  let (back, info) = @formats.read_arrow(@formats.write_arrow(t).unwrap()[:])
  assert_eq(info.geometry, "")
  assert_eq(back.length(), 2)
  assert_true(back.kinds is [NoGeometry, NoGeometry])
  let empty = @formats.write_arrow(@geom.Table::new(), file=true).unwrap()
  assert_eq(@formats.read_arrow(empty[:]).0.length(), 0)
}

///|
test "a geometry column is named apart from a property called geometry" {
  let b = @geom.TableBuilder::new()
  b.point(1.0, 2.0)
  b.end_ring()
  b.end_part()
  b.prop("geometry", Str("mine"))
  b.end_feature(Point)
  let (back, info) = @formats.read_arrow(
    @formats.write_arrow(b.finish()).unwrap()[:],
  )
  assert_eq(info.geometry, "geometry_")
  assert_eq(back.column("geometry").unwrap().values, [Some(Str("mine"))])
  assert_eq(back.coords, [1.0, 2.0])
}

///|
test "read_arrow refuses what is no Arrow data, by where and why" {
  let message = (bytes : Bytes) => {
    try @formats.read_arrow(bytes[:]) catch {
      e => e.message()
    } noraise {
      _ => ""
    }
  }
  assert_eq(message(b""), "malformed Arrow at 0: no schema")
  assert_eq(
    message(b"\xff\xff\xff\xff\x10\x00\x00\x00"),
    "malformed Arrow at 8: a message past the end of the data",
  )
  let good = @formats.write_arrow(arrow_sample([Point, Polygon])).unwrap()
  // Cut anywhere, the stream is refused or read up to its last whole message.
  for cut in 0..<good.length() {
    ignore(message(good[:cut].to_owned()))
  }
  // A record batch before any schema.
  let file = @formats.write_arrow(arrow_sample([Point]), file=true).unwrap()
  assert_true(message(file[:file.length() - 7].to_owned()) != "")
}
