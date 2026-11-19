///|
/// What an expression reads of a table: the properties and geometry type of `row`.
priv struct Row {
  table : @geom.Table
  mut row : Int32
  hooks : @style.Hooks
}

///|
fn value_of(p : @geom.Prop) -> @style.Value {
  match p {
    Null => Null
    Bool(b) => Bool(b)
    Num(n) => Num(n)
    Str(s) => Str(s)
  }
}

///|
/// A result as a cell holds it: errors, NaN and what is not a boolean, number or string
/// (colors, arrays, formatted text) become null, as MapLibre keeps a cluster property.
fn prop_of(v : @style.Value) -> @geom.Prop {
  match v {
    Bool(b) => Bool(b)
    Num(n) if !n.is_nan() => Num(n)
    Str(s) => Str(s)
    _ => Null
  }
}

///|
impl @style.FeatureContext for Row with fn property(self, key) {
  self.table.column(key).bind(c => c.values[self.row]).map(value_of)
}

///|
/// GeoJSON's name of the row's geometry, `"Unknown"` without one.
impl @style.FeatureContext for Row with fn geometry_type(self) {
  match self.table.kinds[self.row] {
    NoGeometry => "Unknown"
    Point => "Point"
    MultiPoint => "MultiPoint"
    LineString => "LineString"
    MultiLineString => "MultiLineString"
    Polygon => "Polygon"
    MultiPolygon => "MultiPolygon"
  }
}

///|
impl @style.FeatureContext for Row with fn id(self) {
  self.table.ids[self.row].map(value_of).unwrap_or(Null)
}

///|
impl @style.FeatureContext for Row with fn trig(self) {
  self.hooks.trig
}

///|
impl @style.FeatureContext for Row with fn number_text(self, x) {
  (self.hooks.number_text)(x)
}

///|
impl @style.FeatureContext for Row with fn text_number(self, s) {
  (self.hooks.text_number)(s)
}

///|
impl @style.FeatureContext for Row with fn number_format(
  self,
  x,
  locale,
  currency,
  unit,
  min,
  max,
) {
  (self.hooks.intl.number_format)(x, locale, currency, unit, min, max)
}

///|
impl @style.FeatureContext for Row with fn collate(
  self,
  a,
  b,
  case,
  diacritic,
  locale,
) {
  (self.hooks.intl.collate)(a, b, case, diacritic, locale)
}

///|
impl @style.FeatureContext for Row with fn resolved_locale(self, locale) {
  (self.hooks.intl.resolved_locale)(locale)
}
