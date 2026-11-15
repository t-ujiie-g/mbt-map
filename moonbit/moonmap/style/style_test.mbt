///|
test "layer functions name the specification's properties and leave out what is not given" {
  let l = @style.circle(
    "places",
    source="places",
    source_layer="poi",
    filter=@expr.has("name"),
    minzoom=10,
    circle_radius=@expr.num(6),
    circle_color=@expr.get("color"),
    circle_sort_key=@expr.get("rank"),
  )
  assert_eq(l.id(), "places")
  assert_eq(l.to_json(), {
    "id": "places",
    "type": "circle",
    "source": "places",
    "source-layer": "poi",
    "filter": ["has", "name"],
    "minzoom": 10,
    "layout": { "circle-sort-key": ["get", "rank"] },
    "paint": { "circle-radius": 6, "circle-color": ["get", "color"] },
  })
  assert_eq(@style.line("roads", source="gsi").to_json(), {
    "id": "roads",
    "type": "line",
    "source": "gsi",
  })
}

///|
test "background takes no source; raster-like layers take no source layer or filter" {
  assert_eq(
    @style.background("bg", background_color=@expr.color("#fff")).to_json(),
    {
      "id": "bg",
      "type": "background",
      "paint": { "background-color": "#fff" },
    },
  )
  assert_eq(
    @style.raster("photo", source="photo", raster_opacity=@expr.num(0.5)).to_json(),
    {
      "id": "photo",
      "type": "raster",
      "source": "photo",
      "paint": { "raster-opacity": 0.5 },
    },
  )
  assert_eq(
    @style.fill_extrusion(
      "buildings",
      source="v",
      fill_extrusion_height=@expr.get("h"),
    ).to_json(),
    {
      "id": "buildings",
      "type": "fill-extrusion",
      "source": "v",
      "paint": { "fill-extrusion-height": ["get", "h"] },
    },
  )
}

///|
test "source functions take the specification's keys in snake case, required ones labelled" {
  assert_eq(
    @style.vector_source(
      tiles=["https://t/{z}/{x}/{y}.pbf"],
      maxzoom=14,
      promote_id="id",
    ).to_json(),
    {
      "type": "vector",
      "tiles": ["https://t/{z}/{x}/{y}.pbf"],
      "maxzoom": 14,
      "promoteId": "id",
    },
  )
  assert_eq(
    @style.geojson_source(
      data="places.geojson",
      cluster=true,
      cluster_radius=40,
    ).to_json(),
    {
      "type": "geojson",
      "data": "places.geojson",
      "cluster": true,
      "clusterRadius": 40,
    },
  )
  assert_eq(
    @style.raster_dem_source(
      url="dem.json",
      tile_size=256,
      encoding="terrarium",
    ).to_json(),
    {
      "type": "raster-dem",
      "url": "dem.json",
      "tileSize": 256,
      "encoding": "terrarium",
    },
  )
  assert_eq(
    @style.image_source(
      coordinates=[[0, 1], [1, 1], [1, 0], [0, 0]],
      url="a.png",
    ).to_json(),
    {
      "type": "image",
      "url": "a.png",
      "coordinates": [[0, 1], [1, 1], [1, 0], [0, 0]],
    },
  )
}

///|
test "Style::new writes version 8, its options, sources and layers; url and json styles as given" {
  let s = @style.Style::new(
    sources=[("v", @style.vector_source(url="https://t/tiles.json"))],
    layers=[@style.Layer::json({ "id": "bg", "type": "background" })],
    sprite="https://t/sprite",
    center=(139.7, 35.7),
    zoom=10,
  )
  assert_eq(s.to_url(), None)
  assert_eq(s.to_json(), {
    "version": 8,
    "sprite": "https://t/sprite",
    "center": [139.7, 35.7],
    "zoom": 10,
    "sources": { "v": { "type": "vector", "url": "https://t/tiles.json" } },
    "layers": [{ "id": "bg", "type": "background" }],
  })
  assert_eq(
    @style.Style::url("https://t/style.json").to_url(),
    Some("https://t/style.json"),
  )
  assert_eq(@style.Style::json({ "version": 8 }).to_json(), { "version": 8 })
  assert_eq(@style.Source::json({ "type": "vector" }).to_json(), {
    "type": "vector",
  })
  assert_eq(@style.Layer::json(Json::null()).id(), "")
}
