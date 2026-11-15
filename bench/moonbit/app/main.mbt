///|
/// Hands `value` to the pack test as `window.__moonbit[key]`.
extern "js" fn report(key : String, value : @moonmap.JsValue) -> Unit =
  #|(k, v) => { (window.__moonbit ??= {})[k] = v; }

///|
/// Tells the pack test the map has loaded (`window.__loaded`, as every test page does).
extern "js" fn mark_loaded() -> Unit =
  #|() => { window.__loaded = performance.now(); }

///|
fn main {
  let tokyo = @moonmap.lnglat(139.7671, 35.6812)
  let map = @moonmap.Map::new(
    "map",
    style=@style.Style::new(sources=[], layers=[
      @style.background("background", background_color=@expr.color("#ffffff")),
    ]),
    center=tokyo,
    zoom=14.0,
    attribution=false,
  )
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
      let names : Array[Json] = features.map(f => {
        match f.properties {
          Object(o) => o.get("name").unwrap_or(Json::null())
          _ => Json::null()
        }
      })
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
        @moonmap.json_to_js({
          "layers": Json::array(map.layer_ids().map(Json::string)),
          "point": [at.x, at.y],
          "features": Json::array(names),
          "layer": Json::array(features.map(f => Json::string(f.layer))),
          "paint": paint,
          "zoom": map.zoom(),
          "bearing": map.bearing(),
          "center": [c.lng, c.lat],
          "moved": moved > 0,
          "movesAfterOff": moves.val - moved,
        }),
      )
    })
  })
  |> ignore
}
