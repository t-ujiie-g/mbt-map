///|
/// A style layer (MapLibre's layer specification). The functions named after the layer types
/// (`fill`, `line`, `circle`, …; `layers.g.mbt`) build one with types; `Layer::json` takes one as written.
pub struct Layer {
  priv json : Json
}

///|
/// `json` as it is: a layer written as JSON.
pub fn Layer::json(json : Json) -> Layer {
  { json, }
}

///|
pub fn Layer::to_json(self : Layer) -> Json {
  self.json
}

///|
/// The layer's id ("" when it has none).
pub fn Layer::id(self : Layer) -> String {
  match self.json {
    Object(o) =>
      match o.get("id") {
        Some(String(id)) => id
        _ => ""
      }
    _ => ""
  }
}

///|
/// A source (MapLibre's source specification). `vector_source`, `raster_source`, `raster_dem_source`,
/// `geojson_source`, `image_source` and `video_source` (`sources.g.mbt`) build one with types;
/// `Source::json` takes one as written.
pub struct Source {
  priv json : Json
}

///|
pub fn Source::json(json : Json) -> Source {
  { json, }
}

///|
pub fn Source::to_json(self : Source) -> Json {
  self.json
}

///|
/// A style: a document at a URL (fetched without credentials), or one written here.
pub struct Style {
  priv url : String?
  priv json : Json
}

///|
/// The style document at `url`.
pub fn Style::url(url : String) -> Style {
  { url: Some(url), json: Json::null(), }
}

///|
/// `json` as it is: a style document written as JSON.
pub fn Style::json(json : Json) -> Style {
  { url: None, json, }
}

///|
/// A style of `sources` (id, source) and `layers` (bottom first), with the sprite and glyphs URLs,
/// the default camera and the top-level `terrain`, `sky`, `projection` and `light` as JSON if given.
pub fn Style::new(
  sources~ : Array[(String, Source)],
  layers~ : Array[Layer],
  name? : String,
  sprite? : String,
  glyphs? : String,
  center? : (Double, Double),
  zoom? : Double,
  bearing? : Double,
  pitch? : Double,
  terrain? : Json,
  sky? : Json,
  projection? : Json,
  light? : Json,
) -> Style {
  let o : Map[String, Json] = { "version": 8 }
  put_string(o, "name", name)
  put_string(o, "sprite", sprite)
  put_string(o, "glyphs", glyphs)
  if center is Some((lng, lat)) {
    o["center"] = [lng, lat]
  }
  put_number(o, "zoom", zoom)
  put_number(o, "bearing", bearing)
  put_number(o, "pitch", pitch)
  put_json(o, "terrain", terrain)
  put_json(o, "sky", sky)
  put_json(o, "projection", projection)
  put_json(o, "light", light)
  let s = Map([])
  for p in sources {
    s[p.0] = p.1.json
  }
  o["sources"] = Json::object(s)
  o["layers"] = Json::array(layers.map(l => l.json))
  { url: None, json: Json::object(o), }
}

///|
/// The style's URL, if it is given by one.
pub fn Style::to_url(self : Style) -> String? {
  self.url
}

///|
/// The style document written here (null for a style given by URL).
pub fn Style::to_json(self : Style) -> Json {
  self.json
}

///|
fn put_expr(o : Map[String, Json], key : String, v : @expr.Expr?) -> Unit {
  if v is Some(e) {
    o[key] = e.to_json()
  }
}

///|
fn put_number(o : Map[String, Json], key : String, v : Double?) -> Unit {
  if v is Some(n) {
    o[key] = Json::number(n)
  }
}

///|
fn put_string(o : Map[String, Json], key : String, v : String?) -> Unit {
  if v is Some(s) {
    o[key] = Json::string(s)
  }
}

///|
fn put_bool(o : Map[String, Json], key : String, v : Bool?) -> Unit {
  if v is Some(b) {
    o[key] = Json::boolean(b)
  }
}

///|
fn put_json(o : Map[String, Json], key : String, v : Json?) -> Unit {
  if v is Some(j) {
    o[key] = j
  }
}

///|
fn put_numbers(o : Map[String, Json], key : String, v : Array[Double]?) -> Unit {
  if v is Some(a) {
    o[key] = Json::array(a.map(n => Json::number(n)))
  }
}

///|
fn put_strings(o : Map[String, Json], key : String, v : Array[String]?) -> Unit {
  if v is Some(a) {
    o[key] = Json::array(a.map(Json::string))
  }
}

///|
/// A layer of `kind` from the parts the generated functions gather.
fn layer(
  id : String,
  kind : String,
  source : String?,
  source_layer : String?,
  filter : @expr.Expr?,
  minzoom : Double?,
  maxzoom : Double?,
  paint : Map[String, Json],
  layout : Map[String, Json],
) -> Layer {
  let o : Map[String, Json] = {
    "id": Json::string(id),
    "type": Json::string(kind),
  }
  put_string(o, "source", source)
  put_string(o, "source-layer", source_layer)
  put_expr(o, "filter", filter)
  put_number(o, "minzoom", minzoom)
  put_number(o, "maxzoom", maxzoom)
  if !layout.is_empty() {
    o["layout"] = Json::object(layout)
  }
  if !paint.is_empty() {
    o["paint"] = Json::object(paint)
  }
  { json: Json::object(o), }
}
