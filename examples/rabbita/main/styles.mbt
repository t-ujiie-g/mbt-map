///|
/// The base maps: OpenFreeMap's vector tiles of the world and GSI's raster tiles of Japan.
#derive(Eq)
priv enum Base {
  OpenFreeMap
  Gsi
}

///|
/// The language labels are drawn in: `Local` is each place's own name.
#derive(Eq)
priv enum Lang {
  Chinese
  Japanese
  English
  Local
}

///|
let languages : Array[Lang] = [Chinese, Japanese, English, Local]

///|
fn Lang::code(self : Lang) -> String {
  match self {
    Chinese => "zh"
    Japanese => "ja"
    English => "en"
    Local => "local"
  }
}

///|
fn Lang::label(self : Lang) -> String {
  match self {
    Chinese => "中文"
    Japanese => "日本語"
    English => "English"
    Local => "Local"
  }
}

///|
/// The name keys tried in turn: OpenMapTiles' `name:<lang>`, then its `name_en` (English or Latin
/// letters), then the local `name`.
fn Lang::keys(self : Lang) -> Array[String] {
  match self {
    Chinese => ["name:zh-Hans", "name:zh", "name"]
    Japanese => ["name:ja", "name"]
    English => ["name:en", "name_en", "name"]
    Local => ["name"]
  }
}

///|
/// The `text-field` of name labels: `["coalesce", ["get", "name:zh-Hans"], ["get", "name:zh"], …]`.
fn Lang::text_field(self : Lang) -> @expr.Expr {
  match self.keys() {
    [key] => @expr.get(key)
    keys => @expr.coalesce(keys.map(@expr.get))
  }
}

///|
/// A feature's name as `text_field` picks it.
fn Lang::name_of(self : Lang, properties : Json) -> String? {
  guard properties is Object(props) else { None }
  for key in self.keys() {
    if props.get(key) is Some(String(name)) {
      return Some(name)
    }
  }
  None
}

///|
/// Whether a `text-field` reads a name (`["get", "name…"]` anywhere in it), not a road number.
fn reads_name(field : Json) -> Bool {
  match field {
    [String("get"), String(key)] => key.has_prefix("name")
    Array(items) => items.iter().any(reads_name)
    _ => false
  }
}

///|
fn is_name_layer(layer : Json) -> Bool {
  layer is { "type": "symbol", "layout": { "text-field": field, .. }, .. } &&
  reads_name(field)
}

///|
/// The ids of the symbol layers of `style` (a style document) that draw names.
fn name_layers(style : Json) -> Array[String] {
  guard style is { "layers": Array(layers), .. } else { [] }
  layers.filter_map(layer => {
    guard is_name_layer(layer) && layer is { "id": String(id), .. } else {
      None
    }
    Some(id)
  })
}

///|
/// Liberty's extrusion layer for buildings.
let buildings_layer = "building-3d"

///|
/// The paint of `buildings_layer`: OpenMapTiles' heights when `raised`, else flat.
fn building_paint(raised : Bool) -> Array[(String, @expr.Expr)] {
  if raised {
    [
      ("fill-extrusion-height", @expr.get("render_height")),
      ("fill-extrusion-base", @expr.get("render_min_height")),
      ("fill-extrusion-opacity", @expr.num(0.9)),
    ]
  } else {
    [
      ("fill-extrusion-height", @expr.num(0.0)),
      ("fill-extrusion-base", @expr.num(0.0)),
      ("fill-extrusion-opacity", @expr.num(0.8)),
    ]
  }
}

///|
/// A copy of the JSON object `object` with `key` set to `value`.
fn with_field(object : Json, key : String, value : Json) -> Json {
  let fields = match object {
    Object(fields) => fields.copy()
    _ => Map([])
  }
  fields[key] = value
  Json::object(fields)
}

///|
/// A copy of `layer` (a layer document) with its `group` ("paint" or "layout") property `name` set.
fn with_property(
  layer : Json,
  group : String,
  name : String,
  value : @expr.Expr,
) -> Json {
  let props = match layer {
    Object(fields) => fields.get(group).unwrap_or(Json::empty_object())
    _ => Json::empty_object()
  }
  with_field(layer, group, with_field(props, name, value.to_json()))
}

///|
/// `layer` with its names in `labels` and, for the buildings, raised or flat.
fn restyle(layer : Json, labels~ : Lang, raised~ : Bool) -> Json {
  if layer is { "id": String(id), .. } && id == buildings_layer {
    building_paint(raised).fold(init=layer, (l, p) => {
      with_property(l, "paint", p.0, p.1)
    })
  } else if is_name_layer(layer) {
    with_property(layer, "layout", "text-field", labels.text_field())
  } else {
    layer
  }
}

///|
let openfreemap_attribution = "OpenFreeMap © OpenMapTiles Data from OpenStreetMap"

///|
fn cities_source() -> @style.Source {
  @style.geojson_source(data=cities_geojson())
}

///|
/// The cities drawn over either base map: a dot and its name below.
fn city_layers(labels : Lang) -> Array[@style.Layer] {
  [
    @style.circle(
      "cities",
      source="cities",
      circle_radius=@expr.interpolate(@expr.zoom(), [
        (3.0, @expr.num(4.0)),
        (15.0, @expr.num(9.0)),
      ]),
      circle_color=@expr.color("#e4572e"),
      circle_stroke_color=@expr.color("#ffffff"),
      circle_stroke_width=@expr.num(2.5),
    ),
    @style.symbol(
      "city-names",
      source="cities",
      text_field=labels.text_field(),
      text_size=@expr.num(16.0),
      text_offset=@expr.nums([0.0, 1.0]),
      text_anchor=@expr.str("top"),
      text_allow_overlap=@expr.bool(true),
      text_color=@expr.color("#7a1f0c"),
      text_halo_color=@expr.color("#ffffff"),
      text_halo_width=@expr.num(2.0),
    ),
  ]
}

///|
/// GSI's pale map (the standard map of the bench fixtures in `fixtures`) with the cities.
fn gsi_style(labels~ : Lang, fixtures~ : String?) -> @style.Style {
  let tiles = match fixtures {
    None =>
      @style.raster_source(
        tiles=["https://cyberjapandata.gsi.go.jp/xyz/pale/{z}/{x}/{y}.png"],
        tile_size=256.0,
        maxzoom=18.0,
        attribution="国土地理院",
      )
    Some(dir) =>
      @style.raster_source(
        tiles=["\{dir}gsi-std/{z}/{x}/{y}.png"],
        tile_size=256.0,
        minzoom=14.0,
        maxzoom=14.0,
        attribution="国土地理院",
      )
  }
  let layers = [@style.raster("gsi", source="gsi")]
  layers.append(city_layers(labels))
  @style.Style::new(
    sources=[("gsi", tiles), ("cities", cities_source())],
    layers~,
  )
}

///|
/// OpenFreeMap's Liberty style `doc` with the cities on top, names in `labels` and buildings `raised`
/// or flat. With `fixtures` its tiles and sprite come from the bench fixtures (z14 around Tokyo).
fn openfreemap_style(
  doc : Json,
  labels~ : Lang,
  raised~ : Bool,
  fixtures~ : String?,
) -> @style.Style {
  guard doc is { "sources": Object(sources), "layers": Array(layers), .. } &&
    doc is Object(fields) else {
    gsi_style(labels~, fixtures~)
  }
  let style = fields.copy()
  let sources = sources.copy()
  let mut layers = layers
  match fixtures {
    Some(dir) => {
      sources["openmaptiles"] = @style.vector_source(
        tiles=["\{dir}ofm-planet/{z}/{x}/{y}.pbf"],
        minzoom=14.0,
        maxzoom=14.0,
        attribution=openfreemap_attribution,
      ).to_json()
      sources.remove("ne2_shaded")
      layers = layers.filter(l => !(l is { "source": "ne2_shaded", .. }))
      style["sprite"] = Json::string("\{dir}sprites/ofm/sprite")
      style.remove("glyphs")
    }
    None =>
      // A source's own attribution wins over its TileJSON's, which is HTML.
      if sources.get("openmaptiles") is Some(source) {
        sources["openmaptiles"] = with_field(
          source,
          "attribution",
          Json::string(openfreemap_attribution),
        )
      }
  }
  sources["cities"] = cities_source().to_json()
  let drawn = layers.map(l => restyle(l, labels~, raised~))
  drawn.append(city_layers(labels).map(l => l.to_json()))
  style["sources"] = Json::object(sources)
  style["layers"] = Json::array(drawn)
  @style.Style::json(Json::object(style))
}
