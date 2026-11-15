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
  let h = {
    load: Some(@cmd.none),
    idle: None,
    move_: None,
    moveend: Some(@cmd.Emit(_ => @cmd.none)),
    click: None,
    error: None,
  }
  assert_true(handle(h, "mbt-map-load", detail()) is Some(_))
  assert_true(handle(h, "mbt-map-moveend", detail()) is Some(_))
  assert_true(handle(h, "mbt-map-idle", detail()) is None)
  assert_true(handle(h, "mbt-map-click", detail()) is None)
  assert_true(handle(h, "click", detail()) is None)
}
