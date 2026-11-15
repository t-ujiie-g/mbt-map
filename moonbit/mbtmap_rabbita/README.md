# t-ujiie-g/mbtmap_rabbita

Maps in [rabbita](https://mooncakes.io/docs/moonbit-community/rabbita) apps (js target): the `<mbt-map>` element of the [`mbt-map`](https://www.npmjs.com/package/mbt-map) npm package as a view, its events as messages, and the typed API of [`t-ujiie-g/mbtmap`](https://mooncakes.io/docs/t-ujiie-g/mbtmap) from `update`.

```sh
moon add t-ujiie-g/mbtmap_rabbita
npm install mbt-map   # or an import map for "mbt-map" and "mbt-map/element"
```

```moonbit
priv enum Msg {
  Moved(@mbtmap_rabbita.Camera)
  Clicked(@mbtmap_rabbita.Click)
  GoTo(@mbtmap.LngLat)
}

fn app() -> @rabbita.Val[@html.Html] {
  let (model, emit) = @rabbita.create_state_with_init(
    // Give the map its style and camera once the view is on the page.
    init=_ => (None, @mbtmap_rabbita.setup("map", style(), center=@mbtmap.lnglat(139.7671, 35.6812), zoom=14.0)),
    update=(model, msg, _) => match msg {
      Moved(camera) => (Some(camera), @rabbita.none)
      Clicked(_) => (model, @rabbita.none)
      GoTo(place) =>
        (model, @mbtmap_rabbita.with_map("map", map => {
          map.fly_to(center=place, zoom=15.0)
          @rabbita.none
        }))
    },
    // The element's events as messages.
    subscriptions=(_, emit) => @mbtmap_rabbita.events(
      "map",
      on_moveend=emit.map(c => Moved(c)),
      on_click=emit.map(c => Clicked(c)),
    ),
  )
  model.map(camera => @html.div([
    @html.button(on_click=emit(GoTo(@mbtmap.lnglat(138.7274, 35.3606))), "Mt Fuji"),
    @mbtmap_rabbita.view("map", css="display:block;height:400px"),
    @html.p(match camera {
      Some(c) => "zoom \{c.zoom}"
      None => ""
    }),
  ]))
}
```

- `view(id, css?, class?)`: the `<mbt-map>` element.
- `setup(id, style, center?, zoom?, bearing?, pitch?)`: a command that gives the map its style (`@style.Style`) and camera after the view renders; run it again to change the style.
- `events(id, on_load?, on_idle?, on_move?, on_moveend?, on_click?, on_error?)`: a subscription.
- `with_map(id, f)`: runs `f` on the typed `@mbtmap.Map` and then the command it returns; `query_features(id, point, layers?, emit)` sends the features at a point as a message.

The repository's `examples/rabbita/` is a complete app. Licensed under the Apache License 2.0.
