///|
fn camera_at(lng : Double, zoom : Double) -> @core.Camera {
  { center: { lng, lat: 10.0, }, zoom, bearing: 0.0, pitch: 0.0, }
}

///|
fn no_copies() -> @core.Limits {
  { ..@core.Limits::default(), world_copies: false, }
}

///|
/// How many of `tiles` hold mercator point `m`, copies by their own bounds.
fn holding(
  tiles : Array[@core.UnwrappedTile],
  m : @core.MercatorCoord,
) -> Int32 {
  tiles
  .filter(u => {
    let b = u.mercator_bounds()
    m.x >= b.min_x && m.x < b.max_x && m.y >= b.min_y && m.y < b.max_y
  })
  .length()
}

///|
test "a view wider than the world is covered once per point, across its copies" {
  for bearing in [0.0, 30.0] {
    let t = @core.Transform::new(
      { ..camera_at(0.0, 0.5), bearing, pitch: 40.0, },
      1600.0,
      600.0,
    )
    let (first, last) = t.wraps()
    assert_true(first <= -1 && last >= 1)
    let tiles = t.covering_tiles(0, 1)
    for m in screen_samples(t) {
      let n = holding(tiles, m)
      assert_true(n == 1 || (n == 0 && (m.y >= 1.0 || m.y <= 0.0)))
    }
    // The same tile in two copies.
    let east = tiles.filter(u => u.id == @core.TileId::new(1, 1, 0).unwrap())
    assert_true(east.length() >= 2)
  }
}

///|
test "a view centered on the antimeridian takes tiles from both ends of the world" {
  let t = @core.Transform::new(camera_at(179.9, 4.0), 800.0, 600.0)
  assert_eq(t.wraps(), (0, 1))
  let tiles = t.covering_tiles(0, 4)
  assert_true(tiles.iter().any(u => u.wrap == 0 && u.id.x == 15))
  assert_true(tiles.iter().any(u => u.wrap == 1 && u.id.x == 0))
  for m in screen_samples(t) {
    assert_eq(holding(tiles, m), 1)
  }
  // Without copies the camera keeps the view west of the antimeridian.
  let one = @core.Transform::new(
    camera_at(179.9, 4.0),
    800.0,
    600.0,
    limits=no_copies(),
  )
  assert_eq(one.wraps(), (0, 0))
  assert_true(one.camera.center.lng < 179.9)
  assert_true(one.screen_to_mercator(800.0, 300.0).x <= 1.0 + 1.0e-12)
  assert_true(one.covering_tiles(0, 4).iter().all(u => u.wrap == 0))
}

///|
test "without copies the zoom rises until the world fills the view" {
  let t = @core.Transform::new(
    camera_at(0.0, 0.0),
    1024.0,
    300.0,
    limits=no_copies(),
  )
  assert_true(close(t.camera.zoom, 1.0))
  let w = @core.Transform::new(camera_at(0.0, 0.0), 1024.0, 300.0)
  assert_eq(w.camera.zoom, 0.0)
}

///|
test "a center past the antimeridian is wrapped, panning across it keeps the map under the pointer" {
  let t = @core.Transform::new(camera_at(190.0, 4.0), 800.0, 600.0)
  assert_true(close(t.camera.center.lng, -170.0))
  let east = @core.Transform::new(camera_at(179.0, 4.0), 800.0, 600.0)
  let before = east.unproject(700.0, 300.0)
  assert_true(before.lng > 180.0)
  let moved = east.with_camera(east.panned(700.0, 300.0, 400.0, 300.0))
  assert_true(moved.camera.center.lng < -160.0)
  let after = moved.unproject(400.0, 300.0)
  assert_true(
    close(after.lng + 360.0, before.lng) && close(after.lat, before.lat),
  )
  // Without copies the pan stops at the antimeridian.
  let one = @core.Transform::new(
    camera_at(170.0, 4.0),
    800.0,
    600.0,
    limits=no_copies(),
  )
  let stuck = one.with_camera(one.panned(700.0, 300.0, 100.0, 300.0))
  assert_true(stuck.camera.center.lng > 0.0)
  assert_true(stuck.screen_to_mercator(800.0, 300.0).x <= 1.0 + 1.0e-12)
}

///|
test "project and unproject take longitudes on a copy to its place on screen" {
  let t = @core.Transform::new(camera_at(179.0, 4.0), 800.0, 600.0)
  let (x, y) = t.project({ lng: -179.0 + 360.0, lat: 10.0, })
  let (wx, wy) = t.project({ lng: -179.0, lat: 10.0, })
  // 2 degrees east of the center, a world (512 * 16 px) left of its main copy.
  assert_true(close(x - wx, 512.0 * 16.0) && close(y, wy))
  let p = t.unproject(x, y)
  assert_true(close(p.lng, 181.0) && close(p.lat, 10.0))
}

///|
test "tile_matrix places a copy a world to the side" {
  let t = @core.Transform::new(camera_at(179.9, 4.0), 800.0, 600.0)
  let id = @core.TileId::new(4, 0, 7).unwrap()
  let b = ({ id, wrap: 1, } : @core.UnwrappedTile).mercator_bounds()
  assert_true(close(b.min_x, 1.0) && close(b.max_x, 1.0625))
  let (sx, sy) = screen_of(t, { x: b.min_x, y: b.min_y, })
  let (x, y, _, w) = t.tile_matrix(id, 4096, wrap=1).apply(0.0, 0.0, 0.0, 1.0)
  assert_true(close(x / w, sx / 400.0 - 1.0) && close(y / w, 1.0 - sy / 300.0))
  let light = t.tile_light_matrix(@core.Mat4::identity(), id, 4096, wrap=1)
  let (lx, _, _, _) = light.apply(0.0, 0.0, 0.0, 1.0)
  let c = t.camera.center.to_mercator()
  assert_true(close(lx, (1.0 - c.x) * t.world_size()))
}

///|
test "unwrapped tile keys tell copies and tiles apart" {
  let keys = []
  for z in [0, 5, 28] {
    let n = 1 << z
    for x in (if n > 1 { [0, n - 1] } else { [0] }) {
      let id = @core.TileId::new(z, x, n - 1).unwrap()
      for wrap in -@core.MAX_WORLD_COPIES..<=@core.MAX_WORLD_COPIES {
        let k = ({ id, wrap, } : @core.UnwrappedTile).key()
        assert_true(!keys.contains(k))
        keys.push(k)
      }
    }
  }
  assert_eq(keys.length(), 5 * 7)
}
