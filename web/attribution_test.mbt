///|
let attributed : Map[String, Json] = {
  "sources": {
    "a": { "attribution": "Long source A" },
    "b": { "attribution": "B" },
    "c": { "attribution": "source A" },
    "dem": { "attribution": "DEM" },
    "unused": { "attribution": "never" },
    "blank": { "attribution": "  " },
  },
  "layers": [
    { "id": "a", "source": "a" },
    { "id": "b", "source": "b", "minzoom": 10 },
    { "id": "c", "source": "c", "maxzoom": 14 },
    { "id": "hidden", "source": "unused", "layout": { "visibility": "none" } },
    { "id": "blank", "source": "blank" },
  ],
  "terrain": { "source": "dem" },
}

///|
test "attributions: sources of layers shown at the zoom and of the terrain, shortest first" {
  assert_eq(@web.attributions(attributed, 12), ["B", "DEM", "Long source A"])
}

///|
test "attributions: a layer outside its zoom range leaves its source out" {
  assert_eq(@web.attributions(attributed, 8), ["DEM", "Long source A"])
  assert_eq(@web.attributions(attributed, 14), ["B", "DEM", "Long source A"])
  assert_eq(@web.attributions({}, 3), [])
}
