///|
test "lnglat keeps longitude and latitude" {
  let p = @mbtmap.lnglat(139.7671, 35.6812)
  assert_eq(p.lng, 139.7671)
  assert_eq(p.lat, 35.6812)
  assert_eq(p, { lng: 139.7671, lat: 35.6812, })
}

///|
test "Padding::new leaves sides at 0 and to_json names the four" {
  let p = @mbtmap.Padding::new(left=320.0, bottom=40.0)
  assert_eq(p, { top: 0.0, right: 0.0, bottom: 40.0, left: 320.0, })
  assert_eq(p.to_json(), { "top": 0, "right": 0, "bottom": 40, "left": 320 })
}
