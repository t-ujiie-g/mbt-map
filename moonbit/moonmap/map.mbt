///|
/// A map drawn into a page element (the npm package's `Map`).
#external
pub type Map

///|
#module("moon-map/moonbit")
extern "js" fn create_map(options : JsValue) -> Map = "createMap"

///|
extern "js" fn Map::js(self : Map) -> JsValue =
  #|(m) => m

///|
/// A style: `Url` of a style document (fetched without credentials), or a `Spec` written as JSON
/// (MapLibre's style specification; `@style` builds one with types).
pub(all) enum Style {
  Url(String)
  Spec(Json)
}

///|
fn Style::to_js(self : Style) -> JsValue {
  match self {
    Url(url) => js_string(url)
    Spec(json) => json_to_js(json)
  }
}

///|
/// A screen point in CSS pixels from the map's top-left corner.
#derive(Eq, Debug)
pub(all) struct Point {
  x : Double
  y : Double
}

///|
/// A box in degrees (west may exceed east across the antimeridian).
#derive(Eq, Debug)
pub(all) struct Bounds {
  west : Double
  south : Double
  east : Double
  north : Double
}

///|
fn lnglat_json(p : LngLat) -> Json {
  [p.lng, p.lat]
}

///|
/// The camera options MapLibre's camera methods take, those given only.
fn camera_json(
  center : LngLat?,
  zoom : Double?,
  bearing : Double?,
  pitch : Double?,
) -> @builtin.Map[String, Json] {
  let o : @builtin.Map[String, Json] = @builtin.Map([])
  if center is Some(c) {
    o["center"] = lnglat_json(c)
  }
  if zoom is Some(z) {
    o["zoom"] = Json::number(z)
  }
  if bearing is Some(b) {
    o["bearing"] = Json::number(b)
  }
  if pitch is Some(p) {
    o["pitch"] = Json::number(p)
  }
  o
}

///|
fn put_number(
  o : @builtin.Map[String, Json],
  key : String,
  v : Double?,
) -> Unit {
  if v is Some(n) {
    o[key] = Json::number(n)
  }
}

///|
fn put_bool(o : @builtin.Map[String, Json], key : String, v : Bool?) -> Unit {
  if v is Some(b) {
    o[key] = Json::boolean(b)
  }
}

///|
/// A map in the element with id `container`, drawing `style` (MapLibre's `new Map(options)`).
/// The camera starts at `center` (default 0, 0), `zoom` (0), `bearing` (0) and `pitch` (0);
/// `min_zoom` .. `max_zoom` and `min_pitch` .. `max_pitch` bound it. Without `interactive` the
/// mouse and keyboard leave it alone; `attribution` shows the sources' attributions (default true).
pub fn Map::new(
  container : String,
  style~ : Style,
  center? : LngLat,
  zoom? : Double,
  bearing? : Double,
  pitch? : Double,
  min_zoom? : Double,
  max_zoom? : Double,
  min_pitch? : Double,
  max_pitch? : Double,
  interactive? : Bool,
  attribution? : Bool,
) -> Map {
  let o = camera_json(center, zoom, bearing, pitch)
  o["container"] = Json::string(container)
  put_number(o, "minZoom", min_zoom)
  put_number(o, "maxZoom", max_zoom)
  put_number(o, "minPitch", min_pitch)
  put_number(o, "maxPitch", max_pitch)
  put_bool(o, "interactive", interactive)
  put_bool(o, "attributionControl", attribution)
  let options = json_to_js(Json::object(o))
  create_map(js_with(options, "style", style.to_js()))
}

///|
extern "js" fn js_with(o : JsValue, key : String, value : JsValue) -> JsValue =
  #|(o, k, v) => ({ ...o, [k]: v })

///|
fn Map::call(self : Map, name : String, args : FixedArray[JsValue]) -> JsValue {
  js_call(self.js(), name, args)
}

///|
/// The point at the center of the map.
pub fn Map::center(self : Map) -> LngLat {
  let c = self.call("getCenter", [])
  { lng: js_as_number(js_get(c, "lng")), lat: js_as_number(js_get(c, "lat")), }
}

///|
pub fn Map::zoom(self : Map) -> Double {
  js_as_number(self.call("getZoom", []))
}

///|
/// Degrees clockwise from north the map is turned by.
pub fn Map::bearing(self : Map) -> Double {
  js_as_number(self.call("getBearing", []))
}

///|
/// Degrees the map is tilted by, 0 looking straight down.
pub fn Map::pitch(self : Map) -> Double {
  js_as_number(self.call("getPitch", []))
}

///|
/// Moves the camera at once to what is given.
pub fn Map::jump_to(
  self : Map,
  center? : LngLat,
  zoom? : Double,
  bearing? : Double,
  pitch? : Double,
) -> Unit {
  let o = camera_json(center, zoom, bearing, pitch)
  self.call("jumpTo", [json_to_js(Json::object(o))]) |> ignore
}

///|
/// Moves the camera to what is given over `duration` milliseconds (MapLibre's `easeTo`, default 500).
pub fn Map::ease_to(
  self : Map,
  center? : LngLat,
  zoom? : Double,
  bearing? : Double,
  pitch? : Double,
  duration? : Double,
) -> Unit {
  let o = camera_json(center, zoom, bearing, pitch)
  put_number(o, "duration", duration)
  self.call("easeTo", [json_to_js(Json::object(o))]) |> ignore
}

///|
/// Flies the camera to what is given, zooming out and back in (MapLibre's `flyTo`): `speed`
/// (screenfuls a second, 1.2), `curve` (1.42), or a fixed `duration` in milliseconds.
pub fn Map::fly_to(
  self : Map,
  center? : LngLat,
  zoom? : Double,
  bearing? : Double,
  pitch? : Double,
  duration? : Double,
  speed? : Double,
  curve? : Double,
) -> Unit {
  let o = camera_json(center, zoom, bearing, pitch)
  put_number(o, "duration", duration)
  put_number(o, "speed", speed)
  put_number(o, "curve", curve)
  self.call("flyTo", [json_to_js(Json::object(o))]) |> ignore
}

///|
/// Moves the camera to show `bounds` with `padding` pixels around them, zooming in no further than
/// `max_zoom`; at once when `duration` is 0.
pub fn Map::fit_bounds(
  self : Map,
  bounds : Bounds,
  padding? : Double,
  max_zoom? : Double,
  duration? : Double,
) -> Unit {
  let o : @builtin.Map[String, Json] = @builtin.Map([])
  put_number(o, "padding", padding)
  put_number(o, "maxZoom", max_zoom)
  put_number(o, "duration", duration)
  let box : Json = [bounds.west, bounds.south, bounds.east, bounds.north]
  self.call("fitBounds", [json_to_js(box), json_to_js(Json::object(o))])
  |> ignore
}

///|
/// The screen point of `p`.
pub fn Map::project(self : Map, p : LngLat) -> Point {
  let r = self.call("project", [json_to_js(lnglat_json(p))])
  { x: js_as_number(js_get(r, "x")), y: js_as_number(js_get(r, "y")), }
}

///|
/// The place under screen point `p`.
pub fn Map::unproject(self : Map, p : Point) -> LngLat {
  let r = self.call("unproject", [json_to_js([p.x, p.y])])
  { lng: js_as_number(js_get(r, "lng")), lat: js_as_number(js_get(r, "lat")), }
}

///|
/// Draws `style` from now on; sources and layers that stay alike keep their tiles.
pub fn Map::set_style(self : Map, style : Style) -> Unit {
  self.call("setStyle", [style.to_js()]) |> ignore
}

///|
/// A copy of the style drawn, or None before it has loaded.
pub fn Map::style(self : Map) -> Json? {
  let s = self.call("getStyle", [])
  if js_is_nullish(s) {
    None
  } else {
    Some(s.to_json())
  }
}

///|
/// Adds source `id` (MapLibre's source specification as JSON).
pub fn Map::add_source(self : Map, id : String, source : Json) -> Unit {
  self.call("addSource", [js_string(id), json_to_js(source)]) |> ignore
}

///|
pub fn Map::remove_source(self : Map, id : String) -> Unit {
  self.call("removeSource", [js_string(id)]) |> ignore
}

///|
/// Replaces the data of GeoJSON source `id`.
pub fn Map::set_data(self : Map, id : String, data : Json) -> Unit {
  let source = self.call("getSource", [js_string(id)])
  if !js_is_nullish(source) {
    js_call(source, "setData", [json_to_js(data)]) |> ignore
  }
}

///|
/// Adds `layer` (MapLibre's layer specification as JSON) below layer `before`, or on top.
pub fn Map::add_layer(self : Map, layer : Json, before? : String) -> Unit {
  let at = match before {
    Some(b) => js_string(b)
    None => js_undefined()
  }
  self.call("addLayer", [json_to_js(layer), at]) |> ignore
}

///|
pub fn Map::remove_layer(self : Map, id : String) -> Unit {
  self.call("removeLayer", [js_string(id)]) |> ignore
}

///|
/// Moves layer `id` below layer `before`, or on top.
pub fn Map::move_layer(self : Map, id : String, before? : String) -> Unit {
  let at = match before {
    Some(b) => js_string(b)
    None => js_undefined()
  }
  self.call("moveLayer", [js_string(id), at]) |> ignore
}

///|
/// The layer ids, bottom first.
pub fn Map::layer_ids(self : Map) -> Array[String] {
  js_items(self.call("getLayersOrder", [])).iter().map(js_as_string).collect()
}

///|
/// Sets paint property `name` of layer `id`; None goes back to its default.
pub fn Map::set_paint(
  self : Map,
  id : String,
  name : String,
  value : Json?,
) -> Unit {
  let v = value.map(json_to_js).unwrap_or(js_null())
  self.call("setPaintProperty", [js_string(id), js_string(name), v]) |> ignore
}

///|
/// Sets layout property `name` of layer `id`; None goes back to its default.
pub fn Map::set_layout(
  self : Map,
  id : String,
  name : String,
  value : Json?,
) -> Unit {
  let v = value.map(json_to_js).unwrap_or(js_null())
  self.call("setLayoutProperty", [js_string(id), js_string(name), v]) |> ignore
}

///|
/// Sets the filter of layer `id`; None removes it.
pub fn Map::set_filter(self : Map, id : String, filter : Json?) -> Unit {
  let v = filter.map(json_to_js).unwrap_or(js_null())
  self.call("setFilter", [js_string(id), v]) |> ignore
}

///|
/// Merges `state` into the feature's state, which paint reading `["feature-state", key]` draws
/// with; `source_layer` names a vector source's layer.
pub fn Map::set_feature_state(
  self : Map,
  source : String,
  id : Json,
  state : Json,
  source_layer? : String,
) -> Unit {
  let target : @builtin.Map[String, Json] = {
    "source": Json::string(source),
    "id": id,
  }
  if source_layer is Some(l) {
    target["sourceLayer"] = Json::string(l)
  }
  self.call("setFeatureState", [
    json_to_js(Json::object(target)),
    json_to_js(state),
  ])
  |> ignore
}

///|
/// Removes the map from the page and frees what it holds.
pub fn Map::remove(self : Map) -> Unit {
  self.call("remove", []) |> ignore
}
