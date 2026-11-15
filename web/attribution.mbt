// The attributions MapLibre GL JS 6.16.0's AttributionControl shows (`_updateAttributions`,
// BSD-3-Clause, Copyright (c) 2020 MapLibre contributors; see NOTICE).

///|
fn number_or(j : Json?, default : Double) -> Double {
  match j {
    Some(Number(n, ..)) => n
    _ => default
  }
}

///|
/// Whether a layer is drawn at `zoom`, as MapLibre's `isHidden` reads `minzoom`, `maxzoom` and
/// `visibility` (a zero bound is no bound).
fn layer_shown(layer : Map[String, Json], zoom : Double) -> Bool {
  let min = number_or(layer.get("minzoom"), 0.0)
  let max = number_or(layer.get("maxzoom"), 0.0)
  !(min != 0.0 && zoom < min) &&
  !(max != 0.0 && zoom >= max) &&
  object_of(layer.get("layout")).get("visibility") != Some(Json::string("none"))
}

///|
/// The attributions of the sources a layer shown at `zoom` or the terrain uses, in source order,
/// then shortest first with any contained in another left out (MapLibre's order).
pub fn attributions(style : Map[String, Json], zoom : Double) -> Array[String] {
  let used : Array[String] = []
  for
    l in (match style.get("layers") {
      Some(Array(a)) => a
      _ => []
    }) {
    let layer = object_of(Some(l))
    if string_of(layer.get("source")) is Some(s) && layer_shown(layer, zoom) {
      used.push(s)
    }
  }
  if string_of(object_of(style.get("terrain")).get("source")) is Some(t) {
    used.push(t)
  }
  let out : Array[String] = []
  for id, s in object_of(style.get("sources")) {
    if used.contains(id) &&
      string_of(object_of(Some(s)).get("attribution")) is Some(a) &&
      !out.contains(a) &&
      !blank(a) {
      out.push(a)
    }
  }
  // Shortest first, ties in source order (a stable sort, as JS's).
  let sorted : Array[String] = []
  for a in out {
    let mut at = sorted.length()
    while at > 0 && sorted[at - 1].length() > a.length() {
      at -= 1
    }
    sorted.insert(at, a)
  }
  let kept = []
  for i, a in sorted {
    if !sorted[i + 1:].iter().any(b => b.contains(a)) {
      kept.push(a)
    }
  }
  kept
}

///|
extern "js" fn blank(s : String) -> Bool =
  #|(s) => s.trim() === ""
