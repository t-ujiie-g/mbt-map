// The style document's exports: the facade holds a `@web.StyleDoc` and edits it through these.
// Edits give the new document, or an `Error` (`RangeError` for ranges) the facade throws.

///|
extern "js" fn as_js(doc : @web.StyleDoc) -> @web.JsValue =
  #|(d) => d

///|
extern "js" fn as_doc(v : @web.JsValue) -> @web.StyleDoc =
  #|(v) => v

///|
extern "js" fn as_engine_style(v : @web.JsValue) -> @web.EngineStyle =
  #|(v) => v

///|
extern "js" fn engine_style_js(e : @web.EngineStyle) -> @web.JsValue =
  #|(e) => e

///|
extern "js" fn js_undefined() -> @web.JsValue =
  #|() => undefined

///|
extern "js" fn js_range_error(message : String) -> @web.JsValue =
  #|(m) => new RangeError(m)

///|
extern "js" fn js_is_string(v : @web.JsValue) -> Bool =
  #|(v) => typeof v === "string"

///|
extern "js" fn js_as_string(v : @web.JsValue) -> String =
  #|(v) => v

///|
extern "js" fn js_pairs(pairs : FixedArray[FixedArray[String]]) -> @web.JsValue =
  #|(p) => p

///|
extern "js" fn js_entries(
  ids : FixedArray[String],
  values : FixedArray[@web.JsValue],
) -> @web.JsValue =
  #|(ids, values) => ids.map((id, i) => ({ id, spec: values[i] }))

///|
extern "js" fn call_documents(f : @web.JsValue, url : String) -> @web.JsValue =
  #|(f, url) => f(url)

///|
extern "js" fn call_convert(
  f : @web.JsValue,
  style : @web.JsValue,
) -> @web.JsValue =
  #|(f, s) => f(s)

///|
fn edited(f : () -> @web.StyleDoc raise @web.StyleEditError) -> @web.JsValue {
  as_js(f()) catch {
    OutOfRange(m) => js_range_error(m)
    Invalid(m) => @web.js_error(m)
  }
}

///|
fn optional_string(v : @web.JsValue) -> String? {
  if js_is_string(v) {
    Some(js_as_string(v))
  } else {
    None
  }
}

///|
/// JSON of `v`, None for null and undefined (what puts a property back to its default).
fn optional_json(v : @web.JsValue) -> Json? {
  if v.is_nullish() {
    None
  } else {
    v.to_json()
  }
}

///|
fn json_or_undefined(j : Json?) -> @web.JsValue {
  match j {
    Some(j) => @web.json_to_js(j)
    None => js_undefined()
  }
}

///|
#export_name("doc_from_js")
pub fn doc_from_js(style : @web.JsValue) -> @web.JsValue {
  edited(() => @web.StyleDoc::from_js(style))
}

///|
/// `doc` with the GeoJSON data of `previous` (a document, or null) where written alike.
#export_name("doc_keep_data")
pub fn doc_keep_data(
  doc : @web.StyleDoc,
  previous : @web.JsValue,
) -> @web.StyleDoc {
  doc.keep_data(
    if previous.is_nullish() {
      None
    } else {
      Some(as_doc(previous))
    },
  )
}

///|
#export_name("doc_to_js")
pub fn doc_to_js(doc : @web.StyleDoc, custom : Bool) -> @web.JsValue {
  doc.to_js(custom~)
}

///|
#export_name("doc_layer")
pub fn doc_layer(doc : @web.StyleDoc, id : String) -> @web.JsValue {
  json_or_undefined(doc.layer(id))
}

///|
/// The layers as `[{id, type}]`, bottom first (what the query ordering reads).
#export_name("doc_layer_kinds")
pub fn doc_layer_kinds(doc : @web.StyleDoc) -> @web.JsValue {
  let kinds = doc
    .layer_ids()
    .map(id => {
      let kind = match doc.layer(id) {
        Some(Object(l)) => l.get("type").unwrap_or(Json::null())
        _ => Json::null()
      }
      ({ "id": Json::string(id), "type": kind } : Json)
    })
  @web.json_to_js(Json::array(kinds))
}

///|
#export_name("doc_layer_ids")
pub fn doc_layer_ids(doc : @web.StyleDoc) -> FixedArray[String] {
  FixedArray::from_array(doc.layer_ids())
}

///|
#export_name("doc_add_layer")
pub fn doc_add_layer(
  doc : @web.StyleDoc,
  layer : @web.JsValue,
  before : @web.JsValue,
) -> @web.JsValue {
  edited(() => {
    doc.add_layer(
      layer.to_json().unwrap_or(Json::null()),
      before?=optional_string(before),
    )
  })
}

///|
#export_name("doc_remove_layer")
pub fn doc_remove_layer(doc : @web.StyleDoc, id : String) -> @web.JsValue {
  edited(() => doc.remove_layer(id))
}

///|
#export_name("doc_move_layer")
pub fn doc_move_layer(
  doc : @web.StyleDoc,
  id : String,
  before : @web.JsValue,
) -> @web.JsValue {
  edited(() => doc.move_layer(id, before?=optional_string(before)))
}

///|
#export_name("doc_set_property")
pub fn doc_set_property(
  doc : @web.StyleDoc,
  id : String,
  layout : Bool,
  name : String,
  value : @web.JsValue,
) -> @web.JsValue {
  let v = optional_json(value)
  edited(() => {
    if layout {
      doc.set_layout(id, name, v)
    } else {
      doc.set_paint(id, name, v)
    }
  })
}

///|
#export_name("doc_property")
pub fn doc_property(
  doc : @web.StyleDoc,
  id : String,
  layout : Bool,
  name : String,
) -> @web.JsValue {
  json_or_undefined(
    if layout {
      doc.layout(id, name)
    } else {
      doc.paint(id, name)
    },
  )
}

///|
#export_name("doc_set_filter")
pub fn doc_set_filter(
  doc : @web.StyleDoc,
  id : String,
  filter : @web.JsValue,
) -> @web.JsValue {
  let f = optional_json(filter)
  edited(() => doc.set_filter(id, f))
}

///|
#export_name("doc_filter")
pub fn doc_filter(doc : @web.StyleDoc, id : String) -> @web.JsValue {
  json_or_undefined(doc.filter(id))
}

///|
#export_name("doc_set_zoom_range")
pub fn doc_set_zoom_range(
  doc : @web.StyleDoc,
  id : String,
  minzoom : Double,
  maxzoom : Double,
) -> @web.JsValue {
  edited(() => doc.set_zoom_range(id, minzoom, maxzoom))
}

///|
#export_name("doc_has_source")
pub fn doc_has_source(doc : @web.StyleDoc, id : String) -> Bool {
  doc.has_source(id)
}

///|
/// Source `id`'s spec (a GeoJSON data object kept apart reads null), or undefined.
#export_name("doc_source")
pub fn doc_source(doc : @web.StyleDoc, id : String) -> @web.JsValue {
  json_or_undefined(doc.source(id))
}

///|
#export_name("doc_source_data")
pub fn doc_source_data(doc : @web.StyleDoc, id : String) -> @web.JsValue {
  doc.source_data(id).unwrap_or(js_undefined())
}

///|
#export_name("doc_add_source")
pub fn doc_add_source(
  doc : @web.StyleDoc,
  id : String,
  source : @web.JsValue,
) -> @web.JsValue {
  edited(() => doc.add_source(id, source))
}

///|
#export_name("doc_remove_source")
pub fn doc_remove_source(doc : @web.StyleDoc, id : String) -> @web.JsValue {
  edited(() => doc.remove_source(id))
}

///|
#export_name("doc_set_source_data")
pub fn doc_set_source_data(
  doc : @web.StyleDoc,
  id : String,
  data : @web.JsValue,
) -> @web.JsValue {
  edited(() => doc.set_source_data(id, data))
}

///|
#export_name("doc_keep_source_key")
pub fn doc_keep_source_key(
  doc : @web.StyleDoc,
  id : String,
  key : String,
  value : @web.JsValue,
) -> Unit {
  doc.keep_source_key(id, key, value.to_json().unwrap_or(Json::null()))
}

///|
#export_name("doc_keep_source_data")
pub fn doc_keep_source_data(
  doc : @web.StyleDoc,
  id : String,
  data : @web.JsValue,
) -> Unit {
  doc.keep_source_data(id, data)
}

///|
#export_name("doc_set_root")
pub fn doc_set_root(
  doc : @web.StyleDoc,
  key : String,
  value : @web.JsValue,
) -> @web.StyleDoc {
  doc.set_root(key, optional_json(value))
}

///|
#export_name("doc_root")
pub fn doc_root(doc : @web.StyleDoc, key : String) -> @web.JsValue {
  json_or_undefined(doc.root(key))
}

///|
/// The ids of `doc`'s sources that `previous` (a document, or null) lacks or had in another revision.
#export_name("doc_changed_sources")
pub fn doc_changed_sources(
  doc : @web.StyleDoc,
  previous : @web.JsValue,
) -> FixedArray[String] {
  FixedArray::from_array(
    doc.changed_sources(
      if previous.is_nullish() {
        None
      } else {
        Some(as_doc(previous))
      },
    ),
  )
}

///|
#export_name("doc_has_legacy")
pub fn doc_has_legacy(doc : @web.StyleDoc) -> Bool {
  doc.has_legacy()
}

///|
#export_name("is_legacy_filter")
pub fn is_legacy_filter_js(filter : @web.JsValue) -> Bool {
  @web.is_legacy_filter_value(filter)
}

///|
/// `[[id, url], ...]` of the sources given by TileJSON, or an `Error`.
#export_name("doc_tilejson_urls")
pub fn doc_tilejson_urls(doc : @web.StyleDoc, base : String) -> @web.JsValue {
  let urls = doc.tilejson_urls(base) catch {
    e => return @web.js_error(e.message())
  }
  js_pairs(FixedArray::from_iter(urls.iter().map(p => [p.0, p.1])))
}

///|
/// The style as the engine takes it (`@web.StyleDoc::engine`), or an `Error`: `state` the global state
/// object, `documents(url)` the TileJSON document fetched (else undefined), `convert` the legacy
/// converter or null.
#export_name("doc_engine")
pub fn doc_engine(
  doc : @web.StyleDoc,
  state : @web.JsValue,
  documents : @web.JsValue,
  base : String,
  convert : @web.JsValue,
) -> @web.JsValue {
  let values = match state.to_json() {
    Some(Object(o)) => o
    _ => Map([])
  }
  let docs = (url : String) => call_documents(documents, url).to_json()
  let e = try {
    if convert.is_nullish() {
      doc.engine(values, docs, base)
    } else {
      doc.engine(values, docs, base, convert=v => call_convert(convert, v))
    }
  } catch {
    e => return @web.js_error(e.message())
  }
  engine_style_js(e)
}

///|
#export_name("engine_text")
pub fn engine_text(e : @web.JsValue) -> String {
  as_engine_style(e).text
}

///|
/// The GeoJSON sources, `[{id, spec}]` (the spec with its data, as given).
#export_name("engine_geojson")
pub fn engine_geojson(e : @web.JsValue) -> @web.JsValue {
  let g = as_engine_style(e).geojson
  js_entries(
    FixedArray::from_iter(g.iter().map(p => p.0)),
    FixedArray::from_iter(g.iter().map(p => p.1)),
  )
}

///|
/// The attributions of what the drawn style shows at `zoom` (MapLibre's AttributionControl).
#export_name("engine_attributions")
pub fn engine_attributions(
  e : @web.JsValue,
  zoom : Double,
) -> FixedArray[String] {
  FixedArray::from_array(@web.attributions(as_engine_style(e).drawn, zoom))
}

///|
/// The engine's warnings as `[{path, layer?, message}]`.
#export_name("engine_warnings")
pub fn engine_warnings(
  e : @web.JsValue,
  flat : FixedArray[String],
) -> @web.JsValue {
  @web.json_to_js(
    Json::array(
      @web.style_warnings(as_engine_style(e).drawn, flat.iter().collect()),
    ),
  )
}

///|
/// The sources of one of `types`, as `[{id, spec}]` (image, video and canvas sources for media.js).
#export_name("doc_sources_of")
pub fn doc_sources_of(
  doc : @web.StyleDoc,
  types : FixedArray[String],
) -> @web.JsValue {
  let ids = []
  let specs = []
  for id in doc.source_ids() {
    if doc.source(id) is Some(Object(s) as spec) &&
      s.get("type") is Some(String(t)) &&
      types.contains(t) {
      ids.push(id)
      specs.push(@web.json_to_js(spec))
    }
  }
  js_entries(FixedArray::from_array(ids), FixedArray::from_array(specs))
}
