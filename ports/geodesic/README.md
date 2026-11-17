# geodesic

Geodesics on an ellipsoid in MoonBit: a port of [geographiclib-geodesic](https://github.com/geographiclib/geographiclib-js) 2.2.0, Charles Karney's algorithms (accurate to round-off, for any pair of points). Distances and azimuths, points along a line, and the perimeter and area of polygons. Pure MoonBit on every backend (wasm, wasm-gc, js, native); it depends only on [`t-ujiie-g/trig`](https://mooncakes.io/docs/t-ujiie-g/trig).

Part of [mbt-map](https://github.com/t-ujiie-g/mbt-map), a WebGIS library, published on its own.

```sh
moon add t-ujiie-g/geodesic
```

```moonbit
/// The distance in meters from Tokyo to Paris, and the point a quarter of the way.
fn tokyo_paris() -> (Double, (Double, Double)) {
  let g = @geodesic.Geodesic::wgs84()
  let line = g.inverse_line(35.6812, 139.7671, 48.8566, 2.3522)
  let p = line.position(false, line.s13 / 4.0)
  (line.s13, (p.lat2, p.lon2))
}

///|
/// The area in square meters of a ring given as lng, lat pairs.
fn ring_area(coords : Array[Double]) -> Double {
  @geodesic.Geodesic::wgs84().measure_path(coords[:], true)[1]
}
```

## What it gives

- `Geodesic::wgs84()`, or `Geodesic::new(a, f)` for another ellipsoid (equatorial radius in meters, flattening; prolate ones too). `None` unless both semi-axes are finite and positive.
- `inverse(lat1, lon1, lat2, lon2)`: the distance `s12` (meters), the azimuths `azi1` and `azi2` (degrees) and the arc `a12`; with `area=true` also `S12`, the area between the geodesic and the equator.
- `direct(lat1, lon1, azi1, s12)`: the point `s12` meters away.
- `line(lat1, lon1, azi1)` and `inverse_line(lat1, lon1, lat2, lon2)`: a `GeodesicLine`, whose `position(arcmode, s12_a12, unroll?)` gives points by distance or by arc; `unroll` lets the longitude run past ±180° continuously.
- `polygon(polyline?)`: a `PolygonArea`; `add_point(lat, lon)`, then `compute(reverse?, sign?)` gives the perimeter and the area.
- Three helpers over arrays of lng, lat pairs (GeoJSON's order): `measure_path(coords, closed)` (length, a ring's area, the distance to each vertex), `densify(coords, step, max_points)` (points at most `step` meters apart along each edge) and `circle(lng, lat, radius, n)`.
- `trig`: `wgs84` and `new` take a `Trig` (default `Trig::moonbit()`). Pass a wasm host's `Math` to get the JavaScript library's results bit for bit.

The functions of the library take latitude first, as GeographicLib does; the three helpers take longitude first.

Not ported: the library's output masks (every quantity is computed, except `S12` on request), `GenDirect`'s reduced length and geodesic scales in the results, and the DMS utilities.

## Matching geographiclib-geodesic

The repository compares the wasm-gc build, with the host's `Math`, against geographiclib-geodesic 2.2.0 on inverse and direct problems, polygons and densified paths (`geodesic:golden`): identical.

## License

Apache-2.0 for the port; geographiclib-geodesic is MIT (see `NOTICE`).
