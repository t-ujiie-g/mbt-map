///|
/// A value of a style property or filter: a constant or one of MapLibre's expressions
/// (https://maplibre.org/maplibre-style-spec/expressions/), held as the JSON the style takes.
pub struct Expr {
  priv json : Json
}

///|
/// The JSON the style takes for `self`.
pub fn Expr::to_json(self : Expr) -> Json {
  self.json
}

///|
/// `json` as it is: an expression or constant written as JSON.
pub fn raw(json : Json) -> Expr {
  { json, }
}

///|
fn op(name : String, args : Array[Expr]) -> Expr {
  let items = [Json::string(name)]
  for a in args {
    items.push(a.json)
  }
  { json: Json::array(items), }
}

///|
pub fn num(n : Double) -> Expr {
  { json: Json::number(n), }
}

///|
pub fn str(s : String) -> Expr {
  { json: Json::string(s), }
}

///|
pub fn bool(b : Bool) -> Expr {
  { json: Json::boolean(b), }
}

///|
/// A CSS color: `"#2166ac"`, `"rgba(0, 0, 0, 0.5)"`, `"steelblue"`, …
pub fn color(css : String) -> Expr {
  { json: Json::string(css), }
}

///|
/// An array of numbers (`line-dasharray`, `text-offset`, …).
pub fn nums(values : Array[Double]) -> Expr {
  { json: Json::array(values.map(n => Json::number(n))), }
}

///|
/// `["literal", value]`: an array or object taken as data, not as an expression.
pub fn literal(value : Json) -> Expr {
  { json: Json::array([Json::string("literal"), value]), }
}

///|
/// The feature's property `key` (`["get", key]`).
pub fn get(key : String) -> Expr {
  op("get", [str(key)])
}

///|
/// Whether the feature has property `key`.
pub fn has(key : String) -> Expr {
  op("has", [str(key)])
}

///|
/// The feature's id.
pub fn id() -> Expr {
  op("id", [])
}

///|
/// The feature's geometry type: `"Point"`, `"LineString"` or `"Polygon"`.
pub fn geometry_type() -> Expr {
  op("geometry-type", [])
}

///|
/// The map's zoom (only as the input of a top-level `interpolate` or `step`).
pub fn zoom() -> Expr {
  op("zoom", [])
}

///|
/// The feature's state `key` (`Map::set_feature_state`).
pub fn feature_state(key : String) -> Expr {
  op("feature-state", [str(key)])
}

///|
/// The map's global state `key`.
pub fn global_state(key : String) -> Expr {
  op("global-state", [str(key)])
}

///|
/// The output of the first label of `cases` equal to `input`, else `default`. Labels are strings,
/// numbers or arrays of them.
pub fn match_(
  input : Expr,
  cases : Array[(Json, Expr)],
  default~ : Expr,
) -> Expr {
  let args = [input]
  for c in cases {
    args.push({ json: c.0, })
    args.push(c.1)
  }
  args.push(default)
  op("match", args)
}

///|
/// The output of the first condition of `branches` that holds, else `default`.
pub fn case_(branches : Array[(Expr, Expr)], default~ : Expr) -> Expr {
  let args = []
  for b in branches {
    args.push(b.0)
    args.push(b.1)
  }
  args.push(default)
  op("case", args)
}

///|
/// The first of `values` that is not null.
pub fn coalesce(values : Array[Expr]) -> Expr {
  op("coalesce", values)
}

///|
/// How `interpolate` goes between stops: straight, exponentially with a base, or along a cubic
/// Bézier curve.
pub(all) enum Curve {
  Linear
  Exponential(Double)
  CubicBezier(Double, Double, Double, Double)
}

///|
/// The outputs of `stops` (input, output; inputs ascending) interpolated at `input` along `curve`.
pub fn interpolate(
  input : Expr,
  stops : Array[(Double, Expr)],
  curve~ : Curve = Linear,
) -> Expr {
  let kind : Json = match curve {
    Linear => ["linear"]
    Exponential(base) => ["exponential", base]
    CubicBezier(x1, y1, x2, y2) => ["cubic-bezier", x1, y1, x2, y2]
  }
  let args = [{ json: kind, }, input]
  for s in stops {
    args.push(num(s.0))
    args.push(s.1)
  }
  op("interpolate", args)
}

///|
/// `base` below the first stop, then the output of the last stop (input, output) not above `input`.
pub fn step(input : Expr, base : Expr, stops : Array[(Double, Expr)]) -> Expr {
  let args = [input, base]
  for s in stops {
    args.push(num(s.0))
    args.push(s.1)
  }
  op("step", args)
}

///|
pub fn eq(a : Expr, b : Expr) -> Expr {
  op("==", [a, b])
}

///|
pub fn ne(a : Expr, b : Expr) -> Expr {
  op("!=", [a, b])
}

///|
pub fn lt(a : Expr, b : Expr) -> Expr {
  op("<", [a, b])
}

///|
pub fn le(a : Expr, b : Expr) -> Expr {
  op("<=", [a, b])
}

///|
pub fn gt(a : Expr, b : Expr) -> Expr {
  op(">", [a, b])
}

///|
pub fn ge(a : Expr, b : Expr) -> Expr {
  op(">=", [a, b])
}

///|
pub fn all(conditions : Array[Expr]) -> Expr {
  op("all", conditions)
}

///|
pub fn any(conditions : Array[Expr]) -> Expr {
  op("any", conditions)
}

///|
pub fn not_(condition : Expr) -> Expr {
  op("!", [condition])
}

///|
/// Whether `input` is one of `values` (`["in", input, ["literal", values]]`).
pub fn in_(input : Expr, values : Array[Json]) -> Expr {
  op("in", [input, literal(Json::array(values))])
}

///|
pub fn add(a : Expr, b : Expr) -> Expr {
  op("+", [a, b])
}

///|
pub fn sub(a : Expr, b : Expr) -> Expr {
  op("-", [a, b])
}

///|
pub fn mul(a : Expr, b : Expr) -> Expr {
  op("*", [a, b])
}

///|
pub fn div(a : Expr, b : Expr) -> Expr {
  op("/", [a, b])
}

///|
/// The text of `values` joined.
pub fn concat(values : Array[Expr]) -> Expr {
  op("concat", values)
}

///|
pub fn to_string(value : Expr) -> Expr {
  op("to-string", [value])
}

///|
pub fn to_number(value : Expr) -> Expr {
  op("to-number", [value])
}

///|
/// The style image `name` (`icon-image`, `*-pattern`).
pub fn image(name : String) -> Expr {
  op("image", [str(name)])
}
