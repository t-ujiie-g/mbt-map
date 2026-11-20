///|
test "iso_date and iso_time write the proleptic Gregorian calendar" {
  assert_eq(iso_date(0L), "1970-01-01")
  assert_eq(iso_date(-1L), "1969-12-31")
  assert_eq(iso_date(19782L), "2024-02-29")
  assert_eq(iso_date(-719528L), "0000-01-01")
  assert_eq(iso_date(-719529L), "-0001-12-31")
  assert_eq(iso_date(2932896L), "9999-12-31")
  assert_eq(iso_time(0L, false), "1970-01-01T00:00:00")
  assert_eq(iso_time(1709210096789L, true), "2024-02-29T12:34:56.789Z")
  assert_eq(iso_time(-1L, false), "1969-12-31T23:59:59.999")
  assert_eq(iso_time(-86400000L, true), "1969-12-31T00:00:00Z")
}

///|
test "half_float reads zeros, subnormals, numbers, infinities and NaN" {
  assert_eq(half_float(0x0000), 0.0)
  assert_eq(half_float(0x3c00), 1.0)
  assert_eq(half_float(0xc000), -2.0)
  assert_eq(half_float(0x3555), 0.333251953125)
  assert_eq(half_float(0x0001), 5.960464477539063e-8)
  assert_eq(half_float(0x7bff), 65504.0)
  assert_eq(half_float(0x7c00), @double.infinity)
  assert_eq(half_float(0xfc00), @double.neg_infinity)
  assert_true(half_float(0x7e00).is_nan())
}

///|
test "number_at reads integers of every width and decimals by their scale" {
  let bytes : Bytes = b"\xff\xfe\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff"
  assert_eq(number_at(Int(8, true), bytes[:], 0), -1.0)
  assert_eq(number_at(Int(8, false), bytes[:], 0), 255.0)
  assert_eq(number_at(Int(16, true), bytes[:], 0), -257.0)
  assert_eq(number_at(Int(16, false), bytes[:], 0), 65279.0)
  assert_eq(number_at(Int(32, true), bytes[:], 0), -257.0)
  assert_eq(number_at(Int(32, false), bytes[:], 0), 4294967039.0)
  assert_eq(number_at(Int(64, true), bytes[:], 0), -257.0)
  assert_eq(number_at(Int(64, false), bytes[:], 0), 18446744073709551359.0)
  // -257 as a 128-bit decimal of scale 2, and 12345 of scale -1.
  assert_eq(number_at(Decimal(128, 2), bytes[:], 0), -2.57)
  let small : Bytes = b"\x39\x30\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
  assert_eq(number_at(Decimal(128, -1), small[:], 0), 123450.0)
  assert_eq(number_at(Decimal(128, 3), small[:], 0), 12.345)
  assert_true(number_at(Boolean, small[:], 0).is_nan())
}

///|
test "json_string_after finds the string a key holds" {
  let geo = "{\"version\":\"1.0.0\",\"primary_column\" : \"geom\",\"columns\":{}}"
  assert_eq(json_string_after(geo, "primary_column"), "geom")
  assert_eq(json_string_after(geo, "version"), "1.0.0")
  assert_eq(json_string_after(geo, "nope"), "")
  assert_eq(json_string_after("{\"primary_column\":", "primary_column"), "")
  assert_eq(json_string_after("", "primary_column"), "")
}

///|
test "encoding_of and native_type name GeoArrow's types" {
  assert_true(encoding_of("geoarrow.wkb") is Some(Wkb))
  assert_true(
    encoding_of("geoarrow.multipolygon") is Some(Native(3, MultiPolygon)),
  )
  assert_true(encoding_of("geoarrow.linestring") is Some(Native(1, LineString)))
  assert_true(encoding_of("geoarrow.wkt") is None)
  assert_true(encoding_of("") is None)
  assert_eq(native_type([Point]), Some(("point", 0)))
  assert_eq(native_type([MultiPolygon, Polygon]), Some(("multipolygon", 3)))
  assert_eq(native_type([Polygon]), Some(("polygon", 2)))
  assert_eq(native_type([LineString, Polygon]), None)
}

///|
/// Whether `bytes` read as a table of at most `max_points` points.
fn arrow_reads(bytes : Bytes, max_points : Int32) -> Bool {
  try arrow_table(bytes[:], max_points, 100) catch {
    _ => false
  } noraise {
    _ => true
  }
}

///|
test "a batch whose buffers lie outside its body, or are too short, fails without reading them" {
  let b = @geom.TableBuilder::new()
  b.prop("n", Num(1.5))
  b.end_feature(NoGeometry)
  let bytes = write_arrow(b.finish()).unwrap().to_array()
  // Every byte changed in turn: the read ends in a table or an error.
  for i in 0..<bytes.length() {
    let damaged = bytes.copy()
    damaged[i] = (damaged[i].to_int() ^ 0x80).to_byte()
    ignore(arrow_reads(Bytes::from_array(damaged), 100))
  }
  // More points than the reader may take.
  let points = @geom.TableBuilder::new()
  for i in 0..<3 {
    points.point(i.to_double(), 0.0)
    points.end_ring()
    points.end_part()
    points.end_feature(Point)
  }
  let three = points.finish()
  for native in [false, true] {
    let many = write_arrow(three, native~).unwrap()
    assert_false(arrow_reads(many, 2))
    assert_true(arrow_reads(many, 3))
  }
}

///|
test "rows are counted where a table has no property to count cells by" {
  let points = @geom.TableBuilder::new()
  for i in 0..<3 {
    points.point(i.to_double(), 0.0)
    points.end_ring()
    points.end_part()
    points.end_feature(Point)
  }
  let bytes = write_arrow(points.finish()).unwrap()
  let reads = (max_cells : Int32) => {
    try arrow_table(bytes[:], 100, max_cells) catch {
      _ => false
    } noraise {
      _ => true
    }
  }
  assert_false(reads(2))
  assert_true(reads(3))
}

///|
test "Validity::has reads a row past its bitmap as null" {
  let valid : Validity = { bits: b"\x01", }
  assert_true(valid.has(0))
  assert_false(valid.has(1))
  assert_false(valid.has(8))
  assert_true({ bits: b"", }.has(8))
}

///|
test "Flat::string counts what it decodes, however often one string is pointed to" {
  // A table with one string field: its vtable, the table, then "hi".
  let b : Bytes = b"\x06\x00\x08\x00\x04\x00\x06\x00\x00\x00\x04\x00\x00\x00\x02\x00\x00\x00hi"
  let flat : Flat = { b: b[:], bad: false, text: 0, }
  assert_eq(flat.string(6, 0), "hi")
  assert_eq(flat.text, 2)
  flat.text = MAX_ARROW_TEXT - 1
  assert_eq(flat.string(6, 0), "")
  assert_true(flat.bad)
}
