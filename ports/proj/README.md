# proj

Map projections and datum shifts in MoonBit: a port of [proj4js](https://github.com/proj4js/proj4js) 2.22.0's transform pipeline. Pure MoonBit on every backend (wasm, wasm-gc, js, native); it depends only on [`t-ujiie-g/trig`](https://mooncakes.io/docs/t-ujiie-g/trig).

Part of [mbt-map](https://github.com/t-ujiie-g/mbt-map), a WebGIS library, published on its own.

```sh
moon add t-ujiie-g/proj
```

```moonbit
/// Tokyo Station in Japan's plane rectangular zone IX (EPSG:6677): about (-5995.19, -35367.23).
fn station_in_zone_9() -> (Double, Double)? {
  guard @proj.Crs::from_epsg(4326) is Some(wgs84) else { return None }
  guard @proj.Crs::from_epsg(6677) is Some(plane) else { return None }
  @proj.transform(wgs84, plane, 139.7671, 35.6812)
}

///|
/// Lambert 93 (`+proj=lcc +lat_0=46.5 +lon_0=3 +lat_1=49 +lat_2=44 +x_0=700000 +y_0=6600000
/// +ellps=GRS80 +towgs84=0,0,0`), built by hand: angles in radians.
fn lambert93() -> @proj.Crs? {
  let rad = 0.017453292519943295
  let d = @proj.Definition::new(Lcc, 6378137.0, 6356752.314140356)
  d.lat0 = 46.5 * rad
  d.long0 = 3.0 * rad
  d.lat1 = 49.0 * rad
  d.lat2 = 44.0 * rad
  d.x0 = 700000.0
  d.y0 = 6600000.0
  d.towgs84 = [0.0, 0.0, 0.0]
  @proj.Crs::new(d)
}
```

## What it gives

- `transform(from, to, x, y)`: the point in `to`'s coordinates, shifting datums through WGS 84 where both are known; `None` where a projection cannot reach the point or the input is not finite. Geographic coordinates are longitude, latitude in degrees; projected ones easting, northing.
- `Crs::from_epsg(code)`: the codes the module lists itself: WGS 84 (4326) and Web Mercator (3857), WGS 84 UTM zones, and Japan's datums (Tokyo, JGD2000, JGD2011) with their plane rectangular and UTM zones. `None` for any other code.
- `Crs::new(definition)`: any other CRS, from a `Definition`: what a PROJ string says, already parsed. `Definition::new(method, a, b)` starts one, and the fields are the PROJ parameters (`lat0`, `long0`, `lat1`, `lat2`, `lat_ts`, `k0`, `x0`, `y0`, `towgs84` with 3 or 7 parameters, `to_meter`, `zone`, `south`, …), angles in radians, NaN for a parameter not given. `None` if the parameters are outside the projection's domain.
- `Method`, the projections: `LongLat`, `Merc`, `Tmerc` (Poder/Engsager's extended series), `Utm`, `Lcc`, `Aea`, `Aeqd`, `Stere`, `Sterea`, `Cass`, `Laea`, `Eqc`, `Eqdc`, `Sinu`, `Eck6`, `Moll`, `Robin`, `Cea`, `Mill`, `Poly`, `Omerc`, `Somerc`, `Krovak`, `Ortho`, `Gnom`, `Eqearth`, `Bonne`.
- `Crs::is_geographic()`.
- `trig`: `from_epsg` and `new` take a `Trig` (default `Trig::moonbit()`). Pass a wasm host's `Math` to compute exactly as proj4js does.

Not here: a PROJ string or WKT parser (mbt-map parses them in TypeScript and hands over 34 numbers, which `Definition::decode` reads: "CRS definition" in the repository's `docs/dev/FORMATS.md`), grid shifts (`+nadgrids`), vertical datums and axis orders other than easting, northing.

## Matching proj4js

The repository compares the module with proj4js 2.22.0 on every EPSG code it knows and on PROJ strings for each projection, both ways (`proj:golden`): within 1 mm and 1e-8°.

## License

Apache-2.0 for the port; proj4js is MIT, and its Equal Earth projection Apache-2.0 (see `NOTICE`).
