///|
/// Why an edit of the style was refused: `Invalid` (an `Error` in JS) or `OutOfRange` (a `RangeError`).
pub(all) suberror StyleEditError {
  Invalid(String)
  OutOfRange(String)
}

///|
/// The message of `e`, as the facade throws it.
pub fn StyleEditError::message(self : StyleEditError) -> String {
  match self {
    Invalid(m) | OutOfRange(m) => m
  }
}

///|
/// The deepest expression nesting the engine takes (`@style.MAX_EXPR_DEPTH`).
let max_expr_depth : Int32 = 32

///|
/// Highest zoom a layer's range may take (the style spec's layer `maxzoom`).
pub const MAX_LAYER_ZOOM : Double = 24.0

///|
/// The style document that `addLayer`, `setPaintProperty` and the like edit: the style's JSON
/// (`spec`), and the data of each GeoJSON source given as a JS object, kept apart as the value it
/// was copied into (`data`; its key in `spec` holds null), so a source whose data did not change
/// keeps it and its tiles. `revisions` numbers each source's version: `sourcedata` fires for those
/// whose number changed. Edits return a new document and leave this one as it was.
pub struct StyleDoc {
  priv spec : Map[String, Json]
  priv data : DataTable
  priv revisions : Map[String, Json]
}

///|
let revision_counter : Ref[Int32] = Ref(0)

///|
fn next_revision() -> Json {
  revision_counter.val += 1
  Json::number(revision_counter.val.to_double())
}

///|
fn copy_map(m : Map[String, Json]) -> Map[String, Json] {
  let out = Map([], capacity=m.length())
  for k, v in m {
    out[k] = v
  }
  out
}

///|
fn object_of(j : Json?) -> Map[String, Json] {
  match j {
    Some(Object(o)) => o
    _ => Map([])
  }
}

///|
fn string_of(j : Json?) -> String? {
  match j {
    Some(String(s)) => Some(s)
    _ => None
  }
}

///|
fn StyleDoc::sources(self : StyleDoc) -> Map[String, Json] {
  object_of(self.spec.get("sources"))
}

///|
fn StyleDoc::layers(self : StyleDoc) -> Array[Json] {
  match self.spec.get("layers") {
    Some(Array(a)) => a
    _ => []
  }
}

///|
fn layer_id(l : Json) -> String? {
  match l {
    Object(o) => string_of(o.get("id"))
    _ => None
  }
}

///|
fn StyleDoc::rebuild(
  self : StyleDoc,
  spec : Map[String, Json],
  data~ : DataTable = self.data,
  revisions~ : Map[String, Json] = self.revisions,
) -> StyleDoc {
  { spec, data, revisions, }
}

///|
fn StyleDoc::with_layers(self : StyleDoc, layers : Array[Json]) -> StyleDoc {
  let spec = copy_map(self.spec)
  spec["layers"] = Json::array(layers)
  self.rebuild(spec)
}

///|
/// A document of `spec`, each source with a new revision; the GeoJSON data stays in the JSON.
pub fn StyleDoc::from_json(spec : Json) -> StyleDoc raise StyleEditError {
  guard spec is Object(o) else {
    raise Invalid("moon-map: the style must be an object")
  }
  let revisions = Map([])
  for id, _ in object_of(o.get("sources")) {
    revisions[id] = next_revision()
  }
  { spec: o, data: DataTable::new(), revisions, }
}

///|
/// A document of the page's style object (copied, as `JSON.parse(JSON.stringify(style))`), its
/// GeoJSON sources' data objects kept apart as JS values.
pub fn StyleDoc::from_js(style : JsValue) -> StyleDoc raise StyleEditError {
  guard style.to_json() is Some(json) else {
    raise Invalid("moon-map: the style must be an object")
  }
  let doc = StyleDoc::from_json(json)
  let sources = style.get("sources")
  let data = DataTable::new()
  let spec_sources = copy_map(doc.sources())
  for id, s in doc.sources() {
    guard s is Object(src) && src.get("type") == Some(Json::string("geojson")) else {
      continue
    }
    let given = sources.get(id).get("data")
    if given.is_object() {
      data.set(id, given.copy())
      let kept = copy_map(src)
      kept["data"] = Json::null()
      spec_sources[id] = Json::object(kept)
    }
  }
  let spec = copy_map(doc.spec)
  if spec.contains("sources") {
    spec["sources"] = Json::object(spec_sources)
  }
  doc.rebuild(spec, data~)
}

///|
/// This document with the GeoJSON data of `previous` wherever the two are written alike, so the
/// sources they share keep their tiles (the data is compared by identity after this).
pub fn StyleDoc::keep_data(self : StyleDoc, previous : StyleDoc?) -> StyleDoc {
  guard previous is Some(prev) else { return self }
  let mut data = self.data
  for id in self.data.ids() {
    let d = self.data.get(id)
    let old = prev.data.get(id)
    if !old.same(d) && !old.is_nullish() && old.json_text() == d.json_text() {
      data = data.put(id, old)
    }
  }
  self.rebuild(self.spec, data~)
}

///|
/// The source's data: the JS value kept, else what the JSON holds (a URL, or inline GeoJSON).
fn StyleDoc::data_of(self : StyleDoc, id : String) -> JsValue? {
  if self.data.has(id) {
    return Some(self.data.get(id))
  }
  match self.sources().get(id) {
    Some(Object(s)) => s.get("data").map(json_to_js)
    _ => None
  }
}

///|
/// The style as a JS object (a copy), GeoJSON data included; custom layers' placeholders only with
/// `custom` (MapLibre's `getStyle` leaves them out: their code is no JSON).
pub fn StyleDoc::to_js(self : StyleDoc, custom~ : Bool = false) -> JsValue {
  let spec = copy_map(self.spec)
  if !custom {
    spec["layers"] = Json::array(
      self
      .layers()
      .filter(l => {
        !(l is Object(o) && o.get("type") == Some(Json::string("custom")))
      }),
    )
  }
  let out = json_to_js(Json::object(spec))
  let ids = self.data.ids()
  if ids.is_empty() {
    return out
  }
  let mut sources = out.get("sources")
  for id in ids {
    sources = sources.with_key(
      id,
      sources.get(id).with_key("data", self.data.get(id).copy()),
    )
  }
  out.with_key("sources", sources)
}

///|
/// Layer `id` as the style gives it.
pub fn StyleDoc::layer(self : StyleDoc, id : String) -> Json? {
  for l in self.layers() {
    if layer_id(l) == Some(id) {
      return Some(l)
    }
  }
  None
}

///|
/// The layer ids, bottom first.
pub fn StyleDoc::layer_ids(self : StyleDoc) -> Array[String] {
  self.layers().filter_map(layer_id)
}

///|
fn StyleDoc::index_of(
  self : StyleDoc,
  id : String,
) -> Int32 raise StyleEditError {
  for i, l in self.layers() {
    if layer_id(l) == Some(id) {
      return i
    }
  }
  raise Invalid("moon-map: the style has no layer \"\{id}\"")
}

///|
/// Whether the style has source `id`.
pub fn StyleDoc::has_source(self : StyleDoc, id : String) -> Bool {
  self.sources().contains(id)
}

///|
/// Source `id` as the style gives it (a GeoJSON source's data object kept apart reads null here).
pub fn StyleDoc::source(self : StyleDoc, id : String) -> Json? {
  self.sources().get(id)
}

///|
/// The data of GeoJSON source `id` as the page gave it (a copy), or undefined.
pub fn StyleDoc::source_data(self : StyleDoc, id : String) -> JsValue? {
  self.data_of(id).map(d => d.copy())
}

///|
/// Adds `layer` before the layer `before` names, or on top.
pub fn StyleDoc::add_layer(
  self : StyleDoc,
  layer : Json,
  before? : String,
) -> StyleDoc raise StyleEditError {
  guard layer is Object(l) &&
    l.get("id") is Some(String(id)) &&
    l.get("type") is Some(String(kind)) else {
    raise Invalid("moon-map: a layer needs an id and a type")
  }
  if self.layer(id) is Some(_) {
    raise Invalid("moon-map: the style already has a layer \"\{id}\"")
  }
  if kind != "background" && kind != "custom" {
    let source = string_of(l.get("source"))
    guard source is Some(s) && self.has_source(s) else {
      let named = match l.get("source") {
        Some(String(s)) => s
        _ => "undefined"
      }
      raise Invalid(
        "moon-map: layer \"\{id}\": the style has no source \"\{named}\"",
      )
    }
  }
  let layers = self.layers().copy()
  match before {
    Some(b) => layers.insert(self.index_of(b), layer)
    None => layers.push(layer)
  }
  self.with_layers(layers)
}

///|
pub fn StyleDoc::remove_layer(
  self : StyleDoc,
  id : String,
) -> StyleDoc raise StyleEditError {
  let i = self.index_of(id)
  let layers = self.layers().copy()
  layers.remove(i) |> ignore
  self.with_layers(layers)
}

///|
/// Moves layer `id` before the layer `before` names, or on top.
pub fn StyleDoc::move_layer(
  self : StyleDoc,
  id : String,
  before? : String,
) -> StyleDoc raise StyleEditError {
  let layer = self.layers()[self.index_of(id)]
  if before is Some(b) {
    self.index_of(b) |> ignore
  }
  let rest = self.layers().filter(l => layer_id(l) != Some(id))
  let at = match before {
    Some(b) =>
      match rest.search_by(l => layer_id(l) == Some(b)) {
        Some(i) => i
        None => rest.length()
      }
    None => rest.length()
  }
  rest.insert(at, layer)
  self.with_layers(rest)
}

///|
fn StyleDoc::with_layer(
  self : StyleDoc,
  id : String,
  f : (Map[String, Json]) -> Unit,
) -> StyleDoc raise StyleEditError {
  let i = self.index_of(id)
  let layers = self.layers().copy()
  let l = copy_map(object_of(Some(layers[i])))
  f(l)
  layers[i] = Json::object(l)
  self.with_layers(layers)
}

///|
/// Sets property `name` of layer `id`'s `group` ("paint" or "layout"); None goes back to its
/// default. The other properties keep their order (layers are compared as written).
fn StyleDoc::set_property(
  self : StyleDoc,
  id : String,
  group : String,
  name : String,
  value : Json?,
) -> StyleDoc raise StyleEditError {
  self.with_layer(id, l => {
    let props = Map([])
    let mut placed = false
    for k, v in object_of(l.get(group)) {
      if k == name {
        placed = true
        if value is Some(x) {
          props[k] = x
        }
      } else {
        props[k] = v
      }
    }
    if !placed && value is Some(x) {
      props[name] = x
    }
    l[group] = Json::object(props)
  })
}

///|
/// Sets paint property `name` of layer `id`; None (null) goes back to its default.
pub fn StyleDoc::set_paint(
  self : StyleDoc,
  id : String,
  name : String,
  value : Json?,
) -> StyleDoc raise StyleEditError {
  self.set_property(id, "paint", name, value)
}

///|
pub fn StyleDoc::set_layout(
  self : StyleDoc,
  id : String,
  name : String,
  value : Json?,
) -> StyleDoc raise StyleEditError {
  self.set_property(id, "layout", name, value)
}

///|
fn StyleDoc::property(
  self : StyleDoc,
  id : String,
  group : String,
  name : String,
) -> Json? {
  match self.layer(id) {
    Some(Object(l)) => object_of(l.get(group)).get(name)
    _ => None
  }
}

///|
pub fn StyleDoc::paint(self : StyleDoc, id : String, name : String) -> Json? {
  self.property(id, "paint", name)
}

///|
pub fn StyleDoc::layout(self : StyleDoc, id : String, name : String) -> Json? {
  self.property(id, "layout", name)
}

///|
/// Sets the filter of layer `id`; None removes it.
pub fn StyleDoc::set_filter(
  self : StyleDoc,
  id : String,
  filter : Json?,
) -> StyleDoc raise StyleEditError {
  self.with_layer(id, l => {
    match filter {
      Some(f) => l["filter"] = f
      None => l.remove("filter")
    }
  })
}

///|
pub fn StyleDoc::filter(self : StyleDoc, id : String) -> Json? {
  match self.layer(id) {
    Some(Object(l)) => l.get("filter")
    _ => None
  }
}

///|
/// Shows layer `id` only from zoom `minzoom` up to `maxzoom`.
pub fn StyleDoc::set_zoom_range(
  self : StyleDoc,
  id : String,
  minzoom : Double,
  maxzoom : Double,
) -> StyleDoc raise StyleEditError {
  if !(minzoom >= 0.0 && maxzoom <= MAX_LAYER_ZOOM && minzoom <= maxzoom) {
    raise OutOfRange(
      "moon-map: a layer's zoom range must lie in 0-24, min not above max",
    )
  }
  self.with_layer(id, l => {
    l["minzoom"] = Json::number(minzoom)
    l["maxzoom"] = Json::number(maxzoom)
  })
}

///|
fn StyleDoc::with_source(
  self : StyleDoc,
  id : String,
  source : Json,
  data : JsValue?,
) -> StyleDoc {
  let sources = copy_map(self.sources())
  sources[id] = source
  let spec = copy_map(self.spec)
  spec["sources"] = Json::object(sources)
  let table = match data {
    Some(d) => self.data.put(id, d)
    None => self.data.drop(id)
  }
  let revisions = copy_map(self.revisions)
  revisions[id] = next_revision()
  self.rebuild(spec, data=table, revisions~)
}

///|
/// `source` split into its JSON and, for a GeoJSON source given an object, that object (copied).
fn split_source(
  id : String,
  source : JsValue,
) -> (Json, JsValue?) raise StyleEditError {
  guard source.to_json() is Some(Object(s)) &&
    s.get("type") is Some(String(kind)) else {
    raise Invalid("moon-map: source \"\{id}\" needs a type")
  }
  let data = source.get("data")
  if kind == "geojson" && data.is_object() {
    let kept = copy_map(s)
    kept["data"] = Json::null()
    (Json::object(kept), Some(data.copy()))
  } else {
    (Json::object(s), None)
  }
}

///|
/// Adds source `id` given by the page (copied; a GeoJSON source's data object kept apart).
pub fn StyleDoc::add_source(
  self : StyleDoc,
  id : String,
  source : JsValue,
) -> StyleDoc raise StyleEditError {
  if self.has_source(id) {
    raise Invalid("moon-map: the style already has a source \"\{id}\"")
  }
  let (json, data) = split_source(id, source)
  self.with_source(id, json, data)
}

///|
/// Adds source `id` written in MoonBit (a GeoJSON source's data inline).
pub fn StyleDoc::add_source_json(
  self : StyleDoc,
  id : String,
  source : Json,
) -> StyleDoc raise StyleEditError {
  if self.has_source(id) {
    raise Invalid("moon-map: the style already has a source \"\{id}\"")
  }
  guard source is Object(s) && s.get("type") is Some(String(_)) else {
    raise Invalid("moon-map: source \"\{id}\" needs a type")
  }
  self.with_source(id, source, None)
}

///|
/// Removes source `id`; refused while a layer or the terrain uses it, as MapLibre refuses.
pub fn StyleDoc::remove_source(
  self : StyleDoc,
  id : String,
) -> StyleDoc raise StyleEditError {
  if !self.has_source(id) {
    raise Invalid("moon-map: the style has no source \"\{id}\"")
  }
  for l in self.layers() {
    if l is Object(o) && string_of(o.get("source")) == Some(id) {
      let user = layer_id(l).unwrap_or("")
      raise Invalid("moon-map: source \"\{id}\" is used by layer \"\{user}\"")
    }
  }
  if string_of(object_of(self.spec.get("terrain")).get("source")) == Some(id) {
    raise Invalid("moon-map: source \"\{id}\" is used by the terrain")
  }
  let sources = copy_map(self.sources())
  sources.remove(id)
  let spec = copy_map(self.spec)
  spec["sources"] = Json::object(sources)
  self.rebuild(spec, data=self.data.drop(id))
}

///|
fn StyleDoc::geojson_source(
  self : StyleDoc,
  id : String,
) -> Map[String, Json] raise StyleEditError {
  match self.source(id) {
    Some(Object(s)) if s.get("type") == Some(Json::string("geojson")) => s
    _ => raise Invalid("moon-map: source \"\{id}\" is not a GeoJSON source")
  }
}

///|
/// Replaces the data of GeoJSON source `id` with what the page gives (an object or a URL).
pub fn StyleDoc::set_source_data(
  self : StyleDoc,
  id : String,
  data : JsValue,
) -> StyleDoc raise StyleEditError {
  let s = copy_map(self.geojson_source(id))
  if data.is_object() {
    s["data"] = Json::null()
    self.with_source(id, Json::object(s), Some(data.copy()))
  } else {
    s["data"] = data.to_json().unwrap_or(Json::null())
    self.with_source(id, Json::object(s), None)
  }
}

///|
/// Replaces the data of GeoJSON source `id` with GeoJSON written in MoonBit.
pub fn StyleDoc::set_source_data_json(
  self : StyleDoc,
  id : String,
  data : Json,
) -> StyleDoc raise StyleEditError {
  let s = copy_map(self.geojson_source(id))
  s["data"] = data
  self.with_source(id, Json::object(s), None)
}

///|
/// Sets key `key` of source `id` in place, as MapLibre's `serialize` keeps what a source was told
/// (an image's coordinates): no new revision, nothing drawn again.
pub fn StyleDoc::keep_source_key(
  self : StyleDoc,
  id : String,
  key : String,
  value : Json,
) -> Unit {
  if self.sources().get(id) is Some(Object(s)) {
    s[key] = value
  }
}

///|
/// Keeps `data` as GeoJSON source `id`'s data in place (a URL source's data the worker read).
pub fn StyleDoc::keep_source_data(
  self : StyleDoc,
  id : String,
  data : JsValue,
) -> Unit {
  if self.has_source(id) {
    self.data.set(id, data)
  }
}

///|
/// Sets a top-level property such as `terrain`, `sky`, `light`, `lights` or `projection`; None removes it.
pub fn StyleDoc::set_root(
  self : StyleDoc,
  key : String,
  value : Json?,
) -> StyleDoc {
  let spec = copy_map(self.spec)
  match value {
    Some(v) => spec[key] = v
    None => spec.remove(key)
  }
  self.rebuild(spec)
}

///|
pub fn StyleDoc::root(self : StyleDoc, key : String) -> Json? {
  self.spec.get(key)
}

///|
/// The ids of the sources this document lacks in `previous` or has in another revision.
pub fn StyleDoc::changed_sources(
  self : StyleDoc,
  previous : StyleDoc?,
) -> Array[String] {
  let out = []
  for id, _ in self.sources() {
    let before = previous.bind(p => p.revisions.get(id))
    if before is None || before != self.revisions.get(id) {
      out.push(id)
    }
  }
  out
}

///|
/// What `filter_kind` tells apart: undefined, a boolean, an array, a string, anything else.
extern "js" fn filter_kind(v : JsValue) -> Int32 =
  #|(v) => v === undefined ? 0 : typeof v === "boolean" ? 1 : Array.isArray(v) ? 2 : typeof v === "string" ? 3 : 4

///|
extern "js" fn js_length(v : JsValue) -> Int32 =
  #|(v) => v.length

///|
extern "js" fn js_at(v : JsValue, i : Int32) -> JsValue =
  #|(v, i) => v[i]

///|
extern "js" fn js_text(v : JsValue) -> String =
  #|(v) => v

///|
/// Whether `f` (as the page gave it) may be a legacy filter, which the facade's converter takes:
/// MapLibre's `classifyFilter`, except that `all` and `any` mixing legacy filters with expressions
/// count. Deeper than the engine takes (`max_expr_depth`), it is left to the engine, which rejects it.
pub fn is_legacy_filter_value(f : JsValue, depth~ : Int32 = 0) -> Bool {
  let kind = filter_kind(f)
  if kind == 0 || kind == 1 || depth > max_expr_depth {
    return false
  }
  if kind != 2 || js_length(f) == 0 {
    return true
  }
  let n = js_length(f)
  let head = js_at(f, 0)
  let op = if filter_kind(head) == 3 { js_text(head) } else { "" }
  let is_string = (i : Int32) => filter_kind(js_at(f, i)) == 3
  let is_array = (i : Int32) => filter_kind(js_at(f, i)) == 2
  match op {
    "has" =>
      n < 2 ||
      (
        is_string(1) &&
        (js_text(js_at(f, 1)) == "$id" || js_text(js_at(f, 1)) == "$type")
      )
    "in" => !(n >= 3 && (!is_string(1) || is_array(2)))
    "!in" | "!has" | "none" => true
    "==" | "!=" | ">" | ">=" | "<" | "<=" =>
      n == 3 && !is_array(1) && !is_array(2)
    "any" | "all" => {
      for i in 1..<n {
        if is_legacy_filter_value(js_at(f, i), depth=depth + 1) {
          return true
        }
      }
      false
    }
    _ => false
  }
}

///|
/// `is_legacy_filter_value` of a filter written as JSON (None: no filter).
pub fn is_legacy_filter(f : Json?) -> Bool {
  match f {
    Some(f) => is_legacy_filter_value(json_to_js(f))
    None => false
  }
}

///|
/// Whether a layer may have a legacy filter or a property function (a plain object as a paint or
/// layout value), which the facade converts before the engine reads the style.
pub fn StyleDoc::has_legacy(self : StyleDoc) -> Bool {
  let function_in = (o : Json?) => {
    object_of(o).values().any(v => v is Object(_))
  }
  self
  .layers()
  .iter()
  .any(l => {
    let o = object_of(Some(l))
    is_legacy_filter(o.get("filter")) ||
    function_in(o.get("paint")) ||
    function_in(o.get("layout"))
  })
}

///|
/// The source ids, in the style's order.
pub fn StyleDoc::source_ids(self : StyleDoc) -> Array[String] {
  self.sources().keys().collect()
}

///|
/// The GeoJSON data kept apart, by source id: a JS object without a prototype (a MoonBit map of JS
/// values would add a copy of the map's code to the bundle).
#external
priv type DataTable

///|
extern "js" fn DataTable::new() -> DataTable =
  #|() => Object.create(null)

///|
extern "js" fn DataTable::has(self : DataTable, id : String) -> Bool =
  #|(t, id) => Object.hasOwn(t, id)

///|
/// The data of `id`, or undefined.
extern "js" fn DataTable::get(self : DataTable, id : String) -> JsValue =
  #|(t, id) => (Object.hasOwn(t, id) ? t[id] : undefined)

///|
extern "js" fn DataTable::ids(self : DataTable) -> FixedArray[String] =
  #|(t) => Object.keys(t)

///|
/// A copy of the table with `id` set to `data`.
extern "js" fn DataTable::put(self : DataTable, id : String, data : JsValue) -> DataTable =
  #|(t, id, d) => {
  #|  const out = Object.assign(Object.create(null), t);
  #|  out[id] = d;
  #|  return out;
  #|}

///|
/// A copy of the table without `id`.
extern "js" fn DataTable::drop(self : DataTable, id : String) -> DataTable =
  #|(t, id) => {
  #|  const out = Object.assign(Object.create(null), t);
  #|  delete out[id];
  #|  return out;
  #|}

///|
extern "js" fn DataTable::set(self : DataTable, id : String, data : JsValue) -> Unit =
  #|(t, id, d) => { t[id] = d; }
