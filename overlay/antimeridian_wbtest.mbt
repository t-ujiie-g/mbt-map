///|
/// Feature `f`'s area in square kilometers on a sphere of the earth's mean
/// radius, its edges straight in longitude and the sine of latitude.
fn sphere_area(t : @geom.Table, f : Int32) -> Double {
  let mut a = 0.0
  let (p0, p1) = t.parts(f)
  for p in p0..<p1 {
    let (r0, r1) = t.rings(p)
    for r in r0..<r1 {
      let (i0, i1) = t.points(r)
      for i in i0..<(i1 - 1) {
        a -= radians(t.coords[i * 2 + 2] - t.coords[i * 2]) *
          (
            @math.sin(radians(t.coords[i * 2 + 1])) +
            @math.sin(radians(t.coords[i * 2 + 3]))
          )
      }
    }
  }
  a / 2.0 * 6371.0088 * 6371.0088
}

///|
fn part_count(t : @geom.Table, f : Int32) -> Int32 {
  let (p0, p1) = t.parts(f)
  p1 - p0
}

///|
fn point(lon : Double, lat : Double) -> @geom.Table {
  table([(Point, [[(lon, lat)]], "a")])
}

///|
/// Whether `a` and `b` agree to one part in a million.
fn close(a : Double, b : Double) -> Bool {
  (a - b).abs() <= b.abs() * 1.0e-6
}

///|
test "may_wrap lets through only small features clear of ±180° and the poles" {
  assert_false(may_wrap(139.7, 35.7, 139.7, 35.7, 1000.0))
  assert_false(may_wrap(139.0, 35.0, 141.0, 36.0, -5000.0))
  assert_true(may_wrap(179.9, 35.0, 179.9, 35.0, 100000.0))
  assert_true(may_wrap(-179.9, 35.0, -179.9, 35.0, 100000.0))
  assert_true(may_wrap(190.0, 35.0, 190.0, 35.0, 1.0))
  assert_true(may_wrap(0.0, 89.5, 0.0, 89.5, 1.0))
  assert_true(may_wrap(0.0, -89.5, 0.0, -89.5, 1.0))
  assert_true(may_wrap(0.0, 0.0, 30.0, 0.0, 1.0))
  assert_true(may_wrap(0.0, 0.0, 0.0, 0.0, 1.0e7))
}

///|
test "lift follows a ring the short way round and counts its turns around the axis" {
  let to_xy = (p : @clipper.Point64) => (p.x.to_double(), p.y.to_double())
  let degree = (p : @clipper.Point64) => p.x / 10000000L
  let across = lift(
    [{ x: 170, y: 0, }, { x: -170, y: 0, }, { x: -170, y: 10, }],
    to_xy,
  )
  assert_eq(across.path.map(degree), [170, 190, 190])
  assert_eq((across.turns, across.wraps), (0, true))
  let east = lift(
    [{ x: 0, y: 80, }, { x: 120, y: 80, }, { x: -120, y: 80, }],
    to_xy,
  )
  assert_eq(east.path.map(degree), [0, 120, 240])
  assert_eq((east.turns, east.wraps), (1, true))
  let west = lift(
    [{ x: 0, y: 80, }, { x: -120, y: 80, }, { x: 120, y: 80, }],
    to_xy,
  )
  assert_eq(west.turns, -1)
  let plain = lift(
    [{ x: 0, y: 0, }, { x: 10, y: 0, }, { x: 10, y: 10, }],
    to_xy,
  )
  assert_eq((plain.turns, plain.wraps), (0, false))
  assert_eq(lift([], to_xy).path.length(), 0)
}

///|
test "copies names the shifts that bring a ring within ±180°" {
  let d = 10000000L
  assert_eq(copies(-10L * d, 10L * d), (0, 0))
  assert_eq(copies(170L * d, 190L * d), (-1, 0))
  assert_eq(copies(-190L * d, -170L * d), (0, 1))
  assert_eq(copies(185L * d, 195L * d), (-1, -1))
  assert_eq(copies(530L * d, 550L * d), (-2, -1))
  // Never more than `MAX_COPIES` either side.
  assert_eq(copies(-5000L * d, 5000L * d), (-2, 2))
  assert_eq(shifted([{ x: 5, y: 7, }], -1), [{ x: 5L - TURN, y: 7, }])
  assert_true(@clipper.area(world(true)[:]) > 0.0)
  assert_true(@clipper.area(world(false)[:]) < 0.0)
  assert_eq(short_way(HALF_TURN + 1L), 1L - HALF_TURN)
  assert_eq(short_way(-HALF_TURN - 1L), HALF_TURN - 1L)
  assert_eq(short_way(HALF_TURN), HALF_TURN)
  assert_eq(turns_floor(-1), -1)
  assert_eq(turns_floor(TURN), 1)
  assert_eq(turns_floor(TURN - 1L), 0)
}

///|
test "a buffer across the antimeridian is cut into parts within ±180°" {
  let reference = sphere_area(buffer(point(10.0, 35.0), 100000.0), 0)
  // The sphere's area differs from the ellipsoid's by its radius, under 1%.
  assert_true((reference / (PI * 1.0e4) - 1.0).abs() < 0.01)
  for lon in [179.9, -179.9, 180.0, 180.7, 539.5] {
    let out = buffer(point(lon, 35.0), 100000.0)
    assert_eq((out.kinds[0], part_count(out, 0)), (MultiPolygon, 2))
    let (w, s, e, n) = bbox_of(out, 0).unwrap()
    assert_eq((w, e), (-180.0, 180.0))
    assert_true(s > 34.0 && n < 36.0)
    assert_true(close(sphere_area(out, 0), reference))
    assert_eq(out.column("name").unwrap().values[0], Some(Str("a")))
    // Each part lies on one side.
    for p in 0..<2 {
      let (i0, i1) = out.points(out.rings(p).0)
      let east = out.coords[i0 * 2] > 0.0
      for i in i0..<i1 {
        assert_true(out.coords[i * 2].abs() > 170.0)
        assert_eq(out.coords[i * 2] > 0.0, east)
      }
    }
  }
}

///|
test "a buffer wholly past 180° comes back within ±180°" {
  let out = buffer(point(190.0, 35.0), 1000.0)
  let (w, _, e, _) = bbox_of(out, 0).unwrap()
  assert_eq(out.kinds[0], Polygon)
  assert_true(w > -170.02 && e < -169.98)
  // The 1e-7° grid is 1e-5 of this circle's radius.
  let reference = sphere_area(buffer(point(10.0, 35.0), 1000.0), 0)
  assert_true((sphere_area(out, 0) / reference - 1.0).abs() < 1.0e-4)
}

///|
test "a buffer over a pole reaches its latitude along ±180° and spans every longitude" {
  let centers = [
    (0.0, 89.5),
    (130.0, 89.5),
    (-179.5, 89.5),
    (40.0, -89.5),
    (40.0, 90.0),
  ]
  for at in centers {
    let out = buffer(point(at.0, at.1), 100000.0)
    assert_eq((out.kinds[0], part_count(out, 0)), (Polygon, 1))
    let (w, s, e, n) = bbox_of(out, 0).unwrap()
    assert_eq((w, e), (-180.0, 180.0))
    let (pole, edge) = if at.1 > 0.0 { (n, s) } else { (s, n) }
    assert_eq(pole.abs(), 90.0)
    assert_true(edge.abs() > 88.6 && edge.abs() < 89.2)
    assert_true((sphere_area(out, 0) / (PI * 1.0e4) - 1.0).abs() < 0.01)
    // Off the pole's latitude and ±180° the vertices are the circle's.
    let plane = LocalPlane::new(at.0, at.1)
    let (i0, i1) = out.points(0)
    let mut on_circle = 0
    for i in i0..<i1 {
      let (lon, lat) = (out.coords[i * 2], out.coords[i * 2 + 1])
      if lon.abs() < 180.0 && lat.abs() < 90.0 {
        let (x, y) = plane.forward(lon, lat)
        assert_true(((x * x + y * y).sqrt() - 100000.0).abs() < 0.05)
        on_circle += 1
      }
    }
    assert_true(on_circle > 40)
  }
}

///|
test "a buffer whose edge passes a pole keeps its area on either side of it" {
  // The circle of 100 km around 89.1047° passes the pole: 1 m steps across it.
  for lon in [0.0, 180.0] {
    for i in 0..<40 {
      let lat = 89.1045 + i.to_double() * 0.00001
      let out = buffer(point(lon, lat), 100000.0)
      let (w, _, e, _) = bbox_of(out, 0).unwrap()
      assert_true(w >= -180.0 && e <= 180.0)
      assert_true((sphere_area(out, 0) / (PI * 1.0e4) - 1.0).abs() < 0.012)
    }
  }
}

///|
test "a line and a polygon with a hole are cut across the antimeridian" {
  let line = buffer(
    table([(LineString, [[(179.5, 10.0), (180.5, 11.0)]], "l")]),
    20000.0,
  )
  let line_reference = buffer(
    table([(LineString, [[(-0.5, 10.0), (0.5, 11.0)]], "l")]),
    20000.0,
  )
  assert_eq((line.kinds[0], part_count(line, 0)), (MultiPolygon, 2))
  assert_true(close(sphere_area(line, 0), sphere_area(line_reference, 0)))
  let holed = (x : Double) => {
    table([
      (Polygon, [square(x, 0.0, 2.0), square(x + 0.5, 0.5, 1.0).rev()], "p"),
      (Point, [[(139.7, 35.7)]], "q"),
    ])
  }
  let cut = buffer(holed(179.0), 1000.0)
  let whole = buffer(holed(-1.0), 1000.0)
  // The antimeridian runs through the hole: two parts shaped like brackets.
  assert_eq((cut.kinds[0], part_count(cut, 0)), (MultiPolygon, 2))
  let (r0, r1) = cut.rings(cut.parts(0).0)
  assert_eq(r1 - r0, 1)
  let (w, _, e, _) = bbox_of(cut, 0).unwrap()
  assert_eq((w, e), (-180.0, 180.0))
  assert_true(close(sphere_area(cut, 0), sphere_area(whole, 0)))
  assert_eq(cut.column("name").unwrap().values, [Some(Str("p")), Some(Str("q"))])
  assert_eq(cut.kinds[1], Polygon)
  // A hole clear of the antimeridian stays one.
  let aside = buffer(
    table([
      (Polygon, [square(178.0, 0.0, 3.0), square(178.5, 0.5, 1.0).rev()], "p"),
    ]),
    1000.0,
  )
  assert_eq(part_count(aside, 0), 2)
  let rings = [0, 1].map(p => {
    let (r0, r1) = aside.rings(aside.parts(0).0 + p)
    r1 - r0
  })
  rings.sort()
  assert_eq(rings, [1, 2])
}

///|
test "a buffer that is not cut keeps the plane's vertices as they are" {
  // Wide enough for `may_wrap`, yet 3° short of 180°.
  assert_true(may_wrap(170.0, 35.0, 170.0, 35.0, 300000.0))
  let cases = [(point(170.0, 35.0), 300000.0), (point(139.7, 35.7), 1000.0)]
  for c in cases {
    let (t, meters) = c
    let out = buffer(t, meters)
    let plane = LocalPlane::new(t.coords[0], t.coords[1])
    let (i0, i1) = out.points(0)
    for i in i0..<i1 {
      // On the plane's millimeter grid, not the cut's 1e-7° (about 1 cm).
      let (x, y) = plane.forward(out.coords[i * 2], out.coords[i * 2 + 1])
      assert_true((x * 1000.0 - (x * 1000.0).round()).abs() < 1.0e-3)
      assert_true((y * 1000.0 - (y * 1000.0).round()).abs() < 1.0e-3)
    }
  }
  // Planar buffers are never cut.
  let planar = buffer(point(179.9, 35.0), 100000.0, mode=Planar)
  assert_eq(planar.kinds[0], Polygon)
  assert_true(bbox_of(planar, 0).unwrap().2 > 100000.0)
}

///|
test "a band around a pole and a buffer over both poles come out as one ring" {
  // Twelve circles of 20 km, 29 km apart on the parallel of 89.5°, a ring
  // each: `shape_of` splits the way between the points of one ring.
  let around = Array::makei(12, i => [(i.to_double() * 30.0 - 170.0, 89.5)])
  let band = buffer(table([(MultiPoint, around, "m")]), 20000.0)
  assert_eq((band.kinds[0], part_count(band, 0)), (Polygon, 1))
  let (r0, r1) = band.rings(band.parts(0).0)
  assert_eq(r1 - r0, 1)
  let (w, s, e, n) = bbox_of(band, 0).unwrap()
  assert_eq((w, e), (-180.0, 180.0))
  assert_true(s > 89.3 && s < 89.33 && n > 89.67 && n < 89.7)
  let circles = 12.0 * PI * 400.0
  assert_true(
    sphere_area(band, 0) > 0.6 * circles && sphere_area(band, 0) < circles,
  )
  // Five circles of 3,000 km along a meridian, the outer ones past the poles.
  let along = [-80.0, -40.0, 0.0, 40.0, 80.0].map(lat => [(20.0, lat)])
  let both = buffer(table([(MultiPoint, along, "m")]), 3000000.0)
  assert_eq((both.kinds[0], part_count(both, 0)), (Polygon, 1))
  assert_eq(bbox_of(both, 0), Some((-180.0, -90.0, 180.0, 90.0)))
  let (r0, r1) = both.rings(both.parts(0).0)
  assert_eq(r1 - r0, 1)
  // It leaves out the far side of the earth.
  let half = 2.0 * PI * 6371.0088 * 6371.0088
  let area = sphere_area(both, 0)
  assert_true(area > 2.0 * PI * 9.0e6 && area < half)
}

///|
test "cut_to_world leaves alone what lies within and gives up on a ring turning twice" {
  let octagon : Array[@clipper.Point64] = [
    { x: 10, y: 0, },
    { x: 7, y: 7, },
    { x: 0, y: 10, },
    { x: -7, y: 7, },
    { x: -10, y: 0, },
    { x: -7, y: -7, },
    { x: 0, y: -10, },
    { x: 7, y: -7, },
  ]
  let tree = tree_of([octagon])
  let north : @clipper.Point64 = { x: 1000, y: 1000, }
  let within = (p : @clipper.Point64) => (p.x.to_double(), p.y.to_double())
  assert_true(cut_to_world(tree, within, north) is None)
  let twice = (p : @clipper.Point64) => {
    let turn = degrees(@math.atan2(p.y.to_double(), p.x.to_double())) * 2.0
    (if turn > 180.0 { turn - 360.0 } else { turn }, 45.0)
  }
  assert_true(cut_to_world(tree, twice, north) is None)
  let past = (p : @clipper.Point64) => {
    (p.x.to_double() + 180.0, p.y.to_double())
  }
  guard cut_to_world(tree, past, north) is Some(cut) else {
    fail("a ring across 180° is cut")
  }
  assert_eq(cut.children.length(), 2)
  assert_true(cut_to_world(@clipper.PolyPath64::new(), within, north) is None)
}
