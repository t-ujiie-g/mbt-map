///|
/// A small style in Liberty's shape: a road number, a place name, the buildings and a raster.
let liberty_like : Json = {
  "version": 8,
  "glyphs": "https://example.test/fonts/{fontstack}/{range}.pbf",
  "sources": {
    "openmaptiles": { "type": "vector", "url": "https://example.test/planet" },
    "ne2_shaded": {
      "type": "raster",
      "tiles": ["https://example.test/{z}/{x}/{y}.png"],
    },
  },
  "layers": [
    { "id": "natural_earth", "type": "raster", "source": "ne2_shaded" },
    {
      "id": "building-3d",
      "type": "fill-extrusion",
      "source": "openmaptiles",
      "source-layer": "building",
      "paint": { "fill-extrusion-color": "#ccc" },
    },
    {
      "id": "shield",
      "type": "symbol",
      "source": "openmaptiles",
      "layout": { "text-field": ["to-string", ["get", "ref"]] },
    },
    {
      "id": "label_city",
      "type": "symbol",
      "source": "openmaptiles",
      "layout": {
        "text-field": [
          "case",
          ["has", "name:nonlatin"],
          ["get", "name:nonlatin"],
          ["get", "name"],
        ],
      },
    },
  ],
}

///|
fn layer_of(style : Json, id : String) -> Json? {
  guard style is { "layers": Array(layers), .. } else { None }
  for layer in layers {
    if layer is { "id": String(i), .. } && i == id {
      return Some(layer)
    }
  }
  None
}

///|
test "text_field coalesces the language's name keys" {
  assert_eq(Chinese.text_field().to_json(), [
    "coalesce",
    ["get", "name:zh-Hans"],
    ["get", "name:zh"],
    ["get", "name"],
  ])
  assert_eq(Japanese.text_field().to_json(), [
    "coalesce",
    ["get", "name:ja"],
    ["get", "name"],
  ])
  assert_eq(English.text_field().to_json(), [
    "coalesce",
    ["get", "name:en"],
    ["get", "name_en"],
    ["get", "name"],
  ])
  assert_eq(Local.text_field().to_json(), ["get", "name"])
}

///|
test "name_of picks the first name key a feature has" {
  let props : Json = {
    "name": "東京",
    "name:zh": "东京",
    "name_en": "Tokyo",
  }
  assert_eq(Chinese.name_of(props), Some("东京"))
  assert_eq(Japanese.name_of(props), Some("東京"))
  assert_eq(English.name_of(props), Some("Tokyo"))
  assert_eq(Local.name_of({ "class": "building" }), None)
  assert_eq(Local.name_of(Json::null()), None)
}

///|
test "name_layers lists symbol layers drawing names, not road numbers" {
  assert_eq(name_layers(liberty_like), ["label_city"])
  assert_eq(name_layers(Json::null()), [])
  assert_eq(reads_name(["concat", ["get", "name:latin"], " "]), true)
  assert_eq(reads_name(["get", "ref"]), false)
}

///|
test "restyle sets names and raises or flattens the buildings" {
  guard layer_of(liberty_like, "label_city") is Some(label) else {
    fail("no label")
  }
  assert_eq(restyle(label, labels=Local, raised=false), {
    "id": "label_city",
    "type": "symbol",
    "source": "openmaptiles",
    "layout": { "text-field": ["get", "name"] },
  })
  guard layer_of(liberty_like, "building-3d") is Some(buildings) else {
    fail("no buildings")
  }
  guard restyle(buildings, labels=Local, raised=true)
    is { "paint": Object(raised), .. } else {
    fail("no paint")
  }
  assert_eq(raised.get("fill-extrusion-height"), Some(["get", "render_height"]))
  assert_eq(raised.get("fill-extrusion-color"), Some("#ccc"))
  guard restyle(buildings, labels=Local, raised=false)
    is { "paint": Object(flat), .. } else {
    fail("no paint")
  }
  assert_eq(flat.get("fill-extrusion-height"), Some(0))
  guard layer_of(liberty_like, "shield") is Some(shield) else {
    fail("no shield")
  }
  assert_eq(restyle(shield, labels=Japanese, raised=true), shield)
}

///|
test "with_property leaves the layer it copies alone" {
  let layer : Json = { "id": "a", "type": "symbol" }
  let changed = with_property(layer, "layout", "text-size", @expr.num(12.0))
  assert_eq(changed, {
    "id": "a",
    "type": "symbol",
    "layout": { "text-size": 12 },
  })
  assert_eq(layer, { "id": "a", "type": "symbol" })
}

///|
test "openfreemap_style adds the cities and a plain-text attribution" {
  let style = openfreemap_style(
    liberty_like,
    labels=Japanese,
    raised=false,
    fixtures=None,
  ).to_json()
  guard style is { "sources": Object(sources), "layers": Array(layers), .. } else {
    fail("not a style")
  }
  assert_eq(
    sources.get("openmaptiles"),
    Some({
      "type": "vector",
      "url": "https://example.test/planet",
      "attribution": openfreemap_attribution,
    }),
  )
  assert_eq(sources.contains("cities"), true)
  assert_eq(sources.contains("ne2_shaded"), true)
  assert_eq(
    layers.map(l => if l is { "id": String(id), .. } { id } else { "" }),
    [
      "natural_earth", "building-3d", "shield", "label_city", "cities", "city-names",
    ],
  )
  assert_eq(name_layers(style), ["label_city", "city-names"])
  guard layer_of(style, "city-names") is Some({ "layout": layout, .. }) else {
    fail("no city names")
  }
  guard layout is { "text-field": field, .. } else { fail("no text-field") }
  assert_eq(field, Japanese.text_field().to_json())
  // The document it was made from is unchanged.
  guard liberty_like is { "layers": Array(original), .. } else { fail("") }
  assert_eq(original.length(), 4)
}

///|
test "openfreemap_style takes tiles and sprite from the fixtures" {
  let style = openfreemap_style(
    liberty_like,
    labels=Chinese,
    raised=true,
    fixtures=Some("http://localhost/fixtures/"),
  ).to_json()
  guard style is { "sources": Object(sources), .. } else { fail("not a style") }
  assert_eq(sources.contains("ne2_shaded"), false)
  guard sources.get("openmaptiles") is Some({ "tiles": tiles, .. }) else {
    fail("no tiles")
  }
  assert_eq(tiles, ["http://localhost/fixtures/ofm-planet/{z}/{x}/{y}.pbf"])
  guard style is { "sprite": sprite, .. } else { fail("no sprite") }
  assert_eq(sprite, "http://localhost/fixtures/sprites/ofm/sprite")
  assert_eq(style is { "glyphs": _, .. }, false)
  assert_eq(layer_of(style, "natural_earth"), None)
}

///|
test "openfreemap_style falls back to GSI on a document that is not a style" {
  let style = openfreemap_style(
    Json::null(),
    labels=Chinese,
    raised=false,
    fixtures=None,
  ).to_json()
  guard style is { "sources": Object(sources), .. } else { fail("not a style") }
  assert_eq(sources.keys().collect(), ["gsi", "cities"])
}

///|
test "gsi_style draws GSI's tiles under the cities" {
  let live = gsi_style(labels=English, fixtures=None).to_json()
  guard live is { "sources": { "gsi": { "tiles": tiles, .. }, .. }, .. } else {
    fail("no gsi source")
  }
  assert_eq(tiles, ["https://cyberjapandata.gsi.go.jp/xyz/pale/{z}/{x}/{y}.png"])
  assert_eq(name_layers(live), ["city-names"])
  let offline = gsi_style(labels=English, fixtures=Some("http://localhost/f/")).to_json()
  guard offline is { "sources": { "gsi": { "tiles": tiles, .. }, .. }, .. } else {
    fail("no gsi source")
  }
  assert_eq(tiles, ["http://localhost/f/gsi-std/{z}/{x}/{y}.png"])
}

///|
test "cities_geojson names each city in each language" {
  guard cities_geojson() is { "features": Array(features), .. } else {
    fail("not a collection")
  }
  assert_eq(features.length(), cities.length())
  guard features[0] is { "properties": props, .. } else {
    fail("no properties")
  }
  assert_eq(English.name_of(props), Some("Beijing"))
  assert_eq(Japanese.name_of(props), Some("北京"))
}
