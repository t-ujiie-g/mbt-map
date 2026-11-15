///|
using @cmd {type Cmd, type Emit}

///|
/// The `<mbt-map>` with `id` (null when there is none); importing it defines the element.
#module("mbt-map/element")
extern "js" fn find_element(id : String) -> @mbtmap.JsValue = "mbtMapElement"

///|
/// The map's camera as an event leaves it.
#derive(Eq, Debug)
pub(all) struct Camera {
  center : @mbtmap.LngLat
  zoom : Double
  bearing : Double
  pitch : Double
}

///|
/// A click on the map: the screen point, the place under it and the camera then.
#derive(Eq, Debug)
pub(all) struct Click {
  point : @mbtmap.Point
  lnglat : @mbtmap.LngLat
  camera : Camera
}

///|
/// A `<mbt-map>` element with `id`, which `setup`, `with_map` and `events` find the map by.
/// `css` is its inline style (give it a height); the map fills it.
pub fn view(id : String, css? : String, class? : String) -> @html.Html {
  let attrs = @html.Attrs::build().id(id)
  if css is Some(text) {
    attrs.style_attr(text) |> ignore
  }
  if class is Some(c) {
    attrs.class(c) |> ignore
  }
  let children : Array[@html.Html] = []
  @html.node("mbt-map", attrs, children)
}

///|
extern "js" fn configure(
  el : @mbtmap.JsValue,
  id : String,
  camera : @mbtmap.JsValue,
  url : String,
  style : @mbtmap.JsValue,
) -> Unit =
  #|(el, id, camera, url, style) => {
  #|  if (!el) { console.error(new Error(`mbt-map: no <mbt-map> with id ${JSON.stringify(id)}`)); return; }
  #|  for (const k of ["center", "zoom", "bearing", "pitch"]) if (k in camera) el[k] = camera[k];
  #|  if (url) { el.mapStyle = null; el.setAttribute("style-url", url); } else el.mapStyle = style;
  #|}

///|
/// Gives the map of `<mbt-map>` `id` its style and camera once the view is on the page; the map is
/// made then. Run it again to change the style (tiles of sources that stay alike are kept).
pub fn setup(
  id : String,
  style : @style.Style,
  center? : @mbtmap.LngLat,
  zoom? : Double,
  bearing? : Double,
  pitch? : Double,
) -> Cmd {
  let camera : Map[String, Json] = Map([])
  if center is Some(c) {
    camera["center"] = { "lng": c.lng, "lat": c.lat }
  }
  if zoom is Some(z) {
    camera["zoom"] = Json::number(z)
  }
  if bearing is Some(b) {
    camera["bearing"] = Json::number(b)
  }
  if pitch is Some(p) {
    camera["pitch"] = Json::number(p)
  }
  let (url, json) = match style.to_url() {
    Some(u) => (u, Json::null())
    None => ("", style.to_json())
  }
  @cmd.custom_cmd(
    _ => {
      configure(
        find_element(id),
        id,
        @mbtmap.json_to_js(Json::object(camera)),
        url,
        @mbtmap.json_to_js(json),
      )
    },
    kind=@cmd.after_render,
  )
}

///|
extern "js" fn when_map(
  el : @mbtmap.JsValue,
  f : (@mbtmap.Map) -> Unit,
) -> Unit =
  #|(el, f) => {
  #|  if (!el) return;
  #|  if (el.map) f(el.map);
  #|  else el.addEventListener("mbt-map-load", () => el.map && f(el.map), { once: true });
  #|}

///|
/// Runs `f` on the map of `<mbt-map>` `id` (once it has loaded, if it has not yet) and then the command
/// `f` returns: the typed API of `t-ujiie-g/mbtmap` from `update`.
pub fn with_map(id : String, f : (@mbtmap.Map) -> Cmd) -> Cmd {
  @cmd.custom_cmd(
    scheduler => when_map(find_element(id), map => scheduler.add(f(map))),
    kind=@cmd.after_render,
  )
}

///|
/// The features drawn at `point` of the map of `<mbt-map>` `id` (in `layers` only, if given), topmost
/// first, as a message.
pub fn query_features(
  id : String,
  point : @mbtmap.Point,
  layers? : Array[String],
  done : Emit[Array[@mbtmap.Feature]],
) -> Cmd {
  @cmd.custom_cmd(
    scheduler => {
      when_map(find_element(id), map => {
        map.query_rendered_features(point~, layers?, features => {
          scheduler.add((done.0)(features))
        })
      })
    },
    kind=@cmd.after_render,
  )
}

///|
priv struct Handlers {
  load : Cmd?
  idle : Cmd?
  move_ : Emit[Camera]?
  moveend : Emit[Camera]?
  click : Emit[Click]?
  error : Emit[String]?
}

///|
priv suberror Listen {
  Listen(String, Handlers)
}

///|
extern "js" fn listen(
  id : String,
  types : FixedArray[String],
  f : (String, @mbtmap.JsValue) -> Unit,
) -> () -> Unit =
  #|(id, types, f) => {
  #|  const h = (e) => { if (e.target instanceof Element && e.target.id === id) f(e.type, e.detail); };
  #|  for (const t of types) document.addEventListener(t, h);
  #|  return () => { for (const t of types) document.removeEventListener(t, h); };
  #|}

///|
extern "js" fn detail_number(detail : @mbtmap.JsValue, key : String) -> Double =
  #|(d, k) => (typeof d?.[k] === "number" ? d[k] : NaN)

///|
extern "js" fn detail_pair(
  detail : @mbtmap.JsValue,
  key : String,
  a : String,
  b : String,
) -> FixedArray[Double] =
  #|(d, k, a, b) => [Number(d?.[k]?.[a] ?? NaN), Number(d?.[k]?.[b] ?? NaN)]

///|
extern "js" fn detail_error(detail : @mbtmap.JsValue) -> String =
  #|(d) => String(d?.error?.message ?? d?.error ?? "")

///|
fn camera_of(detail : @mbtmap.JsValue) -> Camera {
  let c = detail_pair(detail, "center", "lng", "lat")
  {
    center: { lng: c[0], lat: c[1], },
    zoom: detail_number(detail, "zoom"),
    bearing: detail_number(detail, "bearing"),
    pitch: detail_number(detail, "pitch"),
  }
}

///|
fn click_of(detail : @mbtmap.JsValue) -> Click {
  let p = detail_pair(detail, "point", "x", "y")
  let l = detail_pair(detail, "lngLat", "lng", "lat")
  {
    point: { x: p[0], y: p[1], },
    lnglat: { lng: l[0], lat: l[1], },
    camera: camera_of(detail),
  }
}

///|
fn handle(h : Handlers, kind : String, detail : @mbtmap.JsValue) -> Cmd? {
  match kind {
    "mbt-map-load" => h.load
    "mbt-map-idle" => h.idle
    "mbt-map-move" => h.move_.map(e => (e.0)(camera_of(detail)))
    "mbt-map-moveend" => h.moveend.map(e => (e.0)(camera_of(detail)))
    "mbt-map-click" => h.click.map(e => (e.0)(click_of(detail)))
    "mbt-map-error" => h.error.map(e => (e.0)(detail_error(detail)))
    _ => None
  }
}

///|
fn sub_loader(payload : Error, scheduler : &@cmd.Scheduler) -> @sub.RunningSub? {
  guard payload is Listen(id, handlers) else { None }
  let current = Ref(handlers)
  let types = []
  if handlers.load is Some(_) {
    types.push("mbt-map-load")
  }
  if handlers.idle is Some(_) {
    types.push("mbt-map-idle")
  }
  if handlers.move_ is Some(_) {
    types.push("mbt-map-move")
  }
  if handlers.moveend is Some(_) {
    types.push("mbt-map-moveend")
  }
  if handlers.click is Some(_) {
    types.push("mbt-map-click")
  }
  if handlers.error is Some(_) {
    types.push("mbt-map-error")
  }
  let stop = listen(id, FixedArray::from_array(types), (kind, detail) => {
    if handle(current.val, kind, detail) is Some(cmd) {
      scheduler.add(cmd)
    }
  })
  Some({
    unload: _ => stop(),
    update_tagger: p => if p is Listen(_, h) { current.val = h },
  })
}

///|
/// The events of `<mbt-map>` `id` as messages: `on_load` (first view drawn), `on_idle` (settled, also
/// right after load), `on_move` (each frame the camera moves), `on_moveend`, `on_click` and `on_error`
/// (the error's message). Return it from `subscriptions`.
pub fn events(
  id : String,
  on_load? : Cmd,
  on_idle? : Cmd,
  on_move? : Emit[Camera],
  on_moveend? : Emit[Camera],
  on_click? : Emit[Click],
  on_error? : Emit[String],
) -> @sub.Sub {
  let handlers = {
    load: on_load,
    idle: on_idle,
    move_: on_move,
    moveend: on_moveend,
    click: on_click,
    error: on_error,
  }
  let flags = [
    on_load is Some(_),
    on_idle is Some(_),
    on_move is Some(_),
    on_moveend is Some(_),
    on_click is Some(_),
    on_error is Some(_),
  ]
  let key = "mbt-map.events(\{id},\{flags.map(f => if f { "1" } else { "0" }).join("")})"
  @sub.custom_sub(
    key,
    @sub.Scope::Local,
    Listen(id, handlers),
    @sub.SubLoader(sub_loader),
  )
}
