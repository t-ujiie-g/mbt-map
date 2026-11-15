///|
/// Mt Fuji's summit seen from the south at zoom 12, pitched 70°, the center on
/// the summit (3776 m, exaggerated 1.5 times as the terrain page draws it).
fn summit() -> @core.Transform {
  let camera : @core.Camera = {
    center: { lng: 138.7274, lat: 35.3606, },
    zoom: 12.0,
    bearing: 0.0,
    pitch: 70.0,
  }
  @core.Transform::new(camera, 1000.0, 800.0).with_elevation(3776.0 * 1.5)
}

///|
/// Points at `height` meters on a grid six tiles of zoom 12 around the center
/// that are on screen below the horizon line but in none of `tiles`.
fn uncovered(
  t : @core.Transform,
  tiles : Array[@core.TileId],
  height : Double,
) -> Int32 {
  let c = t.camera.center.to_mercator()
  let tile = 1.0 / 4096.0
  let mut missed = 0
  for i in -48..<=48 {
    for j in -48..<=48 {
      let m : @core.MercatorCoord = {
        x: c.x + i.to_double() * tile / 8.0,
        y: c.y + j.to_double() * tile / 8.0,
      }
      let (x, y) = t.project(m.to_lnglat(), elevation=height)
      let on_screen = x > 0.0 &&
        x < t.width &&
        y > t.height / 2.0 - t.horizon() &&
        y < t.height
      let inside = (id : @core.TileId) => {
        let b = id.mercator_bounds()
        m.x >= b.min_x && m.x < b.max_x && m.y >= b.min_y && m.y < b.max_y
      }
      if on_screen && !tiles.iter().any(inside) {
        missed += 1
      }
    }
  }
  missed
}

///|
test "ground below an elevated center is covered down to sea level" {
  let t = summit()
  let tiles = t.covering_tiles(12, 12).map(u => u.id)
  for height in [0.0, 1000.0, 2500.0, 4000.0, t.elevation] {
    assert_eq(uncovered(t, tiles, height), 0)
  }
  // The near row south of the summit, which lower ground fills at the bottom
  // of the screen, is among them.
  let near = @core.TileId::new(12, 3626, 1618).unwrap()
  assert_true(tiles.contains(near))
}

///|
test "covering takes each tile's heights" {
  let t = summit()
  let plain = t.covering_tiles(12, 12).map(u => u.id)
  // Ground rising 5 km above the center everywhere comes into view nearer the
  // camera and needs tiles the center's heights do not reach.
  let peak = t.elevation + 5000.0
  assert_true(uncovered(t, plain, peak) > 0)
  let tiles = t.covering_tiles(12, 12, heights=_ => (0.0, peak)).map(u => u.id)
  assert_eq(uncovered(t, tiles, peak), 0)
  assert_eq(uncovered(t, tiles, 0.0), 0)
  assert_true(plain.iter().all(id => tiles.contains(id)))
  // The center's own heights change nothing.
  let same = t
    .covering_tiles(12, 12, heights=_ => (0.0, t.elevation))
    .map(u => u.id)
  assert_eq(same, plain)
}

///|
test "heights above the camera cover the ground under it" {
  let t = summit()
  let tiles = t.covering_tiles(12, 12, heights=_ => (0.0, 1.0e6)).map(u => u.id)
  let under = t.screen_to_mercator(t.width / 2.0, t.height)
  assert_true(tiles.length() > t.covering_tiles(12, 12).map(u => u.id).length())
  assert_eq(uncovered(t, tiles, 0.0), 0)
  // The camera stands south of the bottom of the screen.
  let camera = @core.tile_containing(
    { x: under.x, y: under.y + (under.y - t.camera.center.to_mercator().y), },
    12,
  ).unwrap()
  assert_true(tiles.contains(camera))
}

///|
test "a view at sea level is covered as without heights" {
  let t = @core.Transform::new(
    { ..tokyo(), bearing: 30.0, pitch: 60.0, },
    800.0,
    600.0,
  )
  assert_eq(
    t.covering_tiles(4, 14, heights=_ => (0.0, 0.0)).map(u => u.id),
    t.covering_tiles(4, 14).map(u => u.id),
  )
}

///|
test "a source that starts far deeper than the camera's zoom is not covered" {
  let far = (zoom : Double, pitch : Double) => {
    @core.Transform::new({ ..tokyo(), zoom, pitch, }, 1200.0, 800.0)
  }
  // The whole world at zoom 14 would be 4^14 tiles.
  assert_eq(far(2.0, 60.0).covering_tiles(14, 14).length(), 0)
  assert_eq(far(2.0, 0.0).covering_tiles(14, 14, tile_size=256).length(), 0)
  assert_eq(far(0.0, 85.0).covering_tiles(14, 22).length(), 0)
  // Up to MIN_ZOOM_SLACK levels above it the ground near the camera still gets its tiles.
  for zoom in [11.0, 12.0, 13.0] {
    let tiles = far(zoom, 60.0).covering_tiles(14, 14)
    assert_true(tiles.length() > 0 && tiles.length() < 400)
    assert_true(tiles.iter().all(u => u.id.z == 14))
  }
  // A maximum deeper than the camera's zoom is not walked into.
  let tiles = far(2.0, 60.0).covering_tiles(0, 24)
  assert_true(tiles.length() > 0 && tiles.length() < 100)
  assert_true(tiles.iter().all(u => u.id.z <= 2))
  assert_true(
    far(2.0, 0.0)
    .covering_tiles(0, 24, tile_size=256)
    .iter()
    .any(u => u.id.z == 3),
  )
}
