///|
let map_id = "map"

///|
let liberty_url = "https://tiles.openfreemap.org/styles/liberty"

///|
extern "js" fn fixtures_url() -> String =
  #|() => (typeof location !== "undefined" && new URLSearchParams(location.search).get("local") === "1" ? new URL("../../bench/fixtures/", location.href).href : "")

///|
/// The bench fixtures' URL with `?local=1` (tiles and styles from them only), else None.
let fixtures : String? = match fixtures_url() {
  "" => None
  url => Some(url)
}

///|
/// When the map first drew (as the other examples leave it for the pack test).
extern "js" fn mark_loaded() -> Unit =
  #|() => { window.__loaded = performance.now(); }

///|
extern "js" fn fetch_json(
  url : String,
  ok : (@mbtmap.JsValue) -> Unit,
  failed : (String) -> Unit,
) -> Unit =
  #|(url, ok, failed) => {
  #|  fetch(url, { credentials: "omit" })
  #|    .then((res) => { if (!res.ok) throw new Error(`HTTP ${res.status}`); return res.json(); })
  #|    .then(ok, (e) => failed(String(e?.message ?? e)));
  #|}

///|
/// Fetches the JSON document at `url` (a style) and sends it, or why it failed, as a message.
/// The browser parses it, which keeps a JSON parser out of the app.
fn fetch_style(
  url : String,
  done : @rabbita.Emit[Result[Json, String]],
) -> @rabbita.Cmd {
  @cmd.custom_cmd(scheduler => {
    fetch_json(url, doc => scheduler.add((done.0)(Ok(doc.to_json()))), e => {
      scheduler.add((done.0)(Err(e)))
    })
  })
}

///|
extern "js" fn fixed(x : Double, digits : Int32) -> String =
  #|(x, d) => x.toFixed(d)

///|
/// What a click found: the feature's name, its style layer and what kind of thing it is.
#derive(Eq)
priv struct Picked {
  name : String
  layer : String
  kind : String
}

///|
/// `liberty` is OpenFreeMap's style document once fetched; `picked` is None before a click and
/// `Some(None)` after one on nothing.
#derive(Eq)
priv struct Model {
  liberty : Json?
  base : Base
  labels : Lang
  raised : Bool
  camera : @mbtmap_rabbita.Camera?
  picked : Picked??
  status : String?
}

///|
priv enum Msg {
  LibertyFetched(Result[Json, String])
  Loaded
  Moved(@mbtmap_rabbita.Camera)
  Clicked(@mbtmap_rabbita.Click)
  Found(Array[@mbtmap.Feature])
  FlyTo(City)
  SetBase(Base)
  SetLabels(Lang)
  ToggleBuildings
}

///|
/// The style the model asks for: Liberty once it has come, else GSI.
fn Model::style(self : Model) -> @style.Style {
  match (self.base, self.liberty) {
    (OpenFreeMap, Some(doc)) =>
      openfreemap_style(doc, labels=self.labels, raised=self.raised, fixtures~)
    _ => gsi_style(labels=self.labels, fixtures~)
  }
}

///|
/// Where the map opens: Beijing, or Tokyo with `?local=1` (the fixtures hold Tokyo only).
fn start_city() -> City {
  let key = if fixtures is Some(_) { "tokyo" } else { "beijing" }
  cities.filter(c => c.key == key)[0]
}

///|
/// What the sidebar says about the topmost feature found.
fn picked(features : Array[@mbtmap.Feature], labels : Lang) -> Picked? {
  guard features is [feature, ..] else { None }
  let props = feature.properties
  let kind = match (props, feature.source_layer) {
    ({ "class": String(c), "subclass": String(s), .. }, _) if c != s =>
      "\{c} · \{s}"
    ({ "class": String(c), .. }, _) => c
    (_, Some(layer)) => layer
    _ => feature.source
  }
  Some({
    name: labels.name_of(props).unwrap_or("(no name)"),
    layer: feature.layer,
    kind,
  })
}

///|
fn update(
  model : Model,
  msg : Msg,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  match msg {
    LibertyFetched(result) => {
      let model = match result {
        Ok(doc) => { ..model, liberty: Some(doc), }
        Err(e) =>
          {
            ..model,
            base: Gsi,
            status: Some(
              "OpenFreeMap's style did not load (\{e}); showing GSI.",
            ),
          }
      }
      let start = start_city()
      (
        model,
        @mbtmap_rabbita.setup(
          map_id,
          model.style(),
          center=start.center,
          zoom=start.zoom,
        ),
      )
    }
    Loaded => {
      mark_loaded()
      (model, @rabbita.none)
    }
    Moved(camera) => ({ ..model, camera: Some(camera), }, @rabbita.none)
    Clicked(click) =>
      (
        model,
        @mbtmap_rabbita.query_features(
          map_id,
          click.point,
          emit.map(features => Found(features)),
        ),
      )
    Found(features) =>
      (
        { ..model, picked: Some(picked(features, model.labels)), },
        @rabbita.none,
      )
    FlyTo(city) =>
      (
        model,
        @mbtmap_rabbita.with_map(map_id, map => {
          map.fly_to(center=city.center, zoom=city.zoom, duration=2500.0)
          @rabbita.none
        }),
      )
    SetBase(base) => {
      let model = { ..model, base, }
      (
        model,
        @mbtmap_rabbita.with_map(map_id, map => {
          map.set_style(model.style())
          @rabbita.none
        }),
      )
    }
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
    ToggleBuildings => {
      let raised = !model.raised
      (
        { ..model, raised, },
        @mbtmap_rabbita.with_map(map_id, map => {
          if map.layer_ids().contains(buildings_layer) {
            for p in building_paint(raised) {
              map.set_paint(buildings_layer, p.0, Some(p.1))
            }
          }
          map.ease_to(
            pitch=if raised { 60.0 } else { 0.0 },
            bearing=if raised { -20.0 } else { 0.0 },
            duration=1200.0,
          )
          @rabbita.none
        }),
      )
    }
  }
}

///|
/// A row of buttons of which one or none is chosen (`aria-pressed`).
fn choice(
  items : Array[(String, String, Bool, @rabbita.Cmd)],
  disabled~ : Bool = false,
) -> @html.Html {
  @html.div(
    class="choice",
    items.map(item => {
      let (id, text, on, click) = item
      @html.button(
        id~,
        class=if on { "on" } else { "" },
        disabled~,
        attrs=@html.Attrs::build().aria_pressed(on.to_string()),
        on_click=click,
        text,
      )
    }),
  )
}

///|
fn panel(title : String, body : Array[@html.Html]) -> @html.Html {
  @html.section(class="panel", [@html.h2(title), ..body])
}

///|
fn camera_text(model : Model) -> String {
  match model.camera {
    Some(c) =>
      "\{fixed(c.center.lng, 5)}, \{fixed(c.center.lat, 5)} · zoom \{fixed(c.zoom, 2)} · pitch \{fixed(c.pitch, 0)}°"
    None => "Move the map to see the camera."
  }
}

///|
fn feature_view(model : Model) -> @html.Html {
  match model.picked {
    None => @html.p(id="feature", class="hint", "Click a place on the map.")
    Some(None) => @html.p(id="feature", class="hint", "Nothing drawn there.")
    Some(Some(f)) =>
      @html.div(id="feature", [
        @html.strong(class="name", f.name),
        @html.dl([
          @html.dt("Layer"),
          @html.dd(f.layer),
          @html.dt("Kind"),
          @html.dd(f.kind),
        ]),
      ])
  }
}

///|
fn sidebar(model : Model, emit : @rabbita.Emit[Msg]) -> @html.Html {
  let on_gsi = model.base is Gsi
  let open_openfreemap = if model.liberty is Some(_) {
    emit(SetBase(OpenFreeMap))
  } else {
    @rabbita.none
  }
  @html.aside(class="sidebar", [
    @html.header([
      @html.h1("mbt-map × rabbita"),
      @html.p(
        class="lead",
        "A WebGIS app written in MoonBit: rabbita draws this sidebar, mbt-map draws the map.",
      ),
    ]),
    panel("Fly to", [
      @html.div(
        class="cities",
        cities.map(city => {
          @html.button(id="go-\{city.key}", on_click=emit(FlyTo(city)), [
            @html.span(class="native", city.name),
            @html.span(city.en),
          ])
        }),
      ),
    ]),
    panel("Base map", [
      choice([
        ("base-openfreemap", "OpenFreeMap", !on_gsi, open_openfreemap),
        ("base-gsi", "GSI (Japan)", on_gsi, emit(SetBase(Gsi))),
      ]),
    ]),
    panel("Labels", [
      choice(
        languages.map(lang => {
          (
            "labels-\{lang.code()}",
            lang.label(),
            lang == model.labels,
            emit(SetLabels(lang)),
          )
        }),
      ),
    ]),
    panel("Buildings", [
      choice(
        [("buildings", "3D buildings", model.raised, emit(ToggleBuildings))],
        disabled=on_gsi,
      ),
    ]),
    panel("Camera", [@html.p(id="camera", class="mono", camera_text(model))]),
    panel("Feature", [feature_view(model)]),
    match model.status {
      Some(text) => @html.p(id="status", class="status", text)
      None => @html.fragment([])
    },
  ])
}

///|
fn view(model : Model, emit : @rabbita.Emit[Msg]) -> @html.Html {
  @html.div(class="app", [
    sidebar(model, emit),
    @mbtmap_rabbita.view(map_id, class="map"),
  ])
}

///|
fn app() -> @rabbita.Val[@html.Html] {
  let (model, emit) = @rabbita.create_state_with_init(
    init=emit => {
      let url = match fixtures {
        Some(dir) => "\{dir}styles/ofm-liberty.json"
        None => liberty_url
      }
      (
        {
          liberty: None,
          base: OpenFreeMap,
          labels: Chinese,
          raised: false,
          camera: None,
          picked: None,
          status: None,
        },
        fetch_style(url, emit.map(r => LibertyFetched(r))),
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
