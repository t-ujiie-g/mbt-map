///|
/// Hands `value` to the pack test as `window.__moonbit[key]`.
extern "js" fn report(key : String, value : @mbtmap.JsValue) -> Unit =
  #|(k, v) => { (window.__moonbit ??= {})[k] = v; }

///|
/// Tells the pack test the map has loaded (`window.__loaded`, as every test page does).
extern "js" fn mark_loaded() -> Unit =
  #|() => { window.__loaded = performance.now(); }

///|
/// Hands the map to the pack test as `window.__mbtmap`, which reads what the API cannot (feature state).
extern "js" fn expose(map : @mbtmap.Map) -> Unit =
  #|(m) => { window.__mbtmap = m; }

///|
fn names(features : Array[@mbtmap.Feature]) -> Json {
  Json::array(
    features.map(f => {
      match f.properties {
        Object(o) => o.get("name").unwrap_or(Json::null())
        _ => Json::null()
      }
    }),
  )
}

///|
fn style_part(map : @mbtmap.Map, key : String) -> Json {
  match map.style() {
    Some(Object(s)) => s.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
/// Calls the methods the first round leaves out, reporting what each left behind as
/// `window.__moonbit.more`, and on a click on the station a restyle and `remove`.
fn second_round(map : @mbtmap.Map, tokyo : @mbtmap.LngLat) -> Unit {
  map.set_layout("places", "circle-sort-key", Some(@expr.num(1.0)))
  map.set_filter("places", Some(@expr.eq(@expr.get("kind"), @expr.str("駅"))))
  map.add_layer(@style.circle("extra", source="places"))
  map.move_layer("extra", before="places")
  let moved = map.layer_ids()
  map.remove_layer("extra")
  map.add_source(
    "tmp",
    @style.geojson_source(data={ "type": "FeatureCollection", "features": [] }),
  )
  let with_tmp = match style_part(map, "sources") {
    Object(o) => o.contains("tmp")
    _ => false
  }
  map.remove_source("tmp")
  let without_tmp = match style_part(map, "sources") {
    Object(o) => !o.contains("tmp")
    _ => false
  }
  map.set_data("places", {
    "type": "Feature",
    "id": 1,
    "properties": { "name": "東京駅", "kind": "駅" },
    "geometry": { "type": "Point", "coordinates": [tokyo.lng, tokyo.lat] },
  })
  map.set_feature_state("places", Json::number(1.0), { "selected": true })
  map.jump_to(pitch=30.0)
  let pitch = map.pitch()
  map.ease_to(center=tokyo, zoom=16.0, bearing=0.0, pitch=0.0, duration=0.0)
  let eased = map.zoom()
  map.fit_bounds(
    { west: 139.76, south: 35.67, east: 139.77, north: 35.69, },
    padding=10.0,
    max_zoom=17.0,
    duration=0.0,
  )
  let fitted = map.center()
  let back = map.unproject(map.project(tokyo))
  let layers = match style_part(map, "layers") {
    Array(ls) => ls
    _ => []
  }
  let places = layers.filter(l => l is Object({ "id": String("places"), .. }))
  map.query_rendered_features(layers=["nope"], features => {
    report(
      "unknownLayer",
      @mbtmap.json_to_js(Json::number(features.length().to_double())),
    )
  })
  map.on_layer(Click, ["places"], e => {
    report("clicked", @mbtmap.json_to_js(names(e.features)))
    map.set_style(
      @style.Style::new(sources=[], layers=[
        @style.background("background", background_color=@expr.color("#ff0000")),
      ]),
    )
    report(
      "restyled",
      @mbtmap.json_to_js(Json::array(map.layer_ids().map(Json::string))),
    )
    map.remove()
  })
  |> ignore
  report(
    "more",
    @mbtmap.json_to_js({
      "moved": Json::array(moved.map(Json::string)),
      "removed": Json::array(map.layer_ids().map(Json::string)),
      "sourceAdded": with_tmp,
      "sourceRemoved": without_tmp,
      "places": Json::array(places),
      "pitch": pitch,
      "eased": eased,
      "fitted": [fitted.lng, fitted.lat],
      "back": [back.lng, back.lat],
    }),
  )
}

///|
fn main {
  let tokyo = @mbtmap.lnglat(139.7671, 35.6812)
  let map = @mbtmap.Map::new(
    "map",
    style=@style.Style::new(sources=[], layers=[
      @style.background("background", background_color=@expr.color("#ffffff")),
    ]),
    center=tokyo,
    zoom=14.0,
    attribution=false,
  )
  expose(map)
  let moves = Ref(0)
  let counting = map.on(Move, _ => moves.val += 1)
  let stage = Ref(0)
  map.on(Load, _ => {
    map.add_source(
      "places",
      @style.geojson_source(data={
        "type": "Feature",
        "properties": { "name": "東京駅", "kind": "駅" },
        "geometry": { "type": "Point", "coordinates": [tokyo.lng, tokyo.lat] },
      }),
    )
    map.add_layer(
      @style.circle(
        "places",
        source="places",
        circle_radius=@expr.num(20.0),
        circle_color=@expr.match_(
          @expr.get("kind"),
          [("駅", @expr.color("#ff0000"))],
          default=@expr.color("#000000"),
        ),
      ),
    )
    stage.val = 1
    mark_loaded()
  })
  |> ignore
  // `Idle` also comes right after `Load` (the first view settled, as MapLibre fires it): the one
  // after that has the layer added on load drawn.
  map.on(Idle, _ => {
    stage.val += 1
    guard stage.val == 3 else { return }
    let at = map.project(tokyo)
    map.query_rendered_features(point=at, layers=["places"], fn(features) {
      map.set_paint("places", "circle-color", Some(@expr.color("#0000ff")))
      map.jump_to(zoom=15.0, bearing=10.0)
      let moved = moves.val
      counting.off()
      map.jump_to(zoom=15.5)
      let style = map.style()
      let paint = match style {
        Some(Object(s)) =>
          match s.get("layers") {
            Some(Array(layers)) =>
              match layers[layers.length() - 1] {
                Object(l) => l.get("paint").unwrap_or(Json::null())
                _ => Json::null()
              }
            _ => Json::null()
          }
        _ => Json::null()
      }
      let c = map.center()
      report(
        "result",
        @mbtmap.json_to_js({
          "layers": Json::array(map.layer_ids().map(Json::string)),
          "point": [at.x, at.y],
          "features": names(features),
          "layer": Json::array(features.map(f => Json::string(f.layer))),
          "paint": paint,
          "zoom": map.zoom(),
          "bearing": map.bearing(),
          "center": [c.lng, c.lat],
          "moved": moved > 0,
          "movesAfterOff": moves.val - moved,
        }),
      )
      second_round(map, tokyo)
    })
  })
  |> ignore
}
