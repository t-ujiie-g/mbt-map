///|
let base : String = "https://example.com/styles/style.json"

///|
fn doc(spec : Json) -> @web.StyleDoc raise {
  @web.StyleDoc::from_js(@web.json_to_js(spec))
}

///|
fn no_documents(_ : String) -> Json? {
  None
}

///|
test "engine resolves tile templates against the style URL and keeps the placeholders" {
  let s = doc({
    "version": 8,
    "sources": {
      "v": { "type": "vector", "tiles": ["../tiles/{z}/{x}/{y}.pbf", 7] },
      "p": {
        "type": "vector",
        "tiles": ["pmtiles://data/a.pmtiles/{z}/{x}/{y}"],
      },
    },
    "layers": [],
  })
  let e = s.engine({}, no_documents, base)
  guard e.drawn.get("sources") is Some(Object(sources)) else {
    fail("no sources")
  }
  assert_eq(
    sources.get("v"),
    Some({
      "type": "vector",
      "tiles": ["https://example.com/tiles/{z}/{x}/{y}.pbf", 7],
    }),
  )
  assert_eq(
    sources.get("p"),
    Some({
      "type": "vector",
      "tiles": [
        "pmtiles://https://example.com/styles/data/a.pmtiles/{z}/{x}/{y}",
      ],
    }),
  )
  assert_eq(
    s.to_js().get("sources").get("v").to_json(),
    Some({ "type": "vector", "tiles": ["../tiles/{z}/{x}/{y}.pbf", 7] }),
  )
  let bad = doc({
    "version": 8,
    "sources": { "v": { "type": "vector", "tiles": ["data:,x"] } },
    "layers": [],
  })
  let message = try {
    bad.engine({}, no_documents, base) |> ignore
    ""
  } catch {
    e => e.message()
  }
  assert_eq(message, "moon-map: tiles must be an http(s) URL: data:,x")
}

///|
test "engine splits GeoJSON data off and hands it to the worker as it was given" {
  let s = doc({
    "version": 8,
    "sources": {
      "g": {
        "type": "geojson",
        "data": { "type": "FeatureCollection", "features": [] },
        "cluster": true,
      },
      "u": { "type": "geojson", "data": "d.json" },
    },
    "layers": [{ "id": "x", "type": "circle", "source": "g" }],
  })
  let e = s.engine({}, no_documents, base)
  assert_eq(e.geojson.map(g => g.0), ["g", "u"])
  assert_eq(
    e.geojson[0].1.json_text(),
    "{\"type\":\"geojson\",\"data\":{\"type\":\"FeatureCollection\",\"features\":[]},\"cluster\":true}",
  )
  assert_eq(e.geojson[1].1.get("data").json_text(), "\"d.json\"")
  guard e.drawn.get("sources") is Some(Object(sources)) else {
    fail("no sources")
  }
  assert_eq(
    sources.get("g"),
    Some({ "type": "geojson", "data": null, "cluster": true }),
  )
  assert_true(e.text.contains("\"data\":null"))
}

///|
test "engine hands the global state over as the style's defaults" {
  let s = doc({
    "version": 8,
    "sources": {},
    "layers": [],
    "state": { "a": { "default": 1 } },
  })
  let e = s.engine({ "a": 2, "b": null }, no_documents, base)
  assert_eq(
    e.drawn.get("state"),
    Some({ "a": { "default": 2 }, "b": { "default": null } }),
  )
  assert_eq(
    s.engine({}, no_documents, base).drawn.get("state"),
    Some({ "a": { "default": 1 } }),
  )
}

///|
fn tilejson_style() -> @web.StyleDoc raise {
  doc({
    "version": 8,
    "sources": {
      "v": { "type": "vector", "url": "../tiles.json", "maxzoom": 12 },
      "r": { "type": "raster", "url": "https://other.org/r.json" },
      "own": {
        "type": "vector",
        "url": "x.json",
        "tiles": ["https://t/{z}/{x}/{y}.pbf"],
      },
      "g": { "type": "geojson", "data": "d.json" },
    },
    "layers": [
      { "id": "a", "type": "line", "source": "v" },
      { "id": "b", "type": "raster", "source": "r" },
    ],
  })
}

///|
test "tilejson_urls lists the url sources without tiles, absolute and http(s) only" {
  let urls = tilejson_style().tilejson_urls(base)
  assert_eq(urls.to_array(), [
    ("v", "https://example.com/tiles.json"),
    ("r", "https://other.org/r.json"),
  ])
  let bad = doc({
    "version": 8,
    "sources": { "x": { "type": "vector", "url": "file:///etc/x.json" } },
    "layers": [],
  })
  let message = try {
    bad.tilejson_urls(base) |> ignore
    ""
  } catch {
    e => e.message()
  }
  assert_eq(
    message, "moon-map: source \"x\": url must be an http(s) URL: file:///etc/x.json",
  )
  let p = doc({
    "version": 8,
    "sources": {
      "p": { "type": "vector", "url": "pmtiles://a.pmtiles" },
      "t": { "type": "geotiff", "url": "dem.tif" },
    },
    "layers": [],
  })
  assert_eq(p.tilejson_urls(base).to_array(), [
    ("p", "pmtiles://https://example.com/styles/a.pmtiles"),
    ("t", "geotiff:https://example.com/styles/dem.tif"),
  ])
}

///|
test "engine merges TileJSON documents (the source's own keys win) and leaves out sources still loading" {
  let documents = (url : String) => {
    if url == "https://example.com/tiles.json" {
      Some(
        (
          {
            "tiles": ["v/{z}/{x}/{y}.pbf"],
            "minzoom": 2,
            "maxzoom": 14,
            "attribution": "© V",
            "bounds": [1, 2, 3, 4],
            "vector_layers": [],
          } : Json),
      )
    } else {
      None
    }
  }
  let e = tilejson_style().engine({}, documents, base)
  guard e.drawn.get("sources") is Some(Object(sources)) else {
    fail("no sources")
  }
  assert_eq(
    sources.get("v"),
    Some({
      "tiles": ["https://example.com/v/{z}/{x}/{y}.pbf"],
      "minzoom": 2,
      "maxzoom": 12,
      "attribution": "© V",
      "bounds": [1, 2, 3, 4],
      "type": "vector",
    }),
  )
  assert_false(sources.contains("r"))
  assert_eq(
    e.drawn.get("layers"),
    Some([{ "id": "a", "type": "line", "source": "v" }]),
  )
  assert_eq(
    sources.get("own"),
    Some({
      "type": "vector",
      "url": "x.json",
      "tiles": ["https://t/{z}/{x}/{y}.pbf"],
    }),
  )
}

///|
test "engine converts a style with legacy filters through the converter it is given" {
  let s = doc({
    "version": 8,
    "sources": {},
    "layers": [{ "id": "bg", "type": "background", "filter": ["==", "a", 1] }],
  })
  let convert = (v : @web.JsValue) => {
    ignore(v)
    @web.json_to_js({ "version": 8, "sources": {}, "layers": [] })
  }
  assert_eq(
    s.engine({}, no_documents, base, convert~).drawn.get("layers"),
    Some([]),
  )
  assert_eq(
    s.engine({}, no_documents, base).drawn.get("layers"),
    Some([{ "id": "bg", "type": "background", "filter": ["==", "a", 1] }]),
  )
}

///|
test "style_warnings pairs the engine's paths and messages and names each warning's layer" {
  let drawn : Map[String, Json] = {
    "version": 8,
    "sources": {},
    "layers": [{ "id": "a" }, { "id": "b" }],
  }
  assert_eq(
    @web.style_warnings(drawn, [
      "layers[1].paint.line-blur", "not drawn yet", "sources.s.tiles", "only http(s) tile URLs",
      "layers[7]", "gone",
    ]),
    [
      {
        "path": "layers[1].paint.line-blur",
        "layer": "b",
        "message": "not drawn yet",
      },
      { "path": "sources.s.tiles", "message": "only http(s) tile URLs" },
      { "path": "layers[7]", "message": "gone" },
    ],
  )
}
