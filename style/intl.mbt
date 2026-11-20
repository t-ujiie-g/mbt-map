///|
/// A host's `Intl` as `FeatureContext::number_format`, `collate` and
/// `resolved_locale` take it, for contexts that get it passed in.
pub(all) struct Intl {
  number_format : (Double, String?, String?, String?, Double?, Double?) -> String?
  collate : (String, String, Bool, Bool, String?) -> Double
  resolved_locale : (String?) -> String?
}

///|
/// What `FeatureContext` does by default: the JavaScript host's `Intl` on the
/// js backend, an approximation elsewhere.
pub fn Intl::fallback() -> Intl {
  {
    number_format: intl_number_format,
    collate: intl_collate,
    resolved_locale: intl_resolved_locale,
  }
}

///|
/// The host hooks an expression's context hands on (`FeatureContext`'s `trig`, `number_text`,
/// `text_number` and `intl`), for packages that evaluate over their own rows.
pub(all) struct Hooks {
  trig : @core.Trig
  number_text : (Double) -> String
  text_number : (String) -> Double
  intl : Intl
}

///|
/// MoonBit's own, for tests and the js backend.
pub fn Hooks::default() -> Hooks {
  {
    trig: @core.Trig::moonbit(),
    number_text: Double::to_string,
    text_number: js_number,
    intl: Intl::fallback(),
  }
}
