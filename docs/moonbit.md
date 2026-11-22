# MoonBit

mbt-map can be used from MoonBit web apps (js target). `t-ujiie-g/mbtmap` is a typed MoonBit API over the npm package, which does the drawing; styles, layers and expressions are written with MoonBit functions and labelled arguments. `t-ujiie-g/mbtmap_rabbita` puts the map in apps made with the [rabbita](https://mooncakes.io/docs/moonbit-community/rabbita) web framework, its events arriving as messages.

## Setup

```sh
moon add t-ujiie-g/mbtmap
moon add t-ujiie-g/mbtmap_rabbita   # for rabbita apps
npm install mbt-map
```

```moonbit
// moon.pkg
import {
  "t-ujiie-g/mbtmap",
  "t-ujiie-g/mbtmap/style",
  "t-ujiie-g/mbtmap/expr",
}
```

The MoonBit packages import the npm package's modules by name (`mbt-map/moonbit`, `mbt-map/element`), so the page resolves them either through a bundler or through an import map; the workers and wasm load from beside those modules ([Getting started](./getting-started.md#how-files-are-loaded)).

```html
<script type="importmap">
  {
    "imports": {
      "mbt-map": "./node_modules/mbt-map/dist/index.js",
      "mbt-map/moonbit": "./node_modules/mbt-map/dist/moonbit.js",
      "mbt-map/element": "./node_modules/mbt-map/dist/element.js"
    }
  }
</script>
<script type="module" src="./app.js"></script>
```

`app.js` is the output of `moon build --target js` of an executable package (`pkgtype(kind: "executable")` with `options(link: { "js": { "format": "esm" } })`).

## Packages

| Package | What it holds |
|---|---|
| `t-ujiie-g/mbtmap` | `Map` (camera, sources and layers, events, queries, feature state), `LngLat`, `Point`, `Bounds` |
| `t-ujiie-g/mbtmap/style` | `Style`, `Source`, `Layer`: one function per layer type and per source type |
| `t-ujiie-g/mbtmap/expr` | `Expr`: constants and style expressions |
| `t-ujiie-g/mbtmap_rabbita` | the `<mbt-map>` element as a rabbita view, its events as messages |

## Styles and expressions

Each layer type of the style specification is a function whose paint and layout properties are labelled arguments, named as in the specification with `_` for `-` (`circle_color` for `circle-color`). The functions are generated from the specification, so every property is there; each takes an `@expr.Expr`. Sources are functions with the specification's properties typed (`tile_size~ : Double`, `tiles~ : Array[String]`, …).

```moonbit
fn style() -> @style.Style {
  @style.Style::new(
    sources=[
      (
        "gsi",
        @style.raster_source(
          tiles=["https://cyberjapandata.gsi.go.jp/xyz/pale/{z}/{x}/{y}.png"],
          tile_size=256.0,
          attribution="国土地理院",
        ),
      ),
      ("places", @style.geojson_source(data={ "type": "FeatureCollection", "features": [] })),
    ],
    layers=[
      @style.raster("gsi", source="gsi"),
      @style.circle(
        "places",
        source="places",
        circle_radius=@expr.interpolate(@expr.zoom(), [
          (10.0, @expr.num(3.0)),
          (16.0, @expr.num(9.0)),
        ]),
        circle_color=@expr.match_(
          @expr.get("kind"),
          [("station", @expr.color("#2166ac"))],
          default=@expr.color("#d6604d"),
        ),
      ),
      @style.symbol(
        "place-names",
        source="places",
        text_field=@expr.get("name"),
        text_offset=@expr.nums([0.0, 1.2]),
        text_anchor=@expr.str("top"),
      ),
    ],
  )
}
```

- Layers: `fill`, `line`, `symbol`, `circle`, `heatmap`, `fill_extrusion`, `raster`, `hillshade`, `color_relief`, `background`. Each takes `id`, `source~` (not `background`), `source_layer?` and `filter?` (the layers that draw features), `minzoom?`, `maxzoom?` and the properties.
- Sources: `vector_source`, `raster_source`, `raster_dem_source`, `geojson_source`, `image_source`, `video_source`.
- `Style::new(sources~, layers~, name?, sprite?, glyphs?, center?, zoom?, bearing?, pitch?, terrain?, sky?, projection?, light?)`, `Style::url(url)` for a style document at a URL.
- Anything written as JSON can be passed as it is: `Layer::json`, `Source::json`, `Style::json`, `@expr.raw`.

Expressions (`@expr`):

| Kind | Functions |
|---|---|
| Constants | `num`, `str`, `bool`, `color`, `nums`, `literal` |
| Feature and map | `get`, `has`, `id`, `geometry_type`, `zoom`, `feature_state`, `global_state` |
| Choice | `match_`, `case_`, `coalesce`, `step`, `interpolate` (`curve=Linear`, `Exponential(base)`, `CubicBezier(…)`) |
| Comparison and logic | `eq`, `ne`, `lt`, `le`, `gt`, `ge`, `all`, `any`, `not_`, `in_` |
| Arithmetic and text | `add`, `sub`, `mul`, `div`, `concat`, `to_string`, `to_number`, `image` |

## The map

```moonbit
fn main {
  let tokyo = @mbtmap.lnglat(139.7671, 35.6812)
  let map = @mbtmap.Map::new("map", style=style(), center=tokyo, zoom=14.0)
  map.on(Load, _ => {
    map.set_data("places", {
      "type": "Feature",
      "properties": { "name": "東京駅", "kind": "station" },
      "geometry": { "type": "Point", "coordinates": [tokyo.lng, tokyo.lat] },
    })
  })
  |> ignore
  map.on_layer(Click, ["places"], e => map.fly_to(center?=e.lnglat, zoom=16.0)) |> ignore
}
```

`Map` methods:

| Group | Methods |
|---|---|
| Create and remove | `Map::new(container, style~, center?, zoom?, bearing?, pitch?, min_zoom?, max_zoom?, min_pitch?, max_pitch?, interactive?, attribution?)`, `remove` |
| Camera | `center`, `zoom`, `bearing`, `pitch`, `jump_to`, `ease_to`, `fly_to`, `fit_bounds`, `project`, `unproject`; `padding`, `set_padding` and `padding?` on the three moves (`Padding::new(left=320.0)`: pixels kept free along the edges, see [The map](./map.md#padding)) |
| Style | `set_style`, `style` (the style drawn, as `Json`), `add_source`, `remove_source`, `set_data`, `add_layer(layer, before?)`, `remove_layer`, `move_layer`, `layer_ids` |
| Properties | `set_paint(id, name, Expr?)`, `set_layout(id, name, Expr?)`, `set_filter(id, Expr?)`: `None` goes back to the default |
| Feature state | `set_feature_state(source, id, state, source_layer?)` |
| Events | `on(EventType, f) -> Listener`, `on_layer(EventType, layers, f)`, `Listener::off` |
| Queries | `query_rendered_features(point?, layers?, done)`: the features are passed to `done` |

`EventType` lists the map's events (`Load`, `Idle`, `Click`, `MouseMove`, `MoveEnd`, `Error`, …). An `Event` carries its `kind`, `point` and `lnglat` for mouse events, the `features` under the pointer for layer events, the `error` message and the `source` id where they apply. `Idle` also comes right after `Load`.

The rest of the npm package's API (data, analysis, 3D, …) is not wrapped yet; MoonBit code can call it through `extern "js"` functions.

## rabbita

`t-ujiie-g/mbtmap_rabbita` places the `<mbt-map>` element in a rabbita view and connects it by its id:

| Function | Kind | What it does |
|---|---|---|
| `view(id, css?, class?)` | view | the `<mbt-map>` element; give it a height |
| `setup(id, style, center?, zoom?, bearing?, pitch?, padding?)` | Cmd | gives the map its style and camera once the view is on the page (the map is made then); run it again to change the style |
| `events(id, on_load?, on_idle?, on_move?, on_moveend?, on_click?, on_error?)` | Sub | the element's events as messages: `Camera` (center, zoom, bearing, pitch), `Click` (point, place, camera), the error message |
| `with_map(id, f)` | Cmd | runs `f` on the typed `@mbtmap.Map` (once it has loaded) and then the command `f` returns |
| `query_features(id, point, layers?, emit)` | Cmd | sends the features drawn at a point as a message |

```moonbit
#derive(Eq, Default)
priv struct Model {
  camera : @mbtmap_rabbita.Camera?
  picked : Int
}

priv enum Msg {
  Moved(@mbtmap_rabbita.Camera)
  Clicked(@mbtmap_rabbita.Click)
  Picked(Array[@mbtmap.Feature])
  GoTo(@mbtmap.LngLat)
}

fn update(model : Model, msg : Msg, emit : @rabbita.Emit[Msg]) -> (Model, @rabbita.Cmd) {
  match msg {
    Moved(camera) => ({ ..model, camera: Some(camera) }, @rabbita.none)
    Clicked(click) =>
      (model, @mbtmap_rabbita.query_features("map", click.point, layers=["places"], emit.map(f => Picked(f))))
    Picked(features) => ({ ..model, picked: features.length() }, @rabbita.none)
    GoTo(place) =>
      (model, @mbtmap_rabbita.with_map("map", map => {
        map.fly_to(center=place, zoom=15.0)
        @rabbita.none
      }))
  }
}

fn app() -> @rabbita.Val[@html.Html] {
  let (model, emit) = @rabbita.create_state_with_init(
    init=_ => (Model::default(), @mbtmap_rabbita.setup("map", style(), center=@mbtmap.lnglat(139.7671, 35.6812), zoom=14.0)),
    update~,
    subscriptions=(_, emit) => @mbtmap_rabbita.events(
      "map",
      on_moveend=emit.map(c => Moved(c)),
      on_click=emit.map(c => Clicked(c)),
    ),
  )
  model.map(m => @html.div([
    @html.button(on_click=emit(GoTo(@mbtmap.lnglat(138.7274, 35.3606))), "Mt Fuji"),
    @mbtmap_rabbita.view("map", css="display:block;height:60vh"),
  ]))
}

fn main {
  @rabbita.new(app).mount("app")
}
```

### The example app

[`examples/rabbita/`](../examples/rabbita/) is a complete WebGIS app in MoonBit: a rabbita sidebar beside the map, buttons that fly to Beijing, Shanghai, Shenzhen, Hong Kong, Chengdu, Hangzhou, Tokyo and Osaka, a base map switch between OpenFreeMap's Liberty (OpenStreetMap vector tiles of the world) and GSI's pale map (raster tiles of Japan), labels in Chinese, Japanese, English or each place's own name, 3D buildings, the camera from `on_moveend` and the feature clicked from `query_features`. Its styles are built in MoonBit: GSI's and the cities' with the typed functions, Liberty's from the style document it fetches, edited as `Json`.

Switching the labels' language finds the symbol layers that draw names in the style the map draws and sets their `text-field`:

```moonbit
fn Lang::text_field(self : Lang) -> @expr.Expr {
  match self.keys() {   // ["name:ja", "name"], ["name:en", "name_en", "name"], …
    [key] => @expr.get(key)
    keys => @expr.coalesce(keys.map(@expr.get))
  }
}

// in update:
SetLabels(labels) =>
  (
    { ..model, labels, },
    @mbtmap_rabbita.with_map(map_id, map => {
      guard map.style() is Some(style) else { @rabbita.none }
      for id in name_layers(style) {
        map.set_layout(id, "text-field", Some(labels.text_field()))
      }
      @rabbita.none
    }),
  )
```

`npm --prefix bench run examples` builds it (`moon build --target js`, then esbuild) and serves it at `/examples/rabbita/`.
