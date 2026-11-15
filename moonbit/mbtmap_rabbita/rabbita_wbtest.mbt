///|
fn detail() -> @mbtmap.JsValue {
  @mbtmap.json_to_js({
    "center": { "lng": 139.7671, "lat": 35.6812 },
    "zoom": 15,
    "bearing": 10,
    "pitch": 30,
    "point": { "x": 400, "y": 300 },
    "lngLat": { "lng": 139.77, "lat": 35.68 },
    "error": { "message": "mbt-map: invalid zoom" },
  })
}

///|
test "camera_of and click_of read an event's detail" {
  let camera = {
    center: @mbtmap.lnglat(139.7671, 35.6812),
    zoom: 15.0,
    bearing: 10.0,
    pitch: 30.0,
  }
  assert_eq(camera_of(detail()), camera)
  assert_eq(click_of(detail()), {
    point: { x: 400.0, y: 300.0, },
    lnglat: @mbtmap.lnglat(139.77, 35.68),
    camera,
  })
  assert_eq(detail_error(detail()), "mbt-map: invalid zoom")
}

///|
test "camera_of gives NaN for what the detail lacks" {
  let c = camera_of(@mbtmap.json_to_js({ "zoom": 3 }))
  assert_eq(c.zoom, 3.0)
  assert_true(c.center.lng.is_nan() && c.bearing.is_nan())
}

///|
test "handle answers only the event types with a handler" {
  let hs = handlers(
    Some(@cmd.none),
    None,
    None,
    Some(@cmd.Emit(_ => @cmd.none)),
    None,
    None,
  )
  assert_eq(hs.map(h => h.0), ["mbt-map-load", "mbt-map-moveend"])
  assert_true(handle(hs, "mbt-map-load", detail()) is Some(_))
  assert_true(handle(hs, "mbt-map-moveend", detail()) is Some(_))
  assert_true(handle(hs, "mbt-map-idle", detail()) is None)
  assert_true(handle(hs, "mbt-map-click", detail()) is None)
  assert_true(handle(hs, "click", detail()) is None)
}

///|
test "handlers read the camera, the click and the error from the detail" {
  let got : Array[String] = []
  let hs = handlers(
    None,
    None,
    Some(
      @cmd.Emit(c => {
        got.push("move \{c.zoom}")
        @cmd.none
      }),
    ),
    None,
    Some(
      @cmd.Emit(c => {
        got.push("click \{c.point.x}")
        @cmd.none
      }),
    ),
    Some(
      @cmd.Emit(m => {
        got.push(m)
        @cmd.none
      }),
    ),
  )
  for kind in ["mbt-map-move", "mbt-map-click", "mbt-map-error"] {
    ignore(handle(hs, kind, detail()))
  }
  assert_eq(got, ["move 15", "click 400", "mbt-map: invalid zoom"])
}
