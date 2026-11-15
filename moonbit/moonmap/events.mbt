///|
/// MapLibre's events: mouse events (on a layer's features with `Map::on_layer`, where alone `MouseEnter`
/// and `MouseLeave` come), `Load` (first view drawn), `Render` (each frame), `Idle` (settled, also right
/// after `Load`), `Error`, `StyleData`, `SourceData`, and the camera's moving, zooming, rotating, pitching.
pub(all) enum EventType {
  MouseDown
  MouseUp
  MouseOver
  MouseOut
  MouseMove
  Click
  DblClick
  ContextMenu
  MouseEnter
  MouseLeave
  Load
  StyleData
  SourceData
  Render
  Idle
  Error
  MoveStart
  Move
  MoveEnd
  ZoomStart
  Zoom
  ZoomEnd
  RotateStart
  Rotate
  RotateEnd
  PitchStart
  Pitch
  PitchEnd
}

///|
/// The name the npm package uses for `self`.
pub fn EventType::name(self : EventType) -> String {
  match self {
    MouseDown => "mousedown"
    MouseUp => "mouseup"
    MouseOver => "mouseover"
    MouseOut => "mouseout"
    MouseMove => "mousemove"
    Click => "click"
    DblClick => "dblclick"
    ContextMenu => "contextmenu"
    MouseEnter => "mouseenter"
    MouseLeave => "mouseleave"
    Load => "load"
    StyleData => "styledata"
    SourceData => "sourcedata"
    Render => "render"
    Idle => "idle"
    Error => "error"
    MoveStart => "movestart"
    Move => "move"
    MoveEnd => "moveend"
    ZoomStart => "zoomstart"
    Zoom => "zoom"
    ZoomEnd => "zoomend"
    RotateStart => "rotatestart"
    Rotate => "rotate"
    RotateEnd => "rotateend"
    PitchStart => "pitchstart"
    Pitch => "pitch"
    PitchEnd => "pitchend"
  }
}

///|
/// A feature under the pointer or found by a query, as GeoJSON with where it was drawn: `layer`
/// and `source` (and `source_layer` of a vector source), its `id` if it has one.
pub(all) struct Feature {
  id : Json?
  layer : String
  source : String
  source_layer : String?
  properties : Json
  geometry : Json
}

///|
/// What an event carries: mouse events their `point` (CSS pixels), its `lnglat` and the `features`
/// of the layers listened to; `Error` its `error` message; `SourceData` the `source` id.
pub(all) struct Event {
  kind : EventType
  point : Point?
  lnglat : LngLat?
  features : Array[Feature]
  error : String?
  source : String?
}

///|
fn optional_string(v : JsValue) -> String? {
  if js_is_nullish(v) {
    None
  } else {
    Some(js_as_string(v))
  }
}

///|
fn feature_of(f : JsValue) -> Feature {
  let layer = js_get(f, "layer")
  let id = js_get(f, "id")
  {
    id: if js_is_nullish(id) {
      None
    } else {
      Some(id.to_json())
    },
    layer: js_as_string(js_get(layer, "id")),
    source: js_as_string(js_get(f, "source")),
    source_layer: optional_string(js_get(f, "sourceLayer")),
    properties: js_get(f, "properties").to_json(),
    geometry: js_get(f, "geometry").to_json(),
  }
}

///|
fn event_of(kind : EventType, e : JsValue) -> Event {
  let p = js_get(e, "point")
  let ll = js_get(e, "lngLat")
  let error = js_get(e, "error")
  {
    kind,
    point: if js_is_nullish(p) {
      None
    } else {
      Some({ x: js_as_number(js_get(p, "x")), y: js_as_number(js_get(p, "y")), })
    },
    lnglat: if js_is_nullish(ll) {
      None
    } else {
      Some({
        lng: js_as_number(js_get(ll, "lng")),
        lat: js_as_number(js_get(ll, "lat")),
      })
    },
    features: js_items(js_get(e, "features")).iter().map(feature_of).collect(),
    error: if js_is_nullish(error) {
      None
    } else {
      Some(js_as_string(js_get(error, "message")))
    },
    source: optional_string(js_get(e, "sourceId")),
  }
}

///|
/// A listener `Map::on` added; `off` removes it.
pub struct Listener {
  priv map : Map
  priv args : FixedArray[JsValue]
}

///|
extern "js" fn js_listener(f : (JsValue) -> Unit) -> JsValue =
  #|(f) => (e) => f(e)

///|
/// Calls `f` with each `kind` event from now on.
pub fn Map::on(self : Map, kind : EventType, f : (Event) -> Unit) -> Listener {
  let args : FixedArray[JsValue] = [
    js_string(kind.name()),
    js_listener(e => f(event_of(kind, e))),
  ]
  self.call("on", args) |> ignore
  { map: self, args, }
}

///|
/// Calls `f` with each `kind` mouse event on the features of `layers` (with those features).
pub fn Map::on_layer(
  self : Map,
  kind : EventType,
  layers : Array[String],
  f : (Event) -> Unit,
) -> Listener {
  let ids = json_to_js(Json::array(layers.map(Json::string)))
  let args : FixedArray[JsValue] = [
    js_string(kind.name()),
    ids,
    js_listener(e => f(event_of(kind, e))),
  ]
  self.call("on", args) |> ignore
  { map: self, args, }
}

///|
/// Stops the listener.
pub fn Listener::off(self : Listener) -> Unit {
  self.map.call("off", self.args) |> ignore
}

///|
extern "js" fn js_then(p : JsValue, f : (JsValue) -> Unit) -> Unit =
  #|(p, f) => { p.then(f); }

///|
/// The features drawn at `point` (or in the whole view without it), topmost first, of `layers` if
/// given, handed to `done` once the workers answered (MapLibre's `queryRenderedFeatures`).
pub fn Map::query_rendered_features(
  self : Map,
  point? : Point,
  layers? : Array[String],
  done : (Array[Feature]) -> Unit,
) -> Unit {
  let options : @builtin.Map[String, Json] = @builtin.Map([])
  if layers is Some(ids) {
    options["layers"] = Json::array(ids.map(Json::string))
  }
  let args : FixedArray[JsValue] = match point {
    Some(p) => [json_to_js([p.x, p.y]), json_to_js(Json::object(options))]
    None => [json_to_js(Json::object(options))]
  }
  js_then(self.call("queryRenderedFeatures", args), r => {
    done(js_items(r).iter().map(feature_of).collect())
  })
}
