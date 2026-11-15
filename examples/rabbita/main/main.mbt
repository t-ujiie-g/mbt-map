///|
/// Where the buttons go: name, place and zoom (with `?local=1` only Tokyo Station has tiles).
let destinations : Array[(String, @mbtmap.LngLat, Double)] = [
  ("東京駅", @mbtmap.lnglat(139.7671, 35.6812), 15.0),
  ("富士山", @mbtmap.lnglat(138.7274, 35.3606), 11.5),
  ("大阪駅", @mbtmap.lnglat(135.4959, 34.7025), 15.0),
  ("京都駅", @mbtmap.lnglat(135.7588, 34.9858), 14.0),
  ("札幌駅", @mbtmap.lnglat(141.3508, 43.0686), 15.0),
]

///|
let stations : Array[(String, Double, Double)] = [
  ("東京駅", 139.7671, 35.6812),
  ("有楽町駅", 139.7631, 35.6751),
  ("神田駅", 139.7708, 35.6918),
  ("日本橋", 139.7745, 35.6840),
  ("二重橋前駅", 139.7614, 35.6806),
  ("大手町駅", 139.7662, 35.6864),
  ("京橋駅", 139.7701, 35.6767),
]

///|
let map_id = "map"

///|
extern "js" fn local_fixtures() -> String =
  #|() => (new URLSearchParams(location.search).get("local") === "1" ? new URL("../../bench/fixtures/", location.href).href : "")

///|
/// When the map first drew (as the other examples leave it for the pack test).
extern "js" fn mark_loaded() -> Unit =
  #|() => { window.__loaded = performance.now(); }

///|
/// GSI's pale map (the bench fixtures' standard map with `?local=1`) and the stations above.
fn style() -> @style.Style {
  let fixtures = local_fixtures()
  let tiles = if fixtures == "" {
    @style.raster_source(
      tiles=["https://cyberjapandata.gsi.go.jp/xyz/pale/{z}/{x}/{y}.png"],
      tile_size=256.0,
      maxzoom=18.0,
      attribution="国土地理院",
    )
  } else {
    @style.raster_source(
      tiles=["\{fixtures}gsi-std/{z}/{x}/{y}.png"],
      tile_size=256.0,
      minzoom=14.0,
      maxzoom=14.0,
    )
  }
  let features = stations.map(s => {
    let (name, lng, lat) = s
    let feature : Json = {
      "type": "Feature",
      "properties": { "name": name },
      "geometry": { "type": "Point", "coordinates": [lng, lat] },
    }
    feature
  })
  @style.Style::new(
    sources=[
      ("gsi", tiles),
      (
        "stations",
        @style.geojson_source(data={
          "type": "FeatureCollection",
          "features": Json::array(features),
        }),
      ),
    ],
    layers=[
      @style.raster("gsi", source="gsi"),
      @style.circle(
        "stations",
        source="stations",
        circle_radius=@expr.interpolate(@expr.zoom(), [
          (10.0, @expr.num(3.0)),
          (16.0, @expr.num(9.0)),
        ]),
        circle_color=@expr.case_(
          [
            (
              @expr.eq(@expr.get("name"), @expr.str("東京駅")),
              @expr.color("#d6604d"),
            ),
          ],
          default=@expr.color("#2166ac"),
        ),
        circle_stroke_color=@expr.color("#ffffff"),
        circle_stroke_width=@expr.num(2.0),
      ),
      @style.symbol(
        "station-names",
        source="stations",
        text_field=@expr.get("name"),
        text_size=@expr.num(13.0),
        text_offset=@expr.nums([0.0, 1.2]),
        text_anchor=@expr.str("top"),
        text_color=@expr.color("#1c2330"),
        text_halo_color=@expr.color("#ffffff"),
        text_halo_width=@expr.num(1.5),
      ),
    ],
  )
}

///|
#derive(Eq)
priv struct Model {
  camera : @mbtmap_rabbita.Camera?
  clicked : @mbtmap_rabbita.Click?
  station : String?
  loaded : Bool
  large : Bool
}

///|
priv enum Msg {
  Loaded
  Moved(@mbtmap_rabbita.Camera)
  Clicked(@mbtmap_rabbita.Click)
  Picked(Array[@mbtmap.Feature])
  Go(Int32)
  Resize
}

///|
fn update(
  model : Model,
  msg : Msg,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  match msg {
    Loaded => {
      mark_loaded()
      ({ ..model, loaded: true, }, @rabbita.none)
    }
    Moved(camera) => ({ ..model, camera: Some(camera), }, @rabbita.none)
    Clicked(click) =>
      (
        { ..model, clicked: Some(click), },
        @mbtmap_rabbita.query_features(
          map_id,
          click.point,
          layers=["stations"],
          emit.map(features => Picked(features)),
        ),
      )
    Picked(features) => {
      let station = match features {
        [first, ..] =>
          match first.properties {
            { "name": String(name), .. } => Some(name)
            _ => None
          }
        [] => None
      }
      ({ ..model, station, }, @rabbita.none)
    }
    Go(i) => {
      let (_, center, zoom) = destinations[i]
      (
        model,
        @mbtmap_rabbita.with_map(map_id, map => {
          map.fly_to(center~, zoom~, duration=1200.0)
          @rabbita.none
        }),
      )
    }
    Resize => {
      let large = !model.large
      let radius = if large { 14.0 } else { 9.0 }
      (
        { ..model, large, },
        @mbtmap_rabbita.with_map(map_id, map => {
          map.set_paint(
            "stations",
            "circle-radius",
            Some(
              @expr.interpolate(@expr.zoom(), [
                (10.0, @expr.num(radius / 3.0)),
                (16.0, @expr.num(radius)),
              ]),
            ),
          )
          @rabbita.none
        }),
      )
    }
  }
}

///|
extern "js" fn fixed(x : Double, digits : Int32) -> String =
  #|(x, d) => x.toFixed(d)

///|
fn readout(model : Model) -> Array[@html.Html] {
  let lines = []
  if model.camera is Some(c) {
    lines.push(
      @html.p(
        id="camera",
        "中心 \{fixed(c.center.lng, 5)}, \{fixed(c.center.lat, 5)}　ズーム \{fixed(c.zoom, 2)}",
      ),
    )
  } else {
    lines.push(
      @html.p(
        id="camera",
        if model.loaded {
          "地図を動かすと中心が出ます"
        } else {
          "読み込み中…"
        },
      ),
    )
  }
  match model.clicked {
    Some(click) =>
      lines.push(
        @html.p(
          id="clicked",
          "クリック \{fixed(click.lnglat.lng, 5)}, \{fixed(click.lnglat.lat, 5)}" +
          (match model.station {
            Some(name) => "（\{name}）"
            None => ""
          }),
        ),
      )
    None =>
      lines.push(
        @html.p(
          id="clicked",
          "駅の点をクリックすると名前が出ます",
        ),
      )
  }
  lines
}

///|
fn view(model : Model, emit : @rabbita.Emit[Msg]) -> @html.Html {
  let buttons = destinations.mapi((i, d) => {
    @html.button(class="go", on_click=emit(Go(i)), d.0)
  })
  buttons.push(
    @html.button(
      id="resize",
      on_click=emit(Resize),
      if model.large {
        "点を小さく"
      } else {
        "点を大きく"
      },
    ),
  )
  @html.div(class="app", [
    @html.header([
      @html.h1("mbt-map × rabbita"),
      @html.p(
        class="lead",
        "MoonBit の Web フレームワーク rabbita のアプリに、mbt-map の地図を <mbt-map> 要素として置いています。",
      ),
    ]),
    @html.nav(buttons),
    @mbtmap_rabbita.view(
      map_id,
      css="display:block;height:60vh;min-height:320px",
    ),
    @html.section(class="readout", readout(model)),
  ])
}

///|
fn app() -> @rabbita.Val[@html.Html] {
  let (model, emit) = @rabbita.create_state_with_init(
    init=_ => {
      (
        {
          camera: None,
          clicked: None,
          station: None,
          loaded: false,
          large: false,
        },
        @mbtmap_rabbita.setup(
          map_id,
          style(),
          center=destinations[0].1,
          zoom=destinations[0].2,
        ),
      )
    },
    update~,
    subscriptions=(_, emit) => {
      @mbtmap_rabbita.events(
        map_id,
        on_load=emit(Loaded),
        on_moveend=emit.map(c => Moved(c)),
        on_click=emit.map(c => Clicked(c)),
      )
    },
  )
  model.map(m => view(m, emit))
}

///|
fn main {
  @rabbita.new(app).mount("app")
}
