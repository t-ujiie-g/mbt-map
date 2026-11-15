///|
/// The scheme prefix of PMTiles archives in source URLs and tile templates.
pub const PMTILES : String = "pmtiles://"

///|
/// The prefix of a GeoTIFF source's key among the documents: its "document" comes from the file's header.
pub const GEOTIFF : String = "geotiff:"

///|
/// `url` resolved against `base` and its scheme (with the colon), or None when it is no URL.
extern "js" fn resolve_url(url : String, base : String) -> FixedArray[String] =
  #|(url, base) => {
  #|  try {
  #|    const u = new URL(url, base);
  #|    return [u.href, u.protocol];
  #|  } catch {
  #|    return [];
  #|  }
  #|}

///|
/// `href` with the tile placeholders `URL` percent-encoded turned back into braces.
extern "js" fn unencode_placeholders(href : String) -> String =
  #|(href) => href.replace(/%7B(z|x|y|prefix|ratio|quadkey|bbox-epsg-3857|bbox)%7D/g, "{$1}")

///|
/// `url` resolved against `base`, refused unless http(s).
pub fn http_url(
  url : String,
  base : String,
  what : String,
) -> String raise StyleEditError {
  let r = resolve_url(url, base)
  guard r.length() == 2 && (r[1] == "http:" || r[1] == "https:") else {
    let shown = if r.length() == 2 { r[0] } else { url }
    raise Invalid("moon-map: \{what} must be an http(s) URL: \{shown}")
  }
  r[0]
}

///|
/// A tile template resolved against `base`, its placeholders kept: http(s), or `pmtiles://` and an
/// http(s) archive.
pub fn resolve_template(
  template : String,
  base : String,
  what~ : String = "tiles",
) -> String raise StyleEditError {
  match template.strip_prefix(PMTILES) {
    Some(archive) =>
      PMTILES + unencode_placeholders(http_url(archive.to_owned(), base, what))
    None => unencode_placeholders(http_url(template, base, what))
  }
}

///|
let tilejson_types : Array[String] = [
  "vector", "raster", "raster-dem", "geotiff",
]

///|
/// The absolute URL of each source's TileJSON (http(s) only), by source id; a PMTiles archive keeps
/// the `pmtiles://` prefix (its document read from the archive's header), a GeoTIFF the `geotiff:` one.
pub fn StyleDoc::tilejson_urls(
  self : StyleDoc,
  base : String,
) -> Map[String, String] raise StyleEditError {
  tilejson_urls_of(self.sources(), base)
}

///|
fn tilejson_urls_of(
  sources : Map[String, Json],
  base : String,
) -> Map[String, String] raise StyleEditError {
  let out = Map([])
  for id, s in sources {
    guard s is Object(src) &&
      string_of(src.get("type")) is Some(kind) &&
      tilejson_types.contains(kind) &&
      string_of(src.get("url")) is Some(url) &&
      !(src.get("tiles") is Some(Array(_))) else {
      continue
    }
    let what = "source \"\{id}\": url"
    out[id] = if kind == "geotiff" {
      GEOTIFF + http_url(url, base, what)
    } else {
      match url.strip_prefix(PMTILES) {
        Some(archive) => PMTILES + http_url(archive.to_owned(), base, what)
        None => http_url(url, base, what)
      }
    }
  }
  out
}

///|
/// The TileJSON keys a source takes, as MapLibre's `loadTileJson` picks them; the source's own win.
let tilejson_keys : Array[String] = [
  "tiles", "minzoom", "maxzoom", "attribution", "bounds", "scheme", "tileSize", "encoding",
]

///|
/// What the engine is handed: `text` (the style's JSON for `Map::set_style`), `drawn` (that style, for
/// attributions and warnings) and the GeoJSON sources (`id`, the spec with its data), whose data
/// only their worker reads.
pub struct EngineStyle {
  text : String
  drawn : Map[String, Json]
  geojson : Array[(String, JsValue)]
}

///|
/// The style as the engine takes it: `convert` applied when a layer may hold legacy filters or
/// property functions, `state` as the defaults of its global state, sources given by `url`
/// completed from `documents` (by `tilejson_urls`; one not come yet is left out with its layers),
/// tile templates resolved against `base`, GeoJSON data split off.
pub fn StyleDoc::engine(
  self : StyleDoc,
  state : Map[String, Json],
  documents : (String) -> Json?,
  base : String,
  convert? : (JsValue) -> JsValue,
) -> EngineStyle raise StyleEditError {
  let spec = match convert {
    Some(f) if self.has_legacy() =>
      match f(json_to_js(Json::object(self.spec))).to_json() {
        Some(Object(o)) => copy_map(o)
        _ => raise Invalid("moon-map: the legacy style could not be converted")
      }
    _ => copy_map(self.spec)
  }
  if !state.is_empty() {
    let defaults = Map([])
    for k, v in state {
      defaults[k] = Json::object({ "default": v })
    }
    spec["state"] = Json::object(defaults)
  }
  let sources = copy_map(object_of(spec.get("sources")))
  let pending = []
  for id, url in tilejson_urls_of(sources, base) {
    guard documents(url) is Some(Object(doc)) else {
      pending.push(id)
      continue
    }
    let merged = Map([])
    for k in tilejson_keys {
      if doc.get(k) is Some(v) {
        merged[k] = v
      }
    }
    for k, v in object_of(sources.get(id)) {
      if k != "url" {
        merged[k] = v
      }
    }
    if merged.get("tiles") is Some(Array(tiles)) {
      merged["tiles"] = Json::array(
        tiles.map(t => {
          match t {
            String(s) => Json::string(resolve_template(s, url))
            _ => t
          }
        }),
      )
    }
    sources[id] = Json::object(merged)
  }
  for id in pending {
    sources.remove(id)
  }
  let geojson = []
  for id, s in sources {
    guard s is Object(src) else { continue }
    if src.get("tiles") is Some(Array(tiles)) {
      let resolved = copy_map(src)
      resolved["tiles"] = Json::array(
        tiles.map(t => {
          match t {
            String(t) => Json::string(resolve_template(t, base))
            _ => t
          }
        }),
      )
      sources[id] = Json::object(resolved)
    } else if src.get("type") == Some(Json::string("geojson")) {
      let with_data = json_to_js(s).with_key(
        "data",
        self.data_of(id).unwrap_or(JsValue::null()),
      )
      geojson.push((id, with_data))
      let without = copy_map(src)
      without["data"] = Json::null()
      sources[id] = Json::object(without)
    }
  }
  spec["sources"] = Json::object(sources)
  if !pending.is_empty() {
    spec["layers"] = Json::array(
      (match spec.get("layers") {
        Some(Array(a)) => a
        _ => []
      }).filter(l => {
        !(l is Object(o) &&
        string_of(o.get("source")) is Some(s) &&
        pending.contains(s))
      }),
    )
  }
  let drawn = spec
  { text: json_text(Json::object(drawn)), drawn, geojson, }
}

///|
/// The engine's warnings (`flat`: path, message, path, ...) as `{path, layer?, message}`, each named
/// after the layer of `drawn` it lies in.
pub fn style_warnings(
  drawn : Map[String, Json],
  flat : Array[String],
) -> Array[Json] {
  let layers = match drawn.get("layers") {
    Some(Array(a)) => a
    _ => []
  }
  let out = []
  let mut i = 0
  while i + 1 < flat.length() {
    let path = flat[i]
    let message = flat[i + 1]
    let warning : Map[String, Json] = { "path": Json::string(path) }
    if layer_index(path) is Some(n) &&
      n < layers.length() &&
      layer_id(layers[n]) is Some(id) {
      warning["layer"] = Json::string(id)
    }
    warning["message"] = Json::string(message)
    out.push(Json::object(warning))
    i += 2
  }
  out
}

///|
/// The index `path` starts with as `layers[<index>]`, if it does.
fn layer_index(path : String) -> Int32? {
  guard path.strip_prefix("layers[") is Some(rest) else { return None }
  let mut n = 0
  let mut digits = 0
  for c in rest {
    if c >= '0' && c <= '9' {
      if digits > 8 {
        return None
      }
      n = n * 10 + (c.to_int() - '0'.to_int())
      digits += 1
    } else {
      return if c == ']' && digits > 0 { Some(n) } else { None }
    }
  }
  None
}
