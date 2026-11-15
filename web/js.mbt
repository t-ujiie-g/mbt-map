///|
/// A JS value handed over as it is: a GeoJSON source's data, a page's object, a function.
#external
pub type JsValue

///|
pub extern "js" fn JsValue::null() -> JsValue =
  #|() => null

///|
pub extern "js" fn JsValue::is_nullish(self : JsValue) -> Bool =
  #|(v) => v === null || v === undefined

///|
/// Whether the value is a JS object (arrays included), not null.
pub extern "js" fn JsValue::is_object(self : JsValue) -> Bool =
  #|(v) => typeof v === "object" && v !== null

///|
extern "js" fn JsValue::same(self : JsValue, other : JsValue) -> Bool =
  #|(a, b) => a === b

///|
/// `JSON.stringify` of the value (`""` for undefined, which JSON cannot write).
pub extern "js" fn JsValue::json_text(self : JsValue) -> String =
  #|(v) => JSON.stringify(v) ?? ""

///|
/// A plain copy, as `JSON.parse(JSON.stringify(v))` makes it, so later changes by the page do
/// not reach the map.
pub extern "js" fn JsValue::copy(self : JsValue) -> JsValue =
  #|(v) => v === undefined ? v : JSON.parse(JSON.stringify(v))

///|
extern "js" fn js_string(s : String) -> JsValue =
  #|(s) => s

///|
extern "js" fn js_number(n : Double) -> JsValue =
  #|(n) => n

///|
extern "js" fn js_bool(b : Bool) -> JsValue =
  #|(b) => b

///|
extern "js" fn js_array(items : FixedArray[JsValue]) -> JsValue =
  #|(items) => items

///|
extern "js" fn js_object(
  keys : FixedArray[String],
  values : FixedArray[JsValue],
) -> JsValue =
  #|(keys, values) => {
  #|  const o = {};
  #|  keys.forEach((k, i) => Object.defineProperty(o, k, { value: values[i], writable: true, enumerable: true, configurable: true }));
  #|  return o;
  #|}

///|
/// The JSON value `v` stands for (as `JSON.stringify` writes it), rebuilt as a MoonBit Json
/// through the given constructors; None for undefined and functions.
extern "js" fn js_to_json_with(
  v : JsValue,
  null_ : () -> Json,
  bool_ : (Bool) -> Json,
  num : (Double) -> Json,
  str : (String) -> Json,
  arr : (FixedArray[Json]) -> Json,
  obj : (FixedArray[String], FixedArray[Json]) -> Json,
  none : () -> Json?,
  some : (Json) -> Json?,
) -> Json? =
  #|(v, mkNull, mkBool, mkNum, mkStr, mkArr, mkObj, none, some) => {
  #|  const text = JSON.stringify(v);
  #|  if (text === undefined) return none();
  #|  const build = (x) => {
  #|    if (x === null) return mkNull();
  #|    switch (typeof x) {
  #|      case "boolean": return mkBool(x);
  #|      case "number": return mkNum(x);
  #|      case "string": return mkStr(x);
  #|    }
  #|    if (Array.isArray(x)) return mkArr(x.map(build));
  #|    const keys = Object.keys(x);
  #|    return mkObj(keys, keys.map((k) => build(x[k])));
  #|  };
  #|  return some(build(JSON.parse(text)));
  #|}

///|
/// The JSON value of `v` (a copy, as `JSON.parse(JSON.stringify(v))`); None for undefined and functions.
pub fn JsValue::to_json(self : JsValue) -> Json? {
  js_to_json_with(
    self,
    () => Json::null(),
    b => Json::boolean(b),
    n => Json::number(n),
    s => Json::string(s),
    items => Json::array(items.iter().collect()),
    (keys, values) => {
      let m = Map([])
      for i, k in keys {
        m[k] = values[i]
      }
      Json::object(m)
    },
    () => None,
    j => Some(j),
  )
}

///|
/// `j` as a plain JS value; object keys are defined as own properties, so `__proto__` stays a key.
pub fn json_to_js(j : Json) -> JsValue {
  match j {
    Null => JsValue::null()
    True => js_bool(true)
    False => js_bool(false)
    Number(n, ..) => js_number(n)
    String(s) => js_string(s)
    Array(items) =>
      js_array(FixedArray::from_iter(items.iter().map(json_to_js)))
    Object(o) => {
      let keys = FixedArray::make(o.length(), "")
      let values = FixedArray::make(o.length(), JsValue::null())
      let mut i = 0
      for k, v in o {
        keys[i] = k
        values[i] = json_to_js(v)
        i += 1
      }
      js_object(keys, values)
    }
  }
}

///|
/// The JSON text of `j`, written by the host's `JSON.stringify` (a MoonBit writer costs bundle size).
pub fn json_text(j : Json) -> String {
  json_to_js(j).json_text()
}

///|
extern "js" fn js_get(o : JsValue, key : String) -> JsValue =
  #|(o, k) => (o !== null && typeof o === "object" && Object.hasOwn(o, k) ? o[k] : undefined)

///|
/// Own property `key` of `self`, or undefined.
pub fn JsValue::get(self : JsValue, key : String) -> JsValue {
  js_get(self, key)
}

///|
extern "js" fn js_with_key(
  o : JsValue,
  key : String,
  value : JsValue,
) -> JsValue =
  #|(o, k, v) => {
  #|  const out = { ...o };
  #|  Object.defineProperty(out, k, { value: v, writable: true, enumerable: true, configurable: true });
  #|  return out;
  #|}

///|
/// A shallow copy of object `self` with own key `key` set to `value`.
pub fn JsValue::with_key(
  self : JsValue,
  key : String,
  value : JsValue,
) -> JsValue {
  js_with_key(self, key, value)
}

///|
/// An `Error` with `message`, which the facade throws.
pub extern "js" fn js_error(message : String) -> JsValue =
  #|(m) => new Error(m)
