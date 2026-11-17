# t-ujiie-g/mbtmap

Maps and WebGIS for MoonBit web apps (js target): a typed MoonBit API over the [`mbt-map`](https://www.npmjs.com/package/mbt-map) npm package, which does the drawing (its workers and WebAssembly come with it).

```sh
moon add t-ujiie-g/mbtmap
npm install mbt-map   # bundled by your app's bundler (Vite, esbuild, …)
```

```moonbit
let tokyo = @mbtmap.lnglat(139.7671, 35.6812)
let map = @mbtmap.Map::new(
  "map",
  style=@style.Style::url("https://example.com/style.json"),
  center=tokyo,
  zoom=14.0,
)
map.on(Load, _ => {
  map.add_source(
    "places",
    @style.geojson_source(data={
      "type": "Feature",
      "properties": { "kind": "station" },
      "geometry": { "type": "Point", "coordinates": [tokyo.lng, tokyo.lat] },
    }),
  )
  map.add_layer(
    @style.circle(
      "places",
      source="places",
      circle_radius=@expr.num(8.0),
      circle_color=@expr.match_(
        @expr.get("kind"),
        [("station", @expr.color("#2166ac"))],
        default=@expr.color("#d6604d"),
      ),
    ),
  )
})
|> ignore
map.on_layer(Click, ["places"], e => map.fly_to(center?=e.lnglat, zoom=16.0)) |> ignore
```

Documentation, examples and a live demo: **<https://t-ujiie-g.github.io/mbt-map/>** (the MoonBit guide is [there](https://t-ujiie-g.github.io/mbt-map/docs/moonbit.html)).

Packages: `t-ujiie-g/mbtmap` (the map, camera, events, queries), `t-ujiie-g/mbtmap/style` (styles, sources and one function per layer type with its paint and layout properties as labelled arguments, generated from MapLibre's style specification; `Layer::json`, `Source::json` and `Style::json` take JSON as written) and `t-ujiie-g/mbtmap/expr` (expressions).

Licensed under the Apache License 2.0.
