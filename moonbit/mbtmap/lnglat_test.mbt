///|
test "lnglat keeps longitude and latitude" {
  let p = @mbtmap.lnglat(139.7671, 35.6812)
  assert_eq(p.lng, 139.7671)
  assert_eq(p.lat, 35.6812)
  assert_eq(p, { lng: 139.7671, lat: 35.6812, })
}
