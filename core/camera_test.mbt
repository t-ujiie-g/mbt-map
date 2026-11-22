///|
fn within(a : Double, b : Double, tol : Double) -> Bool {
  (a - b).abs() < tol
}

///|
fn view(pitch : Double, bearing : Double) -> @core.Transform {
  @core.Transform::new(
    { center: { lng: 139.7671, lat: 35.6812, }, zoom: 14.0, bearing, pitch, },
    800.0,
    600.0,
  )
}

///|
test "project and unproject undo each other, and the center is the screen's middle" {
  for v in [view(0.0, 0.0), view(45.0, 30.0), view(70.0, -120.0)] {
    let (cx, cy) = v.project(v.camera.center)
    assert_true(within(cx, 400.0, 1.0e-6) && within(cy, 300.0, 1.0e-6))
    for p in [(100.0, 550.0), (700.0, 420.0), (400.0, 599.0)] {
      let ll = v.unproject(p.0, p.1)
      let (x, y) = v.project(ll)
      assert_true(within(x, p.0, 1.0e-6) && within(y, p.1, 1.0e-6))
    }
  }
}

///|
test "a point behind the camera goes to the grown viewport's edge" {
  let v = view(80.0, 0.0)
  // Far south of a camera looking north is behind it.
  let (x, y) = v.project({ lng: 139.7671, lat: 30.0, })
  assert_true(within(x, 400.0, 1.0e-6) && within(y, 300.0 + 900.0, 1.0e-6))
}

///|
test "bounds hold the corners and stop at the horizon line when tilted" {
  let flat = view(0.0, 0.0)
  let b = flat.bounds()
  let nw = flat.unproject(0.0, 0.0)
  assert_true(within(b.west, nw.lng, 1.0e-9) && within(b.north, nw.lat, 1.0e-9))
  let tilted = view(85.0, 0.0)
  let t = tilted.bounds()
  let horizon = tilted.unproject(400.0, 300.0 - tilted.horizon())
  assert_true(within(t.north, horizon.lat, 1.0e-9))
}

///|
test "at_point puts a place at a screen point" {
  let v = view(45.0, 30.0)
  let tokyo_tower : @core.LngLat = { lng: 139.7454, lat: 35.6586, }
  let c = v.with_camera(v.at_point(tokyo_tower, 200.0, 450.0))
  let (x, y) = c.project(tokyo_tower)
  assert_true(within(x, 200.0, 1.0e-6) && within(y, 450.0, 1.0e-6))
}

///|
test "camera_for_bounds fits a box with padding, and refuses padding with no room" {
  let v = view(0.0, 0.0)
  let box : @core.LngLatBounds = {
    west: 139.5,
    south: 35.5,
    east: 140.0,
    north: 35.8,
  }
  let c = v
    .camera_for_bounds(box, padding=@core.Padding::uniform(20.0))
    .unwrap()
  let fit = v.with_camera(c)
  let (x0, y0) = fit.project({ lng: 139.5, lat: 35.8, })
  let (x1, y1) = fit.project({ lng: 140.0, lat: 35.5, })
  // One pair of edges touches the padding, the other lies inside it.
  assert_true(within(x0, 20.0, 1.0e-6) || within(y0, 20.0, 1.0e-6))
  assert_true(x0 >= 20.0 - 1.0e-6 && x1 <= 780.0 + 1.0e-6)
  assert_true(y0 >= 20.0 - 1.0e-6 && y1 <= 580.0 + 1.0e-6)
  assert_eq(
    v.camera_for_bounds(box, padding=@core.Padding::uniform(500.0)),
    None,
  )
  let capped = v.camera_for_bounds(box, max_zoom=5.0).unwrap()
  assert_eq(capped.zoom, 5.0)
}

///|
test "the default easing is CSS ease and bearings ease the short way" {
  let e = @core.Bezier::ease()
  assert_eq((e.at(0.0), e.at(1.0), e.at(-1.0), e.at(2.0)), (0.0, 1.0, 0.0, 1.0))
  // CSS `ease` at half time is about 80% of the way.
  assert_true(within(e.at(0.5), 0.8024033877399112, 1.0e-6))
  let linear = @core.Bezier::new(0.0, 0.0, 1.0, 1.0)
  assert_true(within(linear.at(0.3), 0.3, 1.0e-6))
}

///|
test "ease_to starts where the camera is and ends at the target" {
  let v = view(0.0, 0.0)
  let target = @core.CameraTarget::new(
    center={ lng: 140.0, lat: 35.5, },
    zoom=12.0,
    bearing=90.0,
    pitch=30.0,
  )
  let e = v.ease_to(target)
  let a = e.at(0.0)
  assert_true(within(a.center.lng, 139.7671, 1.0e-9) && a.zoom == 14.0)
  let b = e.at(1.0)
  assert_true(
    within(b.center.lng, 140.0, 1.0e-9) && within(b.center.lat, 35.5, 1.0e-9),
  )
  assert_eq((b.zoom, b.bearing, b.pitch), (12.0, 90.0, 30.0))
  // Around a point, that point stays put.
  let around : @core.LngLat = { lng: 139.78, lat: 35.69, }
  let (x, y) = v.project(around)
  let z = v.ease_to(@core.CameraTarget::new(zoom=15.0, around~))
  let (x2, y2) = v.with_camera(z.at(0.5)).project(around)
  assert_true(within(x, x2, 1.0e-6) && within(y, y2, 1.0e-6))
}

///|
test "fly_to zooms out on the way and has a duration; a standstill does not fly" {
  let v = view(0.0, 0.0)
  let f = v
    .fly_to(
      @core.CameraTarget::new(center={ lng: 135.5, lat: 34.7, }, zoom=14.0),
    )
    .unwrap()
  assert_true(f.duration > 1000.0)
  assert_true(f.at(0.5).zoom < 10.0)
  let end = f.at(1.0)
  assert_true(within(end.center.lng, 135.5, 1.0e-9) && end.zoom == 14.0)
  assert_true(v.fly_to(@core.CameraTarget::new()) is None)
  assert_true(@core.CameraTarget::new().offset == (0.0, 0.0))
}

///|
test "with_limits moves the camera inside the new limits" {
  let v = view(60.0, 0.0)
  let limited = v.with_limits({
    ..@core.Limits::default(),
    max_zoom: 12.0,
    max_pitch: 40.0,
  })
  assert_eq((limited.camera.zoom, limited.camera.pitch), (12.0, 40.0))
  assert_eq(limited.limits.max_zoom, 12.0)
}

///|
test "max_pitch_scale_factor is 1 looking down and grows with the pitch" {
  assert_true(within(view(0.0, 0.0).max_pitch_scale_factor(), 1.0, 1.0e-9))
  let tilted = view(60.0, 0.0).max_pitch_scale_factor()
  assert_true(tilted > 1.5 && tilted < 10.0)
}

///|
test "an aligned tile matrix puts tile corners on whole pixels at whole zooms" {
  let v = @core.Transform::new(
    {
      center: { lng: 139.76713, lat: 35.68123, },
      zoom: 14.0,
      bearing: 0.0,
      pitch: 0.0,
    },
    800.0,
    600.0,
  )
  let id = @core.TileId::new(14, 14552, 6451).unwrap()
  let screen = (m : @core.Mat4) => {
    let (x, y, _, w) = m.apply(0.0, 0.0, 0.0, 1.0)
    ((x / w + 1.0) * 400.0, (1.0 - y / w) * 300.0)
  }
  let (ax, ay) = screen(v.tile_matrix(id, 4096, aligned=true))
  let (px, py) = screen(v.tile_matrix(id, 4096))
  assert_true(within(ax, ax.round(), 1.0e-6) && within(ay, ay.round(), 1.0e-6))
  assert_true((ax - px).abs() <= 0.5 && (ay - py).abs() <= 0.5)
}

///|
fn padded(pitch : Double, padding : @core.Padding) -> @core.Transform {
  @core.Transform::new(
    {
      center: { lng: 139.7671, lat: 35.6812, },
      zoom: 14.0,
      bearing: 30.0,
      pitch,
    },
    800.0,
    600.0,
    padding~,
  )
}

///|
test "padding: valid sides are finite and 0 or more" {
  assert_true(@core.Padding::uniform(0.0).valid())
  assert_true(
    ({ top: 1.0, right: 2.5, bottom: 0.0, left: 300.0, } : @core.Padding).valid(),
  )
  for bad in [-1.0, @double.not_a_number, @double.infinity] {
    assert_false(
      ({ top: 0.0, right: 0.0, bottom: bad, left: 0.0, } : @core.Padding).valid(),
    )
  }
}

///|
test "padding: toward mixes each side and center is the middle of what is left, kept on screen" {
  let a : @core.Padding = { top: 0.0, right: 10.0, bottom: 20.0, left: 100.0, }
  let b : @core.Padding = { top: 40.0, right: 10.0, bottom: 0.0, left: 300.0, }
  assert_eq(a.toward(b, 0.0), a)
  assert_eq(a.toward(b, 1.0), b)
  assert_eq(a.toward(b, 0.25), {
    top: 10.0,
    right: 10.0,
    bottom: 15.0,
    left: 150.0,
  })
  assert_eq(b.center(800.0, 600.0), (545.0, 320.0))
  assert_eq(@core.Padding::uniform(0.0).center(800.0, 600.0), (400.0, 300.0))
  let wide : @core.Padding = {
    top: 0.0,
    right: 0.0,
    bottom: 0.0,
    left: 2000.0,
  }
  assert_eq(wide.center(800.0, 600.0), (800.0, 300.0))
}

///|
test "padding: the perspective's principal point moves to the padded center" {
  let p : @core.Padding = { top: 50.0, right: 0.0, bottom: 300.0, left: 320.0, }
  let m = p.perspective(800.0, 600.0, 12.0, 5000.0)
  let plain = @core.Padding::uniform(0.0).perspective(
    800.0, 600.0, 12.0, 5000.0,
  )
  assert_eq(m.m[8], -160.0 * 2.0 / 800.0)
  assert_eq(m.m[9], -125.0 * 2.0 / 600.0)
  for i in [0, 5, 10, 11, 14] {
    assert_eq(m.m[i], plain.m[i])
  }
}

///|
test "a padded view draws its center and its vanishing point at the padded center" {
  let padding : @core.Padding = {
    top: 0.0,
    right: 0.0,
    bottom: 0.0,
    left: 320.0,
  }
  for pitch in [0.0, 60.0] {
    let v = padded(pitch, padding)
    assert_eq(v.padding, padding)
    assert_eq(v.center_point(), (560.0, 300.0))
    let (x, y) = v.project(v.camera.center)
    assert_true(within(x, 560.0, 1.0e-6) && within(y, 300.0, 1.0e-6))
    let c = v.unproject(560.0, 300.0)
    assert_true(
      within(c.lng, 139.7671, 1.0e-9) && within(c.lat, 35.6812, 1.0e-9),
    )
  }
  // Straight ahead of a tilted camera, far ground converges on the padded center's column.
  let v = padded(60.0, padding)
  let plain = padded(60.0, @core.Padding::uniform(0.0))
  let ahead = plain.unproject(400.0, 20.0)
  let (x, y) = v.project(ahead)
  assert_true(within(x, 560.0, 1.0e-6) && within(y, 20.0, 1.0e-6))
}

///|
test "with_padding keeps the center's place and moves the picture; with_view takes both" {
  let v = view(45.0, 30.0)
  let padding : @core.Padding = {
    top: 100.0,
    right: 20.0,
    bottom: 40.0,
    left: 200.0,
  }
  let p = v.with_padding(padding)
  assert_eq(p.camera, v.camera)
  assert_eq(p.center_point(), (490.0, 330.0))
  let (x, y) = p.project(v.camera.center)
  assert_true(within(x, 490.0, 1.0e-6) && within(y, 330.0, 1.0e-6))
  let bad : @core.Padding = { ..padding, top: -1.0, }
  assert_eq(v.with_padding(bad).padding, @core.Padding::uniform(0.0))
  assert_eq(
    @core.Transform::new(v.camera, 800.0, 600.0, padding=bad).padding,
    @core.Padding::uniform(0.0),
  )
  let camera = { ..v.camera, zoom: 10.0, }
  let w = v.with_view(camera, padding)
  assert_eq(w.camera, camera)
  assert_eq(w.padding, padding)
  assert_eq(v.with_view(camera, bad).camera, v.camera)
  assert_eq(p.with_camera(camera).padding, padding)
  assert_eq(p.resize(1000.0, 600.0).padding, padding)
  assert_eq(p.with_elevation(120.0).padding, padding)
  assert_eq(p.with_limits(@core.Limits::default()).padding, padding)
}

///|
test "padding narrows the view the bounds must fill" {
  let limits : @core.Limits = {
    ..@core.Limits::default(),
    bounds: Some({ west: 139.0, south: 35.0, east: 140.0, north: 36.0, }),
  }
  let camera : @core.Camera = {
    center: { lng: 139.5, lat: 35.5, },
    zoom: 3.0,
    bearing: 0.0,
    pitch: 0.0,
  }
  let plain = @core.Transform::new(camera, 800.0, 600.0, limits~)
  let p = @core.Transform::new(camera, 800.0, 600.0, limits~, padding={
    top: 0.0,
    right: 0.0,
    bottom: 0.0,
    left: 200.0,
  })
  // Three quarters of the width to fill.
  assert_true(
    within(plain.camera.zoom - p.camera.zoom, @math.log2(800.0 / 600.0), 1.0e-9),
  )
}

///|
test "camera_for_bounds fits inside the map's padding, and absolute padding stands for it" {
  let b : @core.LngLatBounds = {
    west: 139.5,
    south: 35.5,
    east: 140.0,
    north: 35.8,
  }
  let map_padding : @core.Padding = {
    top: 0.0,
    right: 0.0,
    bottom: 0.0,
    left: 320.0,
  }
  let v = padded(0.0, map_padding)
  let c = v.camera_for_bounds(b).unwrap()
  let fitted = v.with_camera(c)
  let (x0, _) = fitted.project({ lng: 139.5, lat: 35.65, })
  let (x1, _) = fitted.project({ lng: 140.0, lat: 35.65, })
  assert_true(within(x0, 320.0, 1.0e-6) && within(x1, 800.0, 1.0e-6))
  // The same padding as the fit's own leaves less room and moves the center.
  let own = view(0.0, 30.0).camera_for_bounds(b, padding=map_padding).unwrap()
  assert_true(within(own.zoom, c.zoom, 1.0e-9))
  assert_true(own.center.lng < c.center.lng)
  assert_eq(v.camera_for_bounds(b, padding=map_padding, absolute=true), Some(c))
  assert_eq(
    @core.fit_paddings(map_padding, @core.Padding::uniform(5.0), false),
    (@core.Padding::uniform(5.0), map_padding),
  )
  assert_eq(
    @core.fit_paddings(map_padding, @core.Padding::uniform(5.0), true),
    (@core.Padding::uniform(0.0), @core.Padding::uniform(5.0)),
  )
}

///|
test "ease_to and fly_to move the padding with the camera and keep the target under the padded center" {
  let v = view(0.0, 0.0)
  let padding : @core.Padding = {
    top: 0.0,
    right: 0.0,
    bottom: 200.0,
    left: 300.0,
  }
  let center : @core.LngLat = { lng: 139.9, lat: 35.5, }
  let target = @core.CameraTarget::new(center~, zoom=12.0, padding~)
  let e = v.ease_to(target)
  assert_eq(e.padding_at(0.0), @core.Padding::uniform(0.0))
  assert_eq(e.padding_at(0.5), {
    top: 0.0,
    right: 0.0,
    bottom: 100.0,
    left: 150.0,
  })
  assert_eq(e.padding_at(1.0), padding)
  let end = e.at(1.0)
  assert_true(
    within(end.center.lng, 139.9, 1.0e-9) &&
    within(end.center.lat, 35.5, 1.0e-9),
  )
  let (x, y) = v.with_view(end, padding).project(center)
  assert_true(within(x, 550.0, 1.0e-6) && within(y, 200.0, 1.0e-6))
  let f = v.fly_to(target).unwrap()
  assert_eq(f.padding_at(0.0), @core.Padding::uniform(0.0))
  assert_eq(f.padding_at(1.0), padding)
  assert_eq(f.at(1.0).center, v.with_view(end, padding).camera.center)
  // A target without padding, or with the map's, keeps it.
  let kept = v.with_padding(padding)
  assert_eq(
    kept.ease_to(@core.CameraTarget::new(center~)).padding_at(0.5),
    padding,
  )
  assert_eq(
    kept.ease_to(@core.CameraTarget::new(center~, padding~)).padding_at(0.5),
    padding,
  )
  assert_eq(
    kept.fly_to(@core.CameraTarget::new(center~)).unwrap().padding_at(0.5),
    padding,
  )
}

///|
test "covering tiles of a padded, tilted view still reach the screen's corners" {
  let v = padded(60.0, { top: 250.0, right: 0.0, bottom: 0.0, left: 0.0, })
  let tiles = v.covering_tiles(0, 14)
  for p in [(0.0, 599.0), (799.0, 599.0), (400.0, 425.0)] {
    let m = v.screen_to_mercator(p.0, p.1)
    assert_true(
      tiles
      .iter()
      .any(tile => {
        let b = tile.mercator_bounds()
        m.x >= b.min_x && m.x < b.max_x && m.y >= b.min_y && m.y < b.max_y
      }),
    )
  }
}
