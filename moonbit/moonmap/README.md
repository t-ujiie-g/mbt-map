# t-ujiie-g/moonmap

Maps and WebGIS for MoonBit web apps (js target): a typed MoonBit API over the [`moon-map`](https://www.npmjs.com/package/moon-map) npm package, which does the drawing (its workers and WebAssembly come with it).

```sh
moon add t-ujiie-g/moonmap
npm install moon-map   # bundled by your app's bundler (Vite, esbuild, …)
```

```moonbit
let tokyo = @moonmap.lnglat(139.7671, 35.6812)
let map = @moonmap.Map::new(
  "map",
  style=Url("https://example.com/style.json"),
  center=tokyo,
  zoom=14.0,
)
map.on(Load, _ => {
  map.add_source("places", {
    "type": "geojson",
    "data": { "type": "Point", "coordinates": [tokyo.lng, tokyo.lat] },
  })
  map.add_layer({ "id": "places", "type": "circle", "source": "places" })
})
|> ignore
map.on_layer(Click, ["places"], e => map.fly_to(center?=e.lnglat, zoom=16.0)) |> ignore
```

Styles, sources and layers follow MapLibre's style specification, written as MoonBit JSON for now.

Licensed under the Apache License 2.0.
