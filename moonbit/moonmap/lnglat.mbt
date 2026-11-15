///|
/// A place in degrees: longitude east, latitude north (WGS 84).
#derive(Eq, Debug)
pub(all) struct LngLat {
  lng : Double
  lat : Double
}

///|
/// `LngLat` of `lng` and `lat`, degrees.
pub fn lnglat(lng : Double, lat : Double) -> LngLat {
  { lng, lat, }
}
