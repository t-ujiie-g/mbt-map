///|
fn style() -> @web.StyleDoc raise {
  @web.StyleDoc::from_js(
    @web.json_to_js({
      "version": 8,
      "sources": {
        "v": { "type": "vector", "tiles": ["https://x/{z}/{x}/{y}.pbf"] },
        "g": {
          "type": "geojson",
          "data": { "type": "FeatureCollection", "features": [] },
        },
      },
      "layers": [
        { "id": "bg", "type": "background" },
        {
          "id": "a",
          "type": "fill",
          "source": "v",
          "source-layer": "a",
          "paint": { "fill-color": "#f00" },
        },
        {
          "id": "b",
          "type": "line",
          "source": "v",
          "source-layer": "b",
          "filter": ["==", "k", 1],
        },
      ],
    }),
  )
}

///|
fn refused(f : () -> Unit raise @web.StyleEditError) -> String {
  try {
    f()
    ""
  } catch {
    e => e.message()
  }
}

///|
test "add_layer, remove_layer and move_layer keep MapLibre's order and leave the document alone" {
  let s = style()
  let c : Json = { "id": "c", "type": "circle", "source": "g" }
  assert_eq(s.add_layer(c, before="a").layer_ids(), ["bg", "c", "a", "b"])
  assert_eq(s.layer_ids(), ["bg", "a", "b"])
  assert_eq(s.add_layer(c).layer_ids(), ["bg", "a", "b", "c"])
  assert_eq(s.remove_layer("a").layer_ids(), ["bg", "b"])
  assert_eq(s.move_layer("b", before="a").layer_ids(), ["bg", "b", "a"])
  assert_eq(s.move_layer("bg").layer_ids(), ["a", "b", "bg"])
  assert_eq(
    refused(() => {
      s.add_layer({ "id": "a", "type": "fill", "source": "v" }) |> ignore
    }),
    "moon-map: the style already has a layer \"a\"",
  )
  assert_eq(
    refused(() => {
      s.add_layer({ "id": "c", "type": "fill", "source": "nope" }) |> ignore
    }),
    "moon-map: layer \"c\": the style has no source \"nope\"",
  )
  assert_eq(
    refused(() => s.add_layer({ "id": "c", "type": "fill" }) |> ignore),
    "moon-map: layer \"c\": the style has no source \"undefined\"",
  )
  assert_eq(
    refused(() => {
      s.add_layer({ "id": "c", "type": "fill", "source": "v" }, before="nope")
      |> ignore
    }),
    "moon-map: the style has no layer \"nope\"",
  )
  assert_eq(
    refused(() => s.add_layer({ "type": "fill" }) |> ignore),
    "moon-map: a layer needs an id and a type",
  )
  assert_eq(
    refused(() => s.remove_layer("nope") |> ignore),
    "moon-map: the style has no layer \"nope\"",
  )
  assert_eq(
    refused(() => s.move_layer("a", before="nope") |> ignore),
    "moon-map: the style has no layer \"nope\"",
  )
}

///|
test "paint, layout, filter and zoom range edits touch one layer and keep the order of its properties" {
  let s = style()
  let painted = s.set_paint("a", "fill-opacity", Some(0.5))
  assert_eq(painted.paint("a", "fill-opacity"), Some(0.5))
  assert_eq(s.paint("a", "fill-opacity"), None)
  let cleared = painted.set_paint("a", "fill-color", None)
  assert_eq(cleared.paint("a", "fill-color"), None)
  assert_eq(cleared.paint("a", "fill-opacity"), Some(0.5))
  let recolored = painted.set_paint("a", "fill-color", Some("#fff"))
  guard recolored.layer("a") is Some(Object(l)) &&
    l.get("paint") is Some(Object(p)) else {
    fail("no paint")
  }
  assert_eq(p.keys().collect(), ["fill-color", "fill-opacity"])
  let hidden = s.set_layout("b", "visibility", Some("none"))
  assert_eq(hidden.layout("b", "visibility"), Some("none"))
  assert_eq(hidden.layer("a"), s.layer("a"))
  assert_eq(
    s.set_filter("a", Some(["has", "k"])).filter("a"),
    Some(["has", "k"]),
  )
  assert_eq(s.set_filter("b", None).filter("b"), None)
  guard s.set_zoom_range("a", 10, 16).layer("a") is Some(Object(r)) else {
    fail("no layer")
  }
  assert_eq([r.get("minzoom"), r.get("maxzoom")], [Some(10), Some(16)])
  let e = try {
    s.set_zoom_range("a", 16, 10) |> ignore
    None
  } catch {
    e => Some(e)
  }
  assert_true(e is Some(OutOfRange(_)))
  assert_eq(
    refused(() => s.set_paint("nope", "fill-color", Some("#000")) |> ignore),
    "moon-map: the style has no layer \"nope\"",
  )
}

///|
test "sources are added, refused while used, and GeoJSON data replaced and kept apart" {
  let s = style()
  let added = s.add_source(
    "d",
    @web.json_to_js({
      "type": "raster-dem",
      "tiles": ["https://x/{z}/{x}/{y}.png"],
    }),
  )
  assert_true(added.has_source("d"))
  assert_eq(
    refused(() => {
      s.add_source("v", @web.json_to_js({ "type": "vector" })) |> ignore
    }),
    "moon-map: the style already has a source \"v\"",
  )
  assert_eq(
    refused(() => s.add_source("e", @web.json_to_js({})) |> ignore),
    "moon-map: source \"e\" needs a type",
  )
  assert_false(s.remove_source("g").has_source("g"))
  assert_eq(
    refused(() => s.remove_source("v") |> ignore),
    "moon-map: source \"v\" is used by layer \"a\"",
  )
  assert_eq(
    refused(() => {
      added.set_root("terrain", Some({ "source": "d" })).remove_source("d")
      |> ignore
    }),
    "moon-map: source \"d\" is used by the terrain",
  )
  assert_eq(
    refused(() => s.remove_source("nope") |> ignore),
    "moon-map: the style has no source \"nope\"",
  )
  let data : Json = {
    "type": "FeatureCollection",
    "features": [
      {
        "type": "Feature",
        "geometry": { "type": "Point", "coordinates": [1, 2] },
        "properties": {},
      },
    ],
  }
  let replaced = s.set_source_data("g", @web.json_to_js(data))
  assert_eq(replaced.source_data("g").map(d => d.to_json()), Some(Some(data)))
  guard replaced.source("g") is Some(Object(g)) else { fail("no source") }
  assert_eq(g.get("data"), Some(Json::null()))
  let url = s.set_source_data("g", @web.json_to_js("https://x/data.json"))
  assert_eq(
    url.source_data("g").map(d => d.to_json()),
    Some(Some("https://x/data.json")),
  )
  assert_eq(
    refused(() => s.set_source_data("v", @web.json_to_js(data)) |> ignore),
    "moon-map: source \"v\" is not a GeoJSON source",
  )
}

///|
test "keep_data keeps the old data value where the new document writes it alike" {
  let s = style()
  let again = style().keep_data(Some(s))
  assert_true(again.source_data("g") is Some(_))
  assert_eq(
    again.to_js().get("sources").get("g").get("data").json_text(),
    s.to_js().get("sources").get("g").get("data").json_text(),
  )
  let url = s.set_source_data("g", @web.json_to_js("https://x/d.json"))
  assert_eq(
    url.keep_data(Some(s)).source_data("g").map(d => d.json_text()),
    Some("\"https://x/d.json\""),
  )
}

///|
test "changed_sources lists new documents' sources and the ones an edit replaced" {
  let s = style()
  assert_eq(s.changed_sources(None), ["v", "g"])
  assert_eq(
    s.set_paint("a", "fill-opacity", Some(1)).changed_sources(Some(s)),
    [],
  )
  let replaced = s.set_source_data("g", @web.json_to_js("https://x/d.json"))
  assert_eq(replaced.changed_sources(Some(s)), ["g"])
  assert_eq(style().changed_sources(Some(s)), ["v", "g"])
}

///|
test "set_root sets and removes top-level properties" {
  let s = style().set_root("projection", Some({ "type": "globe" }))
  assert_eq(s.root("projection"), Some({ "type": "globe" }))
  assert_eq(s.set_root("projection", None).root("projection"), None)
  assert_eq(
    style().set_root("sky", Some({ "sky-color": "#88c6fc" })).root("sky"),
    Some({ "sky-color": "#88c6fc" }),
  )
}

///|
test "custom layers: placeholders need no source and to_js leaves them out unless asked" {
  let s = style().add_layer({ "id": "c", "type": "custom" }, before="a")
  assert_eq(s.layer_ids()[:3].to_owned(), ["bg", "c", "a"])
  let ids = (v : @web.JsValue) => {
    match v.get("layers").to_json() {
      Some(Array(a)) => a.length()
      _ => -1
    }
  }
  assert_eq(ids(s.to_js()), 3)
  assert_eq(ids(s.to_js(custom=true)), 4)
}

///|
test "to_js gives the style back with its GeoJSON data, as a copy" {
  let s = style()
  let js = s.to_js()
  assert_eq(
    js.get("sources").get("g").get("data").json_text(),
    "{\"type\":\"FeatureCollection\",\"features\":[]}",
  )
  assert_eq(js.get("layers").to_json().map(j => j is Array(_)), Some(true))
}

///|
test "sources and properties named like Object.prototype's keys stay plain keys" {
  let base = @web.StyleDoc::from_js(
    @web.json_to_js({
      "version": 8,
      "sources": {
        "__proto__": {
          "type": "vector",
          "tiles": ["https://x/{z}/{x}/{y}.pbf"],
        },
      },
      "layers": [],
    }),
  )
  assert_true(base.has_source("__proto__"))
  assert_false(base.has_source("toString"))
  let added = base.add_source(
    "toString",
    @web.json_to_js({ "type": "geojson", "data": {} }),
  )
  assert_true(added.has_source("toString"))
  assert_eq(
    refused(() => base.remove_source("constructor") |> ignore),
    "moon-map: the style has no source \"constructor\"",
  )
  let painted = base
    .add_layer({ "id": "l", "type": "line", "source": "__proto__" })
    .set_paint("l", "__proto__", Some(1))
  assert_eq(
    painted.to_js().get("layers").to_json(),
    Some([
      {
        "id": "l",
        "type": "line",
        "source": "__proto__",
        "paint": { "__proto__": 1 },
      },
    ]),
  )
}

///|
test "is_legacy_filter is MapLibre's classifyFilter, mixed all/any counting as legacy" {
  let legacy = (f : Json) => @web.is_legacy_filter(Some(f))
  assert_true(legacy(["==", "a", 1]))
  assert_false(legacy(["has", "a"]))
  assert_true(legacy(["has", "$type"]))
  assert_true(legacy(["in", "a", 1, 2]))
  assert_false(legacy(["in", ["get", "a"], ["literal", [1]]]))
  assert_true(legacy(["!has", "a"]))
  assert_false(legacy(["==", ["get", "a"], 1]))
  assert_true(legacy(["all", ["==", ["get", "a"], 1], ["==", "b", 2]]))
  assert_false(legacy(["all", ["==", ["get", "a"], 1]]))
  assert_false(legacy(true))
  assert_true(legacy([]))
  assert_false(@web.is_legacy_filter(None))
  assert_true(
    style()
    .set_paint("a", "fill-color", Some({ "stops": [[0, "#000"]] }))
    .has_legacy(),
  )
  assert_false(
    style().set_filter("b", Some(["==", ["get", "k"], 1])).has_legacy(),
  )
}

///|
test "has_legacy and is_legacy_filter tell styles that need the converter" {
  let one = (layer : Map[String, Json]) => {
    let l : Map[String, Json] = { "id": "a", "type": "fill" }
    for k, v in layer {
      l[k] = v
    }
    @web.StyleDoc::from_json({
      "version": 8,
      "sources": {},
      "layers": [Json::object(l)],
    })
  }
  assert_false(one({ "filter": ["==", ["get", "k"], 1] }).has_legacy())
  assert_true(one({ "filter": ["==", "k", 1] }).has_legacy())
  assert_true(
    one({ "paint": { "fill-color": { "stops": [[0, "#000"]] } } }).has_legacy(),
  )
  assert_false(
    one({
      "paint": { "fill-color": ["get", "c"] },
      "layout": { "visibility": "visible" },
    }).has_legacy(),
  )
  let legacy : Array[Json] = [
    ["in", "k", "a"],
    ["!in", "k"],
    ["!has", "k"],
    ["has", "$type"],
    ["none"],
    ["all", ["==", "k", 1]],
    null,
  ]
  for f in legacy {
    assert_true(@web.is_legacy_filter(Some(f)), msg=f.stringify())
  }
  let expressions : Array[Json] = [
    true,
    ["has", "k"],
    ["in", ["get", "k"], ["literal", []]],
    ["in", "a", ["get", "s"]],
    ["all", ["has", "k"]],
    ["get", "b"],
  ]
  for f in expressions {
    assert_false(@web.is_legacy_filter(Some(f)), msg=f.stringify())
  }
  assert_false(@web.is_legacy_filter(None))
}

///|
extern "js" fn deep_filter(levels : Int32) -> @web.JsValue =
  #|(n) => { let f = ["==", "k", 1]; for (let i = 0; i < n; i++) f = ["all", f]; return f; }

///|
test "filters nested past the engine's depth are left to it, without deep recursion" {
  assert_false(@web.is_legacy_filter_value(deep_filter(100000)))
}
