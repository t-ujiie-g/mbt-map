# mvt

A [Mapbox Vector Tile](https://github.com/mapbox/vector-tile-spec) (2.1) decoder in MoonBit, reading tiles as [@mapbox/vector-tile](https://github.com/mapbox/vector-tile-js) does. Pure MoonBit on every backend (wasm, wasm-gc, js, native); it depends only on [`t-ujiie-g/pbf`](https://mooncakes.io/docs/t-ujiie-g/pbf).

Part of [mbt-map](https://github.com/t-ujiie-g/mbt-map), a WebGIS library, whose display worker decodes its tiles with it; published on its own.

```sh
moon add t-ujiie-g/mvt
```

```moonbit
/// The points of every polygon feature of the layer `name` whose `class` is "park".
fn park_points(bytes : Bytes, name : String) -> Int raise @mvt.MvtError {
  let tile = @mvt.Tile::parse(bytes[:])
  guard tile.layer(name) is Some(layer) else { return 0 }
  guard layer.key_index("class") is Some(class) else { return 0 }
  let geometry = @mvt.Geometry::new()
  let mut points = 0
  for i in 0..<layer.length() {
    guard layer.geom_type(i) is Polygon else { continue }
    guard layer.property(i, class) is Some(String("park")) else { continue }
    if layer.decode_geometry(i, geometry) {
      points += geometry.num_points()
    }
  }
  points
}
```

## What it gives

- `Tile::parse(bytes)`: the layers, with their key and value tables, feature headers and tags decoded and checked. Geometry stays encoded until asked for. `Tile::layer(name)` gives the last layer of that name, as other decoders resolve duplicates.
- `Layer`: `name`, `version`, `extent` (4096 if the tile gives none), `keys`, `values`, and the features by index in `0..<length()`, stored in columns (no object per feature): `geom_type(i)`, `id(i)`, `property(i, key_index)` (no allocation; resolve `key_index(key)` once per layer), `tag_count(i)` / `tag(i, k)`, `properties(i)` (a map).
- `Layer::decode_geometry(i, out)`: feature `i`'s geometry into a reusable `Geometry` (`coords` as x, y pairs in tile units, `ring_ends`), with the rings `@mapbox/vector-tile`'s `loadGeometry` gives. It returns false on a malformed command stream and `Geometry::error()` says why. `Layer::load_geometry(i)` is the allocating form, one array of points per ring.
- `Value`: `String`, `Float`, `Double`, `Int`, `UInt`, `SInt`, `Bool`, and `Null` for a value message with no field set (the spec forbids it, other decoders accept it).
- `MvtError`: `Malformed` (the protobuf error), `InvalidCommand`, `IndexOutOfRange`, `OddTagCount`, each with the byte offset, and `message()`.

There is no encoder, and polygon rings are not classified into polygons (their winding gives that; mbt-map does it while tessellating).

The tile is treated as untrusted: tag indices are checked against the tables, command counts against the bytes left, and no input loops forever.

## Matching @mapbox/vector-tile

The repository compares the decoder with @mapbox/vector-tile on real tiles (`mvt:golden`): layer version and extent, and every feature's id, type, properties and geometry are the same on the js backend; the wasm-gc build is checked by point counts, property counts and coordinate sums.

## License

Apache-2.0. The module is written from the Vector Tile Specification and contains no third-party code (see `NOTICE`).
